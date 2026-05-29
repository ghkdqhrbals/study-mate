import XCTest
import CloudKit
import UserNotifications
@testable import StudyMate

final class StudyMateTests: XCTestCase {
    func testFreshInstallRequiresOnboarding() {
        let suiteName = "StudyMateTests-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defer {
            defaults.removePersistentDomain(forName: suiteName)
        }

        let store = SettingsStore(defaults: defaults)

        XCTAssertFalse(store.loadHasCompletedOnboarding())
    }

    func testExistingSettingsSkipOnboardingByDefault() {
        let suiteName = "StudyMateTests-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defer {
            defaults.removePersistentDomain(forName: suiteName)
        }

        let store = SettingsStore(defaults: defaults)
        store.saveSettings(
            StudySettings(
                topic: "Swift",
                difficulty: .beginner,
                customPrompt: "짧게",
                intervalMinutes: 15
            )
        )

        XCTAssertTrue(store.loadHasCompletedOnboarding())
    }

    @MainActor
    func testSkippingOnboardingPersistsFlagAndPausesWithoutAPIKey() {
        let suiteName = "StudyMateTests-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defer {
            defaults.removePersistentDomain(forName: suiteName)
        }

        let store = SettingsStore(defaults: defaults)
        let appState = AppState(settingsStore: store, openAIClient: SpyOpenAIClient())

        appState.skipOnboarding()

        XCTAssertTrue(appState.hasCompletedOnboarding)
        XCTAssertTrue(store.loadHasCompletedOnboarding())
        XCTAssertFalse(appState.isRunning)
        XCTAssertFalse(store.loadIsRunning())
        XCTAssertEqual(appState.selectedTab, .settings)
    }

    @MainActor
    func testCompletingOnboardingWithoutAPIKeySavesSettingsAndPauses() async {
        let suiteName = "StudyMateTests-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defer {
            defaults.removePersistentDomain(forName: suiteName)
        }

        let store = SettingsStore(defaults: defaults)
        let appState = AppState(settingsStore: store, openAIClient: SpyOpenAIClient())
        let settings = StudySettings(
            topic: "Redis",
            difficulty: .level6,
            appLanguage: .english,
            language: .english,
            customPrompt: "Ask one focused question.",
            intervalMinutes: 20
        )

        await appState.completeOnboarding(settings: settings, apiKey: "")

        XCTAssertTrue(appState.hasCompletedOnboarding)
        XCTAssertTrue(store.loadHasCompletedOnboarding())
        XCTAssertEqual(store.loadSettings().topic, "Redis")
        XCTAssertEqual(store.loadSettings().difficulty, .level6)
        XCTAssertEqual(store.loadSettings().appLanguage, .english)
        XCTAssertEqual(store.loadSettings().language, .english)
        XCTAssertFalse(appState.isRunning)
        XCTAssertFalse(store.loadIsRunning())
        XCTAssertTrue(appState.hasAPIKeyError)
        XCTAssertEqual(appState.selectedTab, .study)
    }

    func testSettingsRoundTripUsesUserDefaults() {
        let suiteName = "StudyMateTests-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defer {
            defaults.removePersistentDomain(forName: suiteName)
        }

        let store = SettingsStore(defaults: defaults)
        let settings = StudySettings(
            topic: "자료구조",
            difficulty: .advanced,
            appLanguage: .english,
            language: .english,
            openAIModel: "gpt-5.4",
            notificationSound: .chime,
            customPrompt: "면접처럼 질문해줘.",
            intervalMinutes: 7
        )

        store.saveSettings(settings)

        XCTAssertEqual(store.loadSettings(), settings)
    }

    func testTopicGroupingNormalizesCaseSpacingAndSeparators() {
        let topics = [
            "Spring Boot",
            "spring boot",
            "spring-boot",
            "SpringBoot",
            "spring_boot"
        ]

        let keys = Set(topics.map { TopicGrouping.normalizedKey(for: $0, fallback: "Study") })

        XCTAssertEqual(keys.count, 1)
    }

    func testCloudSyncSettingsRoundTripUsesUserDefaults() {
        let suiteName = "StudyMateTests-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defer {
            defaults.removePersistentDomain(forName: suiteName)
        }

        let store = SettingsStore(defaults: defaults)
        let syncedAt = Date(timeIntervalSince1970: 123)

        store.saveIsCloudSyncEnabled(true)
        store.saveCloudSyncSnapshotUpdatedAt(syncedAt)

        XCTAssertTrue(store.loadIsCloudSyncEnabled())
        XCTAssertEqual(store.loadCloudSyncSnapshotUpdatedAt(), syncedAt)
    }

    @MainActor
    func testCloudSyncPullsNewerSnapshotIntoAppState() async {
        let suiteName = "StudyMateTests-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defer {
            defaults.removePersistentDomain(forName: suiteName)
        }

        let store = SettingsStore(defaults: defaults)
        store.saveIsCloudSyncEnabled(true)
        let question = QuestionItem(question: "iPhone 동기화 질문", expectedAnswerHint: "힌트", createdAt: Date(timeIntervalSince1970: 10))
        let record = StudyRecord(question: question, topic: "iCloud", difficulty: .level4)
        let snapshot = CloudSyncSnapshot(
            updatedAt: Date(timeIntervalSince1970: 100),
            apiKey: "sk-remote",
            settings: StudySettings(topic: "iCloud", difficulty: .level4, customPrompt: "질문", intervalMinutes: 9),
            currentQuestion: question,
            questionHistory: [question],
            lastAnswer: "초안",
            gradingResult: nil,
            isRunning: false,
            hasCompletedOnboarding: true,
            studyRecords: [record]
        )
        let syncService = FakeCloudSyncService(remoteSnapshot: snapshot)
        let appState = AppState(settingsStore: store, openAIClient: SpyOpenAIClient(), cloudSyncService: syncService)

        await appState.syncCloudNow()

        XCTAssertEqual(appState.settings.topic, "iCloud")
        XCTAssertEqual(appState.currentQuestion?.question, question.question)
        XCTAssertEqual(appState.lastAnswer, "초안")
        XCTAssertEqual(appState.studyRecords, [record])
        XCTAssertEqual(appState.apiKey, "sk-remote")
        XCTAssertEqual(store.loadAPIKey(), "sk-remote")
        XCTAssertFalse(appState.isRunning)
    }

    @MainActor
    func testCloudSyncPushesLocalSnapshotWhenRemoteIsEmpty() async {
        let suiteName = "StudyMateTests-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defer {
            defaults.removePersistentDomain(forName: suiteName)
        }

        let store = SettingsStore(defaults: defaults)
        store.saveIsCloudSyncEnabled(true)
        store.saveAPIKey("sk-local")
        store.saveSettings(StudySettings(topic: "SwiftUI", difficulty: .level5, customPrompt: "질문", intervalMinutes: 12))
        let syncService = FakeCloudSyncService(remoteSnapshot: nil)
        let appState = AppState(settingsStore: store, openAIClient: SpyOpenAIClient(), cloudSyncService: syncService)

        await appState.syncCloudNow()

        XCTAssertEqual(syncService.savedSnapshot?.settings.topic, "SwiftUI")
        XCTAssertEqual(syncService.savedSnapshot?.settings.difficulty, .level5)
        XCTAssertEqual(syncService.savedSnapshot?.apiKey, "sk-local")
    }

    @MainActor
    func testCloudSyncFailureKeepsToggleEnabledAndReportsQuota() async {
        let suiteName = "StudyMateTests-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defer {
            defaults.removePersistentDomain(forName: suiteName)
        }

        let store = SettingsStore(defaults: defaults)
        store.saveIsCloudSyncEnabled(true)
        store.saveSettings(StudySettings(topic: "SwiftUI", difficulty: .level5, customPrompt: "질문", intervalMinutes: 12))
        let syncService = FakeCloudSyncService(remoteSnapshot: nil, saveError: CKError(.quotaExceeded))
        let appState = AppState(settingsStore: store, openAIClient: SpyOpenAIClient(), cloudSyncService: syncService)

        await appState.syncCloudNow()

        XCTAssertTrue(appState.isCloudSyncEnabled)
        XCTAssertTrue(store.loadIsCloudSyncEnabled())
        XCTAssertTrue(appState.hasCloudSyncError)
        XCTAssertFalse(appState.isCloudSyncing)
        XCTAssertEqual(appState.cloudSyncMessage, appState.strings.syncQuotaExceeded)
    }

    @MainActor
    func testCloudSyncFirstEnablePullsRemoteAndPreservesLocalEnableState() async {
        let suiteName = "StudyMateTests-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defer {
            defaults.removePersistentDomain(forName: suiteName)
        }

        let store = SettingsStore(defaults: defaults)
        store.saveIsCloudSyncEnabled(true)
        store.saveAPIKey("sk-local")
        store.saveHasCompletedOnboarding(true)
        let localSettings = StudySettings(topic: "Local iPhone", difficulty: .level6, customPrompt: "로컬", intervalMinutes: 11)
        store.saveSettings(localSettings)
        let localQuestion = QuestionItem(question: "로컬 질문", expectedAnswerHint: nil, createdAt: Date(timeIntervalSince1970: 20))
        store.replaceStudyRecords([
            StudyRecord(question: localQuestion, topic: localSettings.topic, difficulty: localSettings.difficulty)
        ])

        let remoteQuestion = QuestionItem(question: "맥 질문", expectedAnswerHint: nil, createdAt: Date(timeIntervalSince1970: 10))
        let remoteSnapshot = CloudSyncSnapshot(
            updatedAt: Date(timeIntervalSince1970: 100),
            settings: StudySettings(topic: "Mac", difficulty: .level4, customPrompt: "원격", intervalMinutes: 9),
            currentQuestion: remoteQuestion,
            questionHistory: [remoteQuestion],
            lastAnswer: "",
            gradingResult: nil,
            isRunning: false,
            hasCompletedOnboarding: false,
            studyRecords: [
                StudyRecord(question: remoteQuestion, topic: "Mac", difficulty: .level4)
            ]
        )
        let syncService = FakeCloudSyncService(remoteSnapshot: remoteSnapshot)
        let appState = AppState(settingsStore: store, openAIClient: SpyOpenAIClient(), cloudSyncService: syncService)

        await appState.syncCloudNow()

        XCTAssertTrue(appState.isCloudSyncEnabled)
        XCTAssertTrue(store.loadIsCloudSyncEnabled())
        XCTAssertTrue(appState.hasCompletedOnboarding)
        XCTAssertEqual(appState.settings.topic, "Mac")
        XCTAssertEqual(appState.currentQuestion, remoteQuestion)
        XCTAssertEqual(syncService.savedSnapshot?.settings.topic, "Mac")
        XCTAssertEqual(syncService.savedSnapshot?.studyRecords.count, 2)
        XCTAssertEqual(syncService.savedSnapshot?.apiKey, "sk-local")
    }

    @MainActor
    func testCloudSyncMergesLocalAPIKeyIntoNewerRemoteSnapshotWhenRemoteKeyIsMissing() async {
        let suiteName = "StudyMateTests-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defer {
            defaults.removePersistentDomain(forName: suiteName)
        }

        let store = SettingsStore(defaults: defaults)
        store.saveIsCloudSyncEnabled(true)
        store.saveCloudSyncSnapshotUpdatedAt(Date(timeIntervalSince1970: 50))
        store.saveAPIKey("sk-local")

        let remoteQuestion = QuestionItem(question: "원격 질문", expectedAnswerHint: nil, createdAt: Date(timeIntervalSince1970: 100))
        let remoteSnapshot = CloudSyncSnapshot(
            updatedAt: Date(timeIntervalSince1970: 100),
            apiKey: nil,
            settings: StudySettings(topic: "Remote", difficulty: .level4, customPrompt: "원격", intervalMinutes: 9),
            currentQuestion: remoteQuestion,
            questionHistory: [remoteQuestion],
            lastAnswer: "",
            gradingResult: nil,
            isRunning: false,
            hasCompletedOnboarding: true,
            studyRecords: [
                StudyRecord(question: remoteQuestion, topic: "Remote", difficulty: .level4)
            ]
        )
        let syncService = FakeCloudSyncService(remoteSnapshot: remoteSnapshot)
        let appState = AppState(settingsStore: store, openAIClient: SpyOpenAIClient(), cloudSyncService: syncService)

        await appState.syncCloudNow()

        XCTAssertEqual(appState.settings.topic, "Remote")
        XCTAssertEqual(appState.apiKey, "sk-local")
        XCTAssertEqual(store.loadAPIKey(), "sk-local")
        XCTAssertEqual(syncService.savedSnapshot?.settings.topic, "Remote")
        XCTAssertEqual(syncService.savedSnapshot?.apiKey, "sk-local")
    }

    @MainActor
    func testCloudSyncPreservesRemoteAPIKeyWhenPushingNewerLocalSnapshot() async {
        let suiteName = "StudyMateTests-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defer {
            defaults.removePersistentDomain(forName: suiteName)
        }

        let store = SettingsStore(defaults: defaults)
        store.saveIsCloudSyncEnabled(true)
        store.saveCloudSyncSnapshotUpdatedAt(Date(timeIntervalSince1970: 200))
        store.saveSettings(StudySettings(topic: "Local", difficulty: .level6, customPrompt: "로컬", intervalMinutes: 10))

        let remoteQuestion = QuestionItem(question: "원격 질문", expectedAnswerHint: nil, createdAt: Date(timeIntervalSince1970: 100))
        let remoteSnapshot = CloudSyncSnapshot(
            updatedAt: Date(timeIntervalSince1970: 100),
            apiKey: "sk-remote",
            settings: StudySettings(topic: "Remote", difficulty: .level4, customPrompt: "원격", intervalMinutes: 9),
            currentQuestion: remoteQuestion,
            questionHistory: [remoteQuestion],
            lastAnswer: "",
            gradingResult: nil,
            isRunning: false,
            hasCompletedOnboarding: true,
            studyRecords: [
                StudyRecord(question: remoteQuestion, topic: "Remote", difficulty: .level4)
            ]
        )
        let syncService = FakeCloudSyncService(remoteSnapshot: remoteSnapshot)
        let appState = AppState(settingsStore: store, openAIClient: SpyOpenAIClient(), cloudSyncService: syncService)

        await appState.syncCloudNow()

        XCTAssertEqual(syncService.savedSnapshot?.settings.topic, "Local")
        XCTAssertEqual(syncService.savedSnapshot?.apiKey, "sk-remote")
        XCTAssertEqual(appState.apiKey, "sk-remote")
        XCTAssertEqual(store.loadAPIKey(), "sk-remote")
    }

    @MainActor
    func testCloudSyncDoesNotRewriteSnapshotWhenContentAlreadyMatches() async {
        let suiteName = "StudyMateTests-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defer {
            defaults.removePersistentDomain(forName: suiteName)
        }

        let store = SettingsStore(defaults: defaults)
        store.saveIsCloudSyncEnabled(true)
        store.saveHasCompletedOnboarding(true)
        store.saveCloudSyncSnapshotUpdatedAt(Date(timeIntervalSince1970: 200))

        let remoteSnapshot = CloudSyncSnapshot(
            updatedAt: Date(timeIntervalSince1970: 100),
            settings: .default,
            currentQuestion: nil,
            questionHistory: [],
            lastAnswer: "",
            gradingResult: nil,
            isRunning: true,
            hasCompletedOnboarding: true,
            studyRecords: []
        )
        let syncService = FakeCloudSyncService(remoteSnapshot: remoteSnapshot)
        let appState = AppState(settingsStore: store, openAIClient: SpyOpenAIClient(), cloudSyncService: syncService)

        await appState.syncCloudNow()

        XCTAssertNil(syncService.savedSnapshot)
        XCTAssertEqual(syncService.saveSnapshotCallCount, 0)
        XCTAssertEqual(appState.cloudSyncMessage, appState.strings.syncAlreadyCurrent)
    }

    @MainActor
    func testCloudSyncMergesRemoteRecordsWhenPushingNewerLocalSnapshot() async {
        let suiteName = "StudyMateTests-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defer {
            defaults.removePersistentDomain(forName: suiteName)
        }

        let store = SettingsStore(defaults: defaults)
        store.saveIsCloudSyncEnabled(true)
        store.saveCloudSyncSnapshotUpdatedAt(Date(timeIntervalSince1970: 200))
        let localSettings = StudySettings(topic: "Local", difficulty: .level6, customPrompt: "로컬", intervalMinutes: 10)
        store.saveSettings(localSettings)
        let localQuestion = QuestionItem(question: "로컬 질문", expectedAnswerHint: nil, createdAt: Date(timeIntervalSince1970: 200))
        store.saveQuestion(localQuestion)
        store.appendStudyRecord(question: localQuestion, settings: localSettings)

        let remoteQuestion = QuestionItem(question: "원격 질문", expectedAnswerHint: nil, createdAt: Date(timeIntervalSince1970: 150))
        let remoteSnapshot = CloudSyncSnapshot(
            updatedAt: Date(timeIntervalSince1970: 100),
            settings: StudySettings(topic: "Remote", difficulty: .level4, customPrompt: "원격", intervalMinutes: 9),
            currentQuestion: remoteQuestion,
            questionHistory: [remoteQuestion],
            lastAnswer: "",
            gradingResult: nil,
            isRunning: true,
            hasCompletedOnboarding: true,
            studyRecords: [
                StudyRecord(question: remoteQuestion, topic: "Remote", difficulty: .level4)
            ]
        )
        let syncService = FakeCloudSyncService(remoteSnapshot: remoteSnapshot)
        let appState = AppState(settingsStore: store, openAIClient: SpyOpenAIClient(), cloudSyncService: syncService)

        await appState.syncCloudNow()

        let savedQuestions = syncService.savedSnapshot?.studyRecords.map(\.question.question) ?? []
        XCTAssertTrue(savedQuestions.contains("로컬 질문"))
        XCTAssertTrue(savedQuestions.contains("원격 질문"))
        XCTAssertEqual(syncService.savedSnapshot?.currentQuestion?.question, "로컬 질문")
    }

    @MainActor
    func testCloudSyncDoesNotResurrectDeletedRecordWhenPushingNewerLocalSnapshot() async throws {
        let suiteName = "StudyMateTests-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defer {
            defaults.removePersistentDomain(forName: suiteName)
        }

        let store = SettingsStore(defaults: defaults)
        let settings = StudySettings(topic: "Sync", difficulty: .level5, customPrompt: "질문", intervalMinutes: 10)
        store.saveIsCloudSyncEnabled(true)
        store.saveCloudSyncSnapshotUpdatedAt(Date(timeIntervalSince1970: 200))
        store.saveSettings(settings)

        let deletedQuestion = QuestionItem(question: "삭제될 질문", expectedAnswerHint: nil, createdAt: Date(timeIntervalSince1970: 100))
        let keptQuestion = QuestionItem(question: "남을 질문", expectedAnswerHint: nil, createdAt: Date(timeIntervalSince1970: 120))
        store.appendStudyRecord(question: deletedQuestion, settings: settings)
        store.appendStudyRecord(question: keptQuestion, settings: settings)
        let remoteRecords = store.loadStudyRecords()
        let deletedRecord = try XCTUnwrap(remoteRecords.first { $0.question.question == "삭제될 질문" })
        let remoteSnapshot = CloudSyncSnapshot(
            updatedAt: Date(timeIntervalSince1970: 150),
            settings: settings,
            currentQuestion: keptQuestion,
            questionHistory: [deletedQuestion, keptQuestion],
            lastAnswer: "",
            gradingResult: nil,
            isRunning: true,
            hasCompletedOnboarding: true,
            studyRecords: remoteRecords
        )
        let syncService = FakeCloudSyncService(remoteSnapshot: remoteSnapshot)
        let appState = AppState(settingsStore: store, openAIClient: SpyOpenAIClient(), cloudSyncService: syncService)

        appState.deleteStudyRecord(deletedRecord)
        await appState.syncCloudNow()

        let savedQuestions = syncService.savedSnapshot?.studyRecords.map(\.question.question) ?? []
        XCTAssertFalse(savedQuestions.contains("삭제될 질문"))
        XCTAssertTrue(savedQuestions.contains("남을 질문"))
        XCTAssertFalse(appState.studyRecords.contains { $0.question.question == "삭제될 질문" })
        XCTAssertEqual(syncService.savedSnapshot?.deletedStudyRecordMarkers.count, 1)
    }

    @MainActor
    func testCloudSyncLocalTombstoneFiltersNewerRemoteSnapshot() async throws {
        let suiteName = "StudyMateTests-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defer {
            defaults.removePersistentDomain(forName: suiteName)
        }

        let store = SettingsStore(defaults: defaults)
        let settings = StudySettings(topic: "Sync", difficulty: .level5, customPrompt: "질문", intervalMinutes: 10)
        store.saveIsCloudSyncEnabled(true)
        store.saveCloudSyncSnapshotUpdatedAt(Date(timeIntervalSince1970: 50))
        store.saveSettings(settings)

        let deletedQuestion = QuestionItem(question: "원격에서 살아나면 안 되는 질문", expectedAnswerHint: nil, createdAt: Date(timeIntervalSince1970: 100))
        let keptQuestion = QuestionItem(question: "유지할 질문", expectedAnswerHint: nil, createdAt: Date(timeIntervalSince1970: 120))
        let deletedRecord = StudyRecord(question: deletedQuestion, topic: settings.topic, difficulty: settings.difficulty)
        let keptRecord = StudyRecord(question: keptQuestion, topic: settings.topic, difficulty: settings.difficulty)
        store.replaceStudyRecords([deletedRecord, keptRecord])
        store.deleteStudyRecord(deletedRecord)

        let remoteSnapshot = CloudSyncSnapshot(
            updatedAt: Date(timeIntervalSince1970: 100),
            settings: settings,
            currentQuestion: keptQuestion,
            questionHistory: [deletedQuestion, keptQuestion],
            lastAnswer: "",
            gradingResult: nil,
            isRunning: true,
            hasCompletedOnboarding: true,
            studyRecords: [deletedRecord, keptRecord]
        )
        let syncService = FakeCloudSyncService(remoteSnapshot: remoteSnapshot)
        let appState = AppState(settingsStore: store, openAIClient: SpyOpenAIClient(), cloudSyncService: syncService)

        await appState.syncCloudNow()

        XCTAssertFalse(appState.studyRecords.contains { $0.question.question == "원격에서 살아나면 안 되는 질문" })
        XCTAssertTrue(appState.studyRecords.contains { $0.question.question == "유지할 질문" })
        XCTAssertEqual(store.loadDeletedStudyRecordMarkers().count, 1)
        XCTAssertFalse(syncService.savedSnapshot?.studyRecords.contains { $0.question.question == "원격에서 살아나면 안 되는 질문" } ?? true)
        XCTAssertEqual(syncService.savedSnapshot?.deletedStudyRecordMarkers.count, 1)
    }

    @MainActor
    func testCloudSyncRemoteTombstoneDeletesLocalRecordOnOtherDevice() async throws {
        let suiteName = "StudyMateTests-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defer {
            defaults.removePersistentDomain(forName: suiteName)
        }

        let store = SettingsStore(defaults: defaults)
        let settings = StudySettings(topic: "Sync", difficulty: .level5, customPrompt: "질문", intervalMinutes: 10)
        store.saveIsCloudSyncEnabled(true)
        store.saveCloudSyncSnapshotUpdatedAt(Date(timeIntervalSince1970: 50))
        store.saveSettings(settings)

        let deletedQuestion = QuestionItem(question: "아이폰에서 삭제한 질문", expectedAnswerHint: nil, createdAt: Date(timeIntervalSince1970: 100))
        let keptQuestion = QuestionItem(question: "맥에 남아야 하는 질문", expectedAnswerHint: nil, createdAt: Date(timeIntervalSince1970: 120))
        let deletedRecord = StudyRecord(question: deletedQuestion, topic: settings.topic, difficulty: settings.difficulty)
        let keptRecord = StudyRecord(question: keptQuestion, topic: settings.topic, difficulty: settings.difficulty)
        store.replaceStudyRecords([deletedRecord, keptRecord])

        let remoteSnapshot = CloudSyncSnapshot(
            updatedAt: Date(timeIntervalSince1970: 100),
            settings: settings,
            currentQuestion: keptQuestion,
            questionHistory: [deletedQuestion, keptQuestion],
            lastAnswer: "",
            gradingResult: nil,
            isRunning: true,
            hasCompletedOnboarding: true,
            studyRecords: [keptRecord],
            deletedStudyRecordMarkers: [DeletedStudyRecordMarker(record: deletedRecord, deletedAt: Date(timeIntervalSince1970: 130))]
        )
        let appState = AppState(
            settingsStore: store,
            openAIClient: SpyOpenAIClient(),
            cloudSyncService: FakeCloudSyncService(remoteSnapshot: remoteSnapshot)
        )

        await appState.syncCloudNow()

        XCTAssertFalse(appState.studyRecords.contains { $0.question.question == "아이폰에서 삭제한 질문" })
        XCTAssertTrue(appState.studyRecords.contains { $0.question.question == "맥에 남아야 하는 질문" })
        XCTAssertFalse(store.loadStudyRecords().contains { $0.question.question == "아이폰에서 삭제한 질문" })
    }

    @MainActor
    func testBackgroundRefreshGeneratesQuestionWhenOnlyPhoneIsRunningAndIntervalIsDue() async {
        let suiteName = "StudyMateTests-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defer {
            defaults.removePersistentDomain(forName: suiteName)
        }

        let store = SettingsStore(defaults: defaults)
        store.saveHasCompletedOnboarding(true)
        store.saveAPIKey("sk-local")
        store.saveSettings(StudySettings(topic: "iPhone", difficulty: .level5, customPrompt: "짧게", intervalMinutes: 15))

        let question = QuestionItem(
            question: "iPhone 단독 실행 질문",
            expectedAnswerHint: nil,
            createdAt: Date(timeIntervalSinceNow: -1)
        )
        let client = SpyOpenAIClient()
        client.generatedQuestionResult = GeneratedQuestionResult(question: question, responseID: "resp_phone")
        let appState = AppState(settingsStore: store, openAIClient: client)

        let didUpdate = await appState.handleBackgroundRefresh()

        XCTAssertTrue(didUpdate)
        XCTAssertEqual(client.generateCallCount, 1)
        XCTAssertEqual(appState.currentQuestion?.question, "iPhone 단독 실행 질문")
    }

    @MainActor
    func testBackgroundRefreshEarliestDateUsesConfiguredInterval() {
        let suiteName = "StudyMateTests-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defer {
            defaults.removePersistentDomain(forName: suiteName)
        }

        let store = SettingsStore(defaults: defaults)
        let now = Date(timeIntervalSince1970: 1_000)
        let settings = StudySettings(topic: "Timer", difficulty: .level5, customPrompt: "짧게", intervalMinutes: 1)
        let latestQuestion = QuestionItem(
            question: "백그라운드 예약 기준 질문",
            expectedAnswerHint: nil,
            createdAt: now.addingTimeInterval(-10)
        )
        store.saveSettings(settings)
        store.appendStudyRecord(question: latestQuestion, settings: settings)

        let appState = AppState(settingsStore: store, openAIClient: SpyOpenAIClient())

        XCTAssertEqual(
            appState.backgroundRefreshEarliestBeginDate(now: now).timeIntervalSince1970,
            now.addingTimeInterval(50).timeIntervalSince1970,
            accuracy: 0.001
        )
    }

    @MainActor
    func testScheduledQuestionDoesNotReplaceActiveUngradedDraft() async {
        let suiteName = "StudyMateTests-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defer {
            defaults.removePersistentDomain(forName: suiteName)
        }

        let store = SettingsStore(defaults: defaults)
        let settings = StudySettings(topic: "Redis", difficulty: .level5, customPrompt: "짧게", intervalMinutes: 15)
        let activeQuestion = QuestionItem(
            question: "Redis Stream consumer group은 무엇인가요?",
            expectedAnswerHint: nil,
            createdAt: Date(timeIntervalSince1970: 100)
        )
        let scheduledQuestion = QuestionItem(
            question: "Redis Stream trim은 언제 쓰나요?",
            expectedAnswerHint: nil,
            createdAt: Date(timeIntervalSince1970: 200)
        )
        store.saveAPIKey("sk-local")
        store.saveSettings(settings)
        store.saveIsRunning(true)
        store.saveQuestion(activeQuestion)
        store.appendStudyRecord(question: activeQuestion, settings: settings)
        store.updateStudyRecordAnswer(question: activeQuestion, answer: "작성 중인 답변")
        store.saveLastAnswer("작성 중인 답변")

        let client = SpyOpenAIClient()
        client.generatedQuestionResult = GeneratedQuestionResult(question: scheduledQuestion, responseID: "resp_scheduled")
        let appState = AppState(settingsStore: store, openAIClient: client)

        await appState.generateQuestion(manual: false)

        let questions = appState.studyRecords.map(\.question.question)
        XCTAssertEqual(appState.currentQuestion?.question, activeQuestion.question)
        XCTAssertEqual(appState.lastAnswer, "작성 중인 답변")
        XCTAssertEqual(store.loadQuestion()?.question, activeQuestion.question)
        XCTAssertEqual(store.loadLastAnswer(), "작성 중인 답변")
        XCTAssertTrue(questions.contains(activeQuestion.question))
        XCTAssertTrue(questions.contains(scheduledQuestion.question))
    }

    @MainActor
    func testGeneratedQuestionRetriesAndDoesNotSaveExistingQuestion() async {
        let suiteName = "StudyMateTests-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defer {
            defaults.removePersistentDomain(forName: suiteName)
        }

        let store = SettingsStore(defaults: defaults)
        let settings = StudySettings(topic: "Redis", difficulty: .level5, customPrompt: "짧게", intervalMinutes: 15)
        let existingQuestion = QuestionItem(
            question: "Redis Stream ID는 어떤 의미인가요?",
            expectedAnswerHint: nil,
            createdAt: Date(timeIntervalSince1970: 100)
        )
        let newQuestion = QuestionItem(
            question: "Redis Stream pending entries list는 언제 확인하나요?",
            expectedAnswerHint: nil,
            createdAt: Date(timeIntervalSince1970: 200)
        )
        store.saveAPIKey("sk-local")
        store.saveSettings(settings)
        store.appendStudyRecord(question: existingQuestion, settings: settings)

        let client = SpyOpenAIClient()
        client.generatedQuestionResults = [
            GeneratedQuestionResult(question: existingQuestion, responseID: "resp_duplicate"),
            GeneratedQuestionResult(question: newQuestion, responseID: "resp_new")
        ]
        let appState = AppState(settingsStore: store, openAIClient: client)

        await appState.generateQuestion()

        XCTAssertEqual(client.generateCallCount, 2)
        XCTAssertEqual(appState.studyRecords.filter { $0.question.question == existingQuestion.question }.count, 1)
        XCTAssertTrue(appState.studyRecords.contains { $0.question.question == newQuestion.question })
        XCTAssertEqual(appState.currentQuestion?.question, newQuestion.question)
    }

    @MainActor
    func testGeneratedQuestionDoesNotSaveWhenAllAttemptsRepeatExistingQuestion() async {
        let suiteName = "StudyMateTests-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defer {
            defaults.removePersistentDomain(forName: suiteName)
        }

        let store = SettingsStore(defaults: defaults)
        let settings = StudySettings(topic: "Redis", difficulty: .level5, customPrompt: "짧게", intervalMinutes: 15)
        let existingQuestion = QuestionItem(
            question: "Redis Stream MAXLEN은 언제 쓰나요?",
            expectedAnswerHint: nil,
            createdAt: Date(timeIntervalSince1970: 100)
        )
        store.saveAPIKey("sk-local")
        store.saveSettings(settings)
        store.appendStudyRecord(question: existingQuestion, settings: settings)

        let client = SpyOpenAIClient()
        client.generatedQuestionResult = GeneratedQuestionResult(question: existingQuestion, responseID: "resp_duplicate")
        let appState = AppState(settingsStore: store, openAIClient: client)

        await appState.generateQuestion()

        XCTAssertEqual(client.generateCallCount, 5)
        XCTAssertEqual(appState.studyRecords.count, 1)
        XCTAssertEqual(appState.statusMessage, appState.strings.duplicateQuestionSkipped)
    }

    @MainActor
    func testCloudSyncDoesNotReplaceActiveUngradedDraftWithRemoteCurrentQuestion() async {
        let suiteName = "StudyMateTests-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defer {
            defaults.removePersistentDomain(forName: suiteName)
        }

        let store = SettingsStore(defaults: defaults)
        let localSettings = StudySettings(topic: "Local", difficulty: .level5, customPrompt: "로컬", intervalMinutes: 15)
        let localQuestion = QuestionItem(
            question: "작성 중인 로컬 질문",
            expectedAnswerHint: nil,
            createdAt: Date(timeIntervalSince1970: 100)
        )
        let remoteQuestion = QuestionItem(
            question: "원격에서 새로 온 질문",
            expectedAnswerHint: nil,
            createdAt: Date(timeIntervalSince1970: 200)
        )
        store.saveIsCloudSyncEnabled(true)
        store.saveCloudSyncSnapshotUpdatedAt(Date(timeIntervalSince1970: 50))
        store.saveSettings(localSettings)
        store.saveQuestion(localQuestion)
        store.appendStudyRecord(question: localQuestion, settings: localSettings)
        store.updateStudyRecordAnswer(question: localQuestion, answer: "로컬 작성 중")
        store.saveLastAnswer("로컬 작성 중")

        let remoteSnapshot = CloudSyncSnapshot(
            updatedAt: Date(timeIntervalSince1970: 100),
            settings: StudySettings(topic: "Remote", difficulty: .level6, customPrompt: "원격", intervalMinutes: 15),
            currentQuestion: remoteQuestion,
            questionHistory: [remoteQuestion],
            lastAnswer: "",
            gradingResult: nil,
            isRunning: true,
            hasCompletedOnboarding: true,
            studyRecords: [
                StudyRecord(question: remoteQuestion, topic: "Remote", difficulty: .level6)
            ]
        )
        let syncService = FakeCloudSyncService(remoteSnapshot: remoteSnapshot)
        let appState = AppState(settingsStore: store, openAIClient: SpyOpenAIClient(), cloudSyncService: syncService)

        await appState.syncCloudNow()

        let questions = appState.studyRecords.map(\.question.question)
        XCTAssertEqual(appState.currentQuestion?.question, localQuestion.question)
        XCTAssertEqual(appState.lastAnswer, "로컬 작성 중")
        XCTAssertEqual(store.loadQuestion()?.question, localQuestion.question)
        XCTAssertEqual(store.loadLastAnswer(), "로컬 작성 중")
        XCTAssertTrue(questions.contains(localQuestion.question))
        XCTAssertTrue(questions.contains(remoteQuestion.question))
    }

    @MainActor
    func testSilentCloudPushDoesNotActivatePushedQuestion() async {
        let suiteName = "StudyMateTests-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defer {
            defaults.removePersistentDomain(forName: suiteName)
        }

        let store = SettingsStore(defaults: defaults)
        let settings = StudySettings(topic: "CloudKit", difficulty: .level5, customPrompt: "", intervalMinutes: 15)
        let pushedQuestion = QuestionItem(
            question: "조용히 도착한 push 질문입니다.",
            expectedAnswerHint: nil,
            createdAt: Date(timeIntervalSince1970: 300)
        )
        let snapshot = CloudSyncSnapshot(
            updatedAt: Date(timeIntervalSince1970: 400),
            settings: settings,
            currentQuestion: pushedQuestion,
            questionHistory: [pushedQuestion],
            lastAnswer: "",
            gradingResult: nil,
            isRunning: true,
            hasCompletedOnboarding: true,
            studyRecords: [
                StudyRecord(question: pushedQuestion, topic: "CloudKit", difficulty: .level5)
            ]
        )
        store.saveIsCloudSyncEnabled(true)
        store.saveCloudSyncSnapshotUpdatedAt(Date(timeIntervalSince1970: 100))
        let syncService = FakeCloudSyncService(remoteSnapshot: snapshot)
        syncService.questionPushesByRecordName["question-300000"] = CloudQuestionPush(
            question: pushedQuestion,
            topic: "CloudKit",
            difficulty: .level5
        )
        let appState = AppState(settingsStore: store, openAIClient: SpyOpenAIClient(), cloudSyncService: syncService)

        let didHandle = await appState.handleCloudQuestionPush(
            recordName: "question-300000",
            openStudy: false
        )

        XCTAssertTrue(didHandle)
        XCTAssertNil(appState.currentQuestion)
        XCTAssertNil(store.loadQuestion())
        XCTAssertTrue(appState.studyRecords.contains { $0.question == pushedQuestion })
    }

    @MainActor
    func testSilentCloudPushReplySavesAnswerWithoutOpeningStudy() async {
        let suiteName = "StudyMateTests-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defer {
            defaults.removePersistentDomain(forName: suiteName)
        }

        let store = SettingsStore(defaults: defaults)
        let settings = StudySettings(topic: "CloudKit", difficulty: .level5, customPrompt: "", intervalMinutes: 15)
        let pushedQuestion = QuestionItem(
            question: "백그라운드 답장을 저장할 질문입니다.",
            expectedAnswerHint: nil,
            createdAt: Date(timeIntervalSince1970: 310)
        )
        store.saveSettings(settings)
        store.saveIsCloudSyncEnabled(true)
        store.saveCloudSyncSnapshotUpdatedAt(Date(timeIntervalSince1970: 100))
        let syncService = FakeCloudSyncService(remoteSnapshot: nil)
        syncService.questionPushesByRecordName["question-310000"] = CloudQuestionPush(
            question: pushedQuestion,
            topic: "CloudKit",
            difficulty: .level5
        )
        let appState = AppState(settingsStore: store, openAIClient: SpyOpenAIClient(), cloudSyncService: syncService)
        appState.selectedTab = .records

        let didHandle = await appState.handleCloudQuestionPush(
            recordName: "question-310000",
            openStudy: false,
            replyText: "알림에서 바로 답장했습니다."
        )

        XCTAssertTrue(didHandle)
        XCTAssertEqual(appState.selectedTab, .records)
        XCTAssertNil(appState.currentQuestion)
        XCTAssertEqual(store.loadStudyRecords().first?.answer, "알림에서 바로 답장했습니다.")
    }

    @MainActor
    func testGeneratedQuestionSavesCloudPushRecordWhenSyncIsEnabled() async {
        let suiteName = "StudyMateTests-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defer {
            defaults.removePersistentDomain(forName: suiteName)
        }

        let store = SettingsStore(defaults: defaults)
        let settings = StudySettings(topic: "Swift", difficulty: .level6, customPrompt: "짧게", intervalMinutes: 15)
        store.saveIsCloudSyncEnabled(true)
        store.saveSettings(settings)

        let question = QuestionItem(
            question: "actor isolation은 왜 필요한가요?",
            expectedAnswerHint: "데이터 경쟁",
            createdAt: Date(timeIntervalSince1970: 200)
        )
        let client = SpyOpenAIClient()
        client.generatedQuestionResult = GeneratedQuestionResult(question: question, responseID: "resp_1")
        let syncService = FakeCloudSyncService(remoteSnapshot: nil)
        let appState = AppState(settingsStore: store, openAIClient: client, cloudSyncService: syncService)

        await appState.generateQuestion()

        XCTAssertEqual(syncService.savedQuestionPushes.count, 1)
        XCTAssertEqual(syncService.savedQuestionPushes.first?.question, question)
        XCTAssertEqual(syncService.savedQuestionPushes.first?.settings.topic, "Swift")
    }

    @MainActor
    func testCloudQuestionPushHandlerSyncsAndOpensPushedQuestion() async {
        let suiteName = "StudyMateTests-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defer {
            defaults.removePersistentDomain(forName: suiteName)
        }

        let store = SettingsStore(defaults: defaults)
        store.saveIsCloudSyncEnabled(true)

        let question = QuestionItem(
            question: "CloudKit query subscription은 언제 쓰나요?",
            expectedAnswerHint: "레코드 변경",
            createdAt: Date(timeIntervalSince1970: 300)
        )
        let snapshot = CloudSyncSnapshot(
            updatedAt: Date(timeIntervalSince1970: 400),
            settings: StudySettings(topic: "CloudKit", difficulty: .level5, customPrompt: "", intervalMinutes: 15),
            currentQuestion: question,
            questionHistory: [question],
            lastAnswer: "",
            gradingResult: nil,
            isRunning: true,
            hasCompletedOnboarding: true,
            studyRecords: [
                StudyRecord(question: question, topic: "CloudKit", difficulty: .level5)
            ]
        )
        let syncService = FakeCloudSyncService(remoteSnapshot: snapshot)
        syncService.questionPushesByRecordName["question-300000"] = CloudQuestionPush(
            question: question,
            topic: "CloudKit",
            difficulty: .level5
        )
        let appState = AppState(settingsStore: store, openAIClient: SpyOpenAIClient(), cloudSyncService: syncService)

        let didHandle = await appState.handleCloudQuestionPush(
            recordName: "question-300000",
            openStudy: true
        )

        XCTAssertTrue(didHandle)
        XCTAssertEqual(appState.currentQuestion, question)
        XCTAssertEqual(appState.selectedTab, .study)
        XCTAssertEqual(appState.studyRecords.first?.question, question)
    }

    func testNotificationPayloadParsesNestedCloudKitQuestionPush() throws {
        let userInfo: [AnyHashable: Any] = [
            "aps": [
                "alert": "StudyMate"
            ],
            "ck": [
                "qry": [
                    "sid": CloudSyncService.questionPushSubscriptionID,
                    "rid": "question-123000",
                    "createdAt": "123.5"
                ]
            ]
        ]

        XCTAssertTrue(StudyNotificationPayload.isCloudQuestionPush(from: userInfo))
        XCTAssertEqual(
            StudyNotificationPayload.cloudQuestionPushRecordName(from: userInfo),
            "question-123000"
        )
        let createdAt = try XCTUnwrap(StudyNotificationPayload.questionCreatedAt(from: userInfo))
        XCTAssertEqual(createdAt, 123.5, accuracy: 0.001)
    }

    func testNotificationPayloadIgnoresDifferentCloudKitSubscription() {
        let userInfo: [AnyHashable: Any] = [
            "ck": [
                "qry": [
                    "sid": "unrelated-subscription",
                    "rid": "question-123000"
                ]
            ]
        ]

        XCTAssertFalse(StudyNotificationPayload.isCloudQuestionPush(from: userInfo))
        XCTAssertNil(StudyNotificationPayload.cloudQuestionPushRecordName(from: userInfo))
    }

    func testNotificationPayloadRecognizesCloudKitSubscriptionWithoutRecordName() {
        let userInfo: [AnyHashable: Any] = [
            "ck": [
                "qry": [
                    "sid": CloudSyncService.questionPushSubscriptionID
                ]
            ]
        ]

        XCTAssertTrue(StudyNotificationPayload.isCloudQuestionPush(from: userInfo))
        XCTAssertNil(StudyNotificationPayload.cloudQuestionPushRecordName(from: userInfo))
    }

    func testNotificationPayloadParsesLocalQuestionCreatedAtVariants() throws {
        let date = Date(timeIntervalSince1970: 300)

        let numberValue = try XCTUnwrap(
            StudyNotificationPayload.questionCreatedAt(from: [
                StudyNotificationAction.questionCreatedAt: NSNumber(value: 100.25)
            ])
        )
        XCTAssertEqual(numberValue, 100.25, accuracy: 0.001)

        let stringValue = try XCTUnwrap(
            StudyNotificationPayload.questionCreatedAt(from: [
                "createdAt": "200.5"
            ])
        )
        XCTAssertEqual(stringValue, 200.5, accuracy: 0.001)

        let dateValue = try XCTUnwrap(
            StudyNotificationPayload.questionCreatedAt(from: [
                "createdAt": date
            ])
        )
        XCTAssertEqual(dateValue, 300, accuracy: 0.001)
    }

    func testLocalQuestionNotificationPayloadIsNotCloudQuestionPush() {
        let userInfo: [AnyHashable: Any] = [
            StudyNotificationAction.questionCreatedAt: NSNumber(value: 100.25)
        ]

        XCTAssertFalse(StudyNotificationPayload.isCloudQuestionPush(from: userInfo))
        XCTAssertNil(StudyNotificationPayload.cloudQuestionPushRecordName(from: userInfo))
    }

    func testNotificationRoutingOnlyOpensBackgroundDefaultTap() {
        XCTAssertTrue(
            StudyNotificationRouting.shouldOpenStudyImmediately(
                actionIdentifier: UNNotificationDefaultActionIdentifier
            )
        )
        XCTAssertFalse(
            StudyNotificationRouting.shouldOpenStudyImmediately(
                actionIdentifier: StudyNotificationAction.reply
            )
        )
        XCTAssertFalse(
            StudyNotificationRouting.shouldOpenStudyImmediately(
                actionIdentifier: StudyNotificationAction.otherAnswer
            )
        )
        XCTAssertTrue(StudyNotificationRouting.isIgnored(StudyNotificationAction.ignore))
        XCTAssertTrue(StudyNotificationRouting.isIgnored(UNNotificationDismissActionIdentifier))
    }

    @MainActor
    func testMissingCloudQuestionPushDoesNotOpenFallbackQuestion() async {
        let suiteName = "StudyMateTests-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defer {
            defaults.removePersistentDomain(forName: suiteName)
        }

        let store = SettingsStore(defaults: defaults)
        store.saveIsCloudSyncEnabled(true)
        let settings = StudySettings(topic: "CloudKit", difficulty: .level5, customPrompt: "", intervalMinutes: 15)
        let existingQuestion = QuestionItem(
            question: "기존 질문을 잘못 열면 안 됩니다.",
            expectedAnswerHint: nil,
            createdAt: Date(timeIntervalSince1970: 200)
        )
        store.appendStudyRecord(question: existingQuestion, settings: settings)
        let syncService = FakeCloudSyncService(remoteSnapshot: nil)
        let appState = AppState(settingsStore: store, openAIClient: SpyOpenAIClient(), cloudSyncService: syncService)

        let didHandle = await appState.handleCloudQuestionPush(
            recordName: "missing-question",
            openStudy: true
        )

        XCTAssertFalse(didHandle)
        XCTAssertEqual(appState.selectedTab, .study)
        XCTAssertNil(appState.currentQuestion)
        XCTAssertEqual(appState.statusMessage, appState.strings.notificationQuestionUnavailable)
        XCTAssertEqual(appState.notificationLandingMessage, appState.strings.notificationQuestionUnavailable)
        XCTAssertTrue(appState.studyRecords.contains { $0.question == existingQuestion })
    }

    @MainActor
    func testDeletedCloudQuestionPushIsNotReaddedOrOpened() async {
        let suiteName = "StudyMateTests-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defer {
            defaults.removePersistentDomain(forName: suiteName)
        }

        let store = SettingsStore(defaults: defaults)
        store.saveIsCloudSyncEnabled(true)
        let settings = StudySettings(topic: "CloudKit", difficulty: .level5, customPrompt: "", intervalMinutes: 15)
        let deletedQuestion = QuestionItem(
            question: "삭제한 CloudKit push 질문입니다.",
            expectedAnswerHint: nil,
            createdAt: Date(timeIntervalSince1970: 300)
        )
        store.appendStudyRecord(question: deletedQuestion, settings: settings)
        guard let deletedRecord = store.loadStudyRecords().first else {
            XCTFail("Expected record to exist before deletion.")
            return
        }
        store.deleteStudyRecord(deletedRecord)

        let syncService = FakeCloudSyncService(remoteSnapshot: nil)
        syncService.questionPushesByRecordName["question-300000"] = CloudQuestionPush(
            question: deletedQuestion,
            topic: "CloudKit",
            difficulty: .level5
        )
        let appState = AppState(settingsStore: store, openAIClient: SpyOpenAIClient(), cloudSyncService: syncService)

        let didHandle = await appState.handleCloudQuestionPush(
            recordName: "question-300000",
            openStudy: true
        )

        XCTAssertTrue(didHandle)
        XCTAssertEqual(appState.selectedTab, .study)
        XCTAssertNil(appState.currentQuestion)
        XCTAssertEqual(appState.statusMessage, appState.strings.notificationQuestionUnavailable)
        XCTAssertEqual(appState.notificationLandingMessage, appState.strings.notificationQuestionUnavailable)
        XCTAssertFalse(appState.studyRecords.contains { $0.question == deletedQuestion })
        XCTAssertFalse(store.loadStudyRecords().contains { $0.question == deletedQuestion })
    }

    @MainActor
    func testDeletedCloudQuestionPushTapPreservesActiveDraft() async {
        let suiteName = "StudyMateTests-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defer {
            defaults.removePersistentDomain(forName: suiteName)
        }

        let store = SettingsStore(defaults: defaults)
        store.saveIsCloudSyncEnabled(true)
        let settings = StudySettings(topic: "CloudKit", difficulty: .level5, customPrompt: "", intervalMinutes: 15)
        let deletedQuestion = QuestionItem(
            question: "삭제한 CloudKit push 질문입니다.",
            expectedAnswerHint: nil,
            createdAt: Date(timeIntervalSince1970: 300)
        )
        let activeQuestion = QuestionItem(
            question: "작성 중인 현재 질문입니다.",
            expectedAnswerHint: nil,
            createdAt: Date(timeIntervalSince1970: 400)
        )
        store.appendStudyRecord(question: deletedQuestion, settings: settings)
        store.appendStudyRecord(question: activeQuestion, settings: settings)

        guard let deletedRecord = store.loadStudyRecords().first(where: { $0.question == deletedQuestion }),
              let activeRecord = store.loadStudyRecords().first(where: { $0.question == activeQuestion }) else {
            XCTFail("Expected records to exist.")
            return
        }
        store.deleteStudyRecord(deletedRecord)

        let syncService = FakeCloudSyncService(remoteSnapshot: nil)
        syncService.questionPushesByRecordName["question-300000"] = CloudQuestionPush(
            question: deletedQuestion,
            topic: "CloudKit",
            difficulty: .level5
        )
        let appState = AppState(settingsStore: store, openAIClient: SpyOpenAIClient(), cloudSyncService: syncService)
        appState.selectStudyRecord(activeRecord)
        appState.updateAnswer("기존 답변 초안")

        let didHandle = await appState.handleCloudQuestionPush(
            recordName: "question-300000",
            openStudy: true
        )

        XCTAssertTrue(didHandle)
        XCTAssertEqual(appState.selectedTab, .study)
        XCTAssertEqual(appState.currentQuestion?.question, activeQuestion.question)
        XCTAssertEqual(appState.lastAnswer, "기존 답변 초안")
        XCTAssertEqual(appState.statusMessage, appState.strings.notificationQuestionUnavailable)
        XCTAssertEqual(appState.notificationLandingMessage, appState.strings.notificationQuestionUnavailable)
        XCTAssertFalse(appState.studyRecords.contains { $0.question == deletedQuestion })
    }

    func testOpenAIBillingStatusParsesCostsAPIResponse() throws {
        let data = try XCTUnwrap("""
        {
          "object": "page",
          "data": [
            {
              "object": "bucket",
              "start_time": 1704067200,
              "end_time": 1704153600,
              "results": [
                {
                  "object": "organization.costs.result",
                  "amount": {
                    "value": 1.25,
                    "currency": "usd"
                  }
                }
              ]
            },
            {
              "object": "bucket",
              "start_time": 1704153600,
              "end_time": 1704240000,
              "results": [
                {
                  "object": "organization.costs.result",
                  "amount": {
                    "value": 0.75,
                    "currency": "usd"
                  }
                }
              ]
            }
          ]
        }
        """.data(using: .utf8))

        let status = try OpenAIClient.parseBillingStatus(
            from: data,
            periodStart: Date(timeIntervalSince1970: 1_704_067_200),
            periodEnd: Date(timeIntervalSince1970: 1_704_240_000),
            checkedAt: Date(timeIntervalSince1970: 1_704_240_000)
        )

        XCTAssertEqual(status.spentAmount, 2.0, accuracy: 0.000001)
        XCTAssertEqual(status.currency, "usd")
        XCTAssertEqual(status.formattedSpentAmount, "$2.00")
    }

    func testOpenAIBillingStatusFiltersGroupedCostsAPIResponseByScope() throws {
        let data = try XCTUnwrap("""
        {
          "object": "page",
          "data": [
            {
              "object": "bucket",
              "start_time": 1704067200,
              "end_time": 1704153600,
              "results": [
                {
                  "object": "organization.costs.result",
                  "project_id": "proj_studymate",
                  "api_key_id": "key_studymate",
                  "amount": {
                    "value": 0.40,
                    "currency": "usd"
                  }
                },
                {
                  "object": "organization.costs.result",
                  "project_id": "proj_other",
                  "api_key_id": "key_other",
                  "amount": {
                    "value": 9.99,
                    "currency": "usd"
                  }
                }
              ]
            },
            {
              "object": "bucket",
              "start_time": 1704153600,
              "end_time": 1704240000,
              "results": [
                {
                  "object": "organization.costs.result",
                  "project_id": "proj_studymate",
                  "api_key_id": "key_studymate",
                  "amount": {
                    "value": 0.60,
                    "currency": "usd"
                  }
                }
              ]
            }
          ]
        }
        """.data(using: .utf8))

        let status = try OpenAIClient.parseBillingStatus(
            from: data,
            periodStart: Date(timeIntervalSince1970: 1_704_067_200),
            periodEnd: Date(timeIntervalSince1970: 1_704_240_000),
            checkedAt: Date(timeIntervalSince1970: 1_704_240_000),
            projectID: "proj_studymate",
            apiKeyID: "key_studymate"
        )

        XCTAssertEqual(status.spentAmount, 1.0, accuracy: 0.000001)
    }

    func testOpenAIUsageStatusParsesCompletionsUsageAPIResponse() throws {
        let data = try XCTUnwrap("""
        {
          "object": "page",
          "data": [
            {
              "object": "bucket",
              "start_time": 1704067200,
              "end_time": 1704153600,
              "results": [
                {
                  "object": "organization.usage.completions.result",
                  "input_tokens": 1200,
                  "input_cached_tokens": 300,
                  "output_tokens": 450,
                  "num_model_requests": 7
                }
              ]
            },
            {
              "object": "bucket",
              "start_time": 1704153600,
              "end_time": 1704240000,
              "results": [
                {
                  "object": "organization.usage.completions.result",
                  "input_tokens": 800,
                  "input_cached_tokens": 100,
                  "output_tokens": 250,
                  "num_model_requests": 3
                }
              ]
            }
          ]
        }
        """.data(using: .utf8))

        let status = try OpenAIClient.parseUsageStatus(
            from: data,
            periodStart: Date(timeIntervalSince1970: 1_704_067_200),
            periodEnd: Date(timeIntervalSince1970: 1_704_240_000),
            checkedAt: Date(timeIntervalSince1970: 1_704_240_000)
        )

        XCTAssertEqual(status.inputTokens, 2_000)
        XCTAssertEqual(status.cachedInputTokens, 400)
        XCTAssertEqual(status.outputTokens, 700)
        XCTAssertEqual(status.totalTokens, 2_700)
        XCTAssertEqual(status.requestCount, 10)
    }

    func testOpenAIUsageStatusFiltersGroupedCompletionsUsageAPIResponseByScope() throws {
        let data = try XCTUnwrap("""
        {
          "object": "page",
          "data": [
            {
              "object": "bucket",
              "start_time": 1704067200,
              "end_time": 1704153600,
              "results": [
                {
                  "object": "organization.usage.completions.result",
                  "project_id": "proj_studymate",
                  "api_key_id": "key_studymate",
                  "input_tokens": 100,
                  "input_cached_tokens": 20,
                  "output_tokens": 50,
                  "num_model_requests": 2
                },
                {
                  "object": "organization.usage.completions.result",
                  "project_id": "proj_other",
                  "api_key_id": "key_other",
                  "input_tokens": 900,
                  "input_cached_tokens": 0,
                  "output_tokens": 900,
                  "num_model_requests": 9
                }
              ]
            },
            {
              "object": "bucket",
              "start_time": 1704153600,
              "end_time": 1704240000,
              "results": [
                {
                  "object": "organization.usage.completions.result",
                  "project_id": "proj_studymate",
                  "api_key_id": "key_studymate",
                  "input_tokens": 300,
                  "input_cached_tokens": 30,
                  "output_tokens": 70,
                  "num_model_requests": 3
                }
              ]
            }
          ]
        }
        """.data(using: .utf8))

        let status = try OpenAIClient.parseUsageStatus(
            from: data,
            periodStart: Date(timeIntervalSince1970: 1_704_067_200),
            periodEnd: Date(timeIntervalSince1970: 1_704_240_000),
            checkedAt: Date(timeIntervalSince1970: 1_704_240_000),
            projectID: "proj_studymate",
            apiKeyID: "key_studymate"
        )

        XCTAssertEqual(status.inputTokens, 400)
        XCTAssertEqual(status.cachedInputTokens, 50)
        XCTAssertEqual(status.outputTokens, 120)
        XCTAssertEqual(status.totalTokens, 520)
        XCTAssertEqual(status.requestCount, 5)
    }

    @MainActor
    func testOpenAIBillingStatusFollowsNextPageCursor() async throws {
        let recorder = URLRequestRecorder()
        let client = OpenAIClient { request in
            let pageValue = URLComponents(url: request.url!, resolvingAgainstBaseURL: false)?
                .queryItems?
                .first { $0.name == "page" }?
                .value
            recorder.append(pageValue)

            let body: Data
            if pageValue == nil {
                body = """
                {
                  "object": "page",
                  "has_more": true,
                  "next_page": "page_next",
                  "data": [
                    {
                      "object": "bucket",
                      "start_time": 1730419200,
                      "end_time": 1730505600,
                      "results": []
                    }
                  ]
                }
                """.data(using: .utf8)!
            } else {
                body = """
                {
                  "object": "page",
                  "has_more": false,
                  "data": [
                    {
                      "object": "bucket",
                      "start_time": 1730505600,
                      "end_time": 1730592000,
                      "results": [
                        {
                          "object": "organization.costs.result",
                          "amount": {
                            "value": 10.8,
                            "currency": "usd"
                          }
                        }
                      ]
                    }
                  ]
                }
                """.data(using: .utf8)!
            }

            let response = HTTPURLResponse(
                url: request.url!,
                statusCode: 200,
                httpVersion: nil,
                headerFields: nil
            )!
            return (body, response)
        }

        let status = try await client.fetchBillingStatus(
            adminAPIKey: "sk-admin",
            projectID: nil as String?,
            apiKeyID: nil as String?
        )

        XCTAssertEqual(recorder.pageValues, [nil, "page_next"])
        XCTAssertEqual(status.spentAmount, 10.8, accuracy: 0.000001)
        XCTAssertEqual(status.sourcePageCount, 2)
        XCTAssertEqual(status.sourceBucketCount, 2)
        XCTAssertEqual(status.sourceResultCount, 1)
    }

    func testSettingsWithoutLanguageDefaultsToKorean() throws {
        let suiteName = "StudyMateTests-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defer {
            defaults.removePersistentDomain(forName: suiteName)
        }

        let legacySettingsData = try XCTUnwrap("""
        {
          "topic": "Swift",
          "difficulty": "beginner",
          "customPrompt": "짧게",
          "intervalMinutes": 15,
          "maxHistoryCount": 100
        }
        """.data(using: .utf8))
        defaults.set(legacySettingsData, forKey: "studySettings")

        let store = SettingsStore(defaults: defaults)

        XCTAssertEqual(store.loadSettings().appLanguage, .korean)
        XCTAssertEqual(store.loadSettings().language, .korean)
        XCTAssertEqual(store.loadSettings().difficulty, .beginner)
        XCTAssertEqual(store.loadSettings().openAIModel, StudySettings.defaultOpenAIModel)
        XCTAssertEqual(store.loadSettings().notificationSound, .defaultSound)
    }

    func testNotificationSoundOptionsExposeBundledSoundNames() {
        XCTAssertNil(NotificationSoundOption.defaultSound.bundledFileName)
        XCTAssertNil(NotificationSoundOption.none.bundledFileName)
        XCTAssertEqual(NotificationSoundOption.softPing.bundledFileName, "study_ping.wav")
        XCTAssertEqual(NotificationSoundOption.chime.bundledFileName, "study_chime.wav")
        XCTAssertEqual(NotificationSoundOption.pop.bundledFileName, "study_pop.wav")
        XCTAssertEqual(NotificationSoundOption.bell.bundledFileName, "study_bell.wav")
        XCTAssertEqual(NotificationSoundOption.tap.bundledFileName, "study_tap.wav")
    }

    func testGeneratedUninstallScriptIsValidShellAndTargetsKnownInstallLocations() throws {
        let script = AppState.makeUninstallScript(appPath: "/tmp/StudyMate Test.app")
        let scriptURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("studymate-uninstall-test-\(UUID().uuidString).sh")
        defer {
            try? FileManager.default.removeItem(at: scriptURL)
        }

        try script.write(to: scriptURL, atomically: true, encoding: .utf8)

        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/sh")
        process.arguments = ["-n", scriptURL.path]
        try process.run()
        process.waitUntilExit()

        XCTAssertEqual(process.terminationStatus, 0)
        XCTAssertTrue(script.contains("/Applications/StudyMate.app"))
        XCTAssertTrue(script.contains("~/Applications/StudyMate.app"))
        XCTAssertTrue(script.contains("Library/Caches/Sparkle"))
        XCTAssertTrue(script.contains("사용해주셔서 감사합니다."))
    }

    func testAppLanguageControlsStudyLanguageOnSave() {
        let suiteName = "StudyMateTests-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defer {
            defaults.removePersistentDomain(forName: suiteName)
        }

        let store = SettingsStore(defaults: defaults)
        let settings = StudySettings(
            topic: "Swift",
            difficulty: .beginner,
            appLanguage: .english,
            language: .korean,
            customPrompt: "Short question",
            intervalMinutes: 15
        )

        store.saveSettings(settings)

        let loadedSettings = store.loadSettings()
        XCTAssertEqual(loadedSettings.appLanguage, .english)
        XCTAssertEqual(loadedSettings.language, .english)
    }

    func testUnsupportedOpenAIModelDefaultsWhenSaved() {
        let suiteName = "StudyMateTests-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defer {
            defaults.removePersistentDomain(forName: suiteName)
        }

        let store = SettingsStore(defaults: defaults)
        let settings = StudySettings(
            topic: "Swift",
            difficulty: .beginner,
            openAIModel: "  gpt-custom  ",
            customPrompt: "짧게",
            intervalMinutes: 15
        )

        store.saveSettings(settings)

        XCTAssertEqual(store.loadSettings().openAIModel, StudySettings.defaultOpenAIModel)
    }

    func testSupportedOpenAIModelIsSaved() {
        let suiteName = "StudyMateTests-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defer {
            defaults.removePersistentDomain(forName: suiteName)
        }

        let store = SettingsStore(defaults: defaults)
        let settings = StudySettings(
            topic: "Swift",
            difficulty: .beginner,
            openAIModel: "gpt-5.4",
            customPrompt: "짧게",
            intervalMinutes: 15
        )

        store.saveSettings(settings)

        XCTAssertEqual(store.loadSettings().openAIModel, "gpt-5.4")
    }

    func testEmptyOpenAIModelDefaultsWhenSaved() {
        let suiteName = "StudyMateTests-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defer {
            defaults.removePersistentDomain(forName: suiteName)
        }

        let store = SettingsStore(defaults: defaults)
        let settings = StudySettings(
            topic: "Swift",
            difficulty: .beginner,
            openAIModel: "   ",
            customPrompt: "짧게",
            intervalMinutes: 15
        )

        store.saveSettings(settings)

        XCTAssertEqual(store.loadSettings().openAIModel, StudySettings.defaultOpenAIModel)
    }

    func testSettingsIntervalIsClampedWhenLoaded() {
        let suiteName = "StudyMateTests-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defer {
            defaults.removePersistentDomain(forName: suiteName)
        }

        let store = SettingsStore(defaults: defaults)
        let settings = StudySettings(
            topic: "SwiftUI",
            difficulty: .beginner,
            customPrompt: "짧게",
            intervalMinutes: 999
        )

        store.saveSettings(settings)

        XCTAssertEqual(store.loadSettings().intervalMinutes, 240)
    }

    func testSettingsHistoryLimitIsClampedWhenLoaded() {
        let suiteName = "StudyMateTests-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defer {
            defaults.removePersistentDomain(forName: suiteName)
        }

        let store = SettingsStore(defaults: defaults)
        let settings = StudySettings(
            topic: "SwiftUI",
            difficulty: .beginner,
            customPrompt: "짧게",
            intervalMinutes: 15,
            maxHistoryCount: 999
        )

        store.saveSettings(settings)

        XCTAssertEqual(store.loadSettings().maxHistoryCount, 999)
    }

    func testSettingsHistoryLimitCapsAtTenThousand() {
        let suiteName = "StudyMateTests-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defer {
            defaults.removePersistentDomain(forName: suiteName)
        }

        let store = SettingsStore(defaults: defaults)
        let settings = StudySettings(
            topic: "SwiftUI",
            difficulty: .beginner,
            customPrompt: "짧게",
            intervalMinutes: 15,
            maxHistoryCount: 50_000
        )

        store.saveSettings(settings)

        XCTAssertEqual(store.loadSettings().maxHistoryCount, 10_000)
    }

    func testAPIKeyRoundTripUsesUserDefaults() {
        let suiteName = "StudyMateTests-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defer {
            defaults.removePersistentDomain(forName: suiteName)
        }

        let store = SettingsStore(defaults: defaults)

        store.saveAPIKey("  sk-test  ")

        XCTAssertEqual(store.loadAPIKey(), "sk-test")
    }

    func testEmptyAPIKeyClearsStoredValue() {
        let suiteName = "StudyMateTests-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defer {
            defaults.removePersistentDomain(forName: suiteName)
        }

        let store = SettingsStore(defaults: defaults)
        store.saveAPIKey("sk-test")

        store.saveAPIKey("   ")

        XCTAssertEqual(store.loadAPIKey(), "")
    }

    func testAdminAPIKeyRoundTripUsesUserDefaults() {
        let suiteName = "StudyMateTests-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defer {
            defaults.removePersistentDomain(forName: suiteName)
        }

        let store = SettingsStore(defaults: defaults)

        store.saveAdminAPIKey("  sk-admin-test  ")

        XCTAssertEqual(store.loadAdminAPIKey(), "sk-admin-test")
    }

    func testEmptyAdminAPIKeyClearsStoredValue() {
        let suiteName = "StudyMateTests-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defer {
            defaults.removePersistentDomain(forName: suiteName)
        }

        let store = SettingsStore(defaults: defaults)
        store.saveAdminAPIKey("sk-admin-test")

        store.saveAdminAPIKey("   ")

        XCTAssertEqual(store.loadAdminAPIKey(), "")
    }

    func testOpenAIUsageScopeFiltersRoundTripUsesUserDefaults() {
        let suiteName = "StudyMateTests-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defer {
            defaults.removePersistentDomain(forName: suiteName)
        }

        let store = SettingsStore(defaults: defaults)

        store.saveOpenAIUsageProjectID("  proj_studymate  ")
        store.saveOpenAIUsageAPIKeyID("  key_studymate  ")

        XCTAssertEqual(store.loadOpenAIUsageProjectID(), "proj_studymate")
        XCTAssertEqual(store.loadOpenAIUsageAPIKeyID(), "key_studymate")
    }

    @MainActor
    func testSaveSettingsWithoutAPIKeyChangeSkipsValidation() async {
        let suiteName = "StudyMateTests-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defer {
            defaults.removePersistentDomain(forName: suiteName)
        }

        let store = SettingsStore(defaults: defaults)
        store.saveAPIKey("sk-existing")
        let client = SpyOpenAIClient()
        let appState = AppState(settingsStore: store, openAIClient: client)

        appState.settings.topic = "Changed topic"

        await appState.saveSettingsAndValidateAPIKey()

        XCTAssertEqual(client.validateCallCount, 0)
        XCTAssertEqual(store.loadSettings().topic, "Changed topic")
        XCTAssertEqual(store.loadAPIKey(), "sk-existing")
    }

    @MainActor
    func testCancelSettingsEditingDiscardsDraftChanges() {
        let suiteName = "StudyMateTests-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defer {
            defaults.removePersistentDomain(forName: suiteName)
        }

        let store = SettingsStore(defaults: defaults)
        store.saveAPIKey("sk-existing")
        store.saveAdminAPIKey("sk-admin-existing")
        store.saveOpenAIUsageProjectID("proj_existing")
        store.saveOpenAIUsageAPIKeyID("key_existing")
        let appState = AppState(settingsStore: store, openAIClient: SpyOpenAIClient())
        let savedTopic = appState.settings.topic

        appState.beginSettingsEditing()
        appState.draftSettings.topic = "Unsaved topic"
        appState.draftAPIKey = "sk-unsaved"
        appState.draftAdminAPIKey = "sk-admin-unsaved"
        appState.draftOpenAIUsageProjectID = "proj_unsaved"
        appState.draftOpenAIUsageAPIKeyID = "key_unsaved"
        appState.cancelSettingsEditing()

        XCTAssertEqual(appState.settings.topic, savedTopic)
        XCTAssertEqual(appState.draftSettings.topic, savedTopic)
        XCTAssertEqual(store.loadSettings().topic, savedTopic)
        XCTAssertEqual(store.loadAPIKey(), "sk-existing")
        XCTAssertEqual(store.loadAdminAPIKey(), "sk-admin-existing")
        XCTAssertEqual(store.loadOpenAIUsageProjectID(), "proj_existing")
        XCTAssertEqual(store.loadOpenAIUsageAPIKeyID(), "key_existing")
        XCTAssertFalse(appState.hasUnsavedSettingsChanges)
    }

    @MainActor
    func testSaveSettingsEditingCommitsDraftChanges() async {
        let suiteName = "StudyMateTests-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defer {
            defaults.removePersistentDomain(forName: suiteName)
        }

        let store = SettingsStore(defaults: defaults)
        store.saveAPIKey("sk-existing")
        store.saveAdminAPIKey("sk-admin-existing")
        store.saveOpenAIUsageProjectID("proj_existing")
        store.saveOpenAIUsageAPIKeyID("key_existing")
        let client = SpyOpenAIClient()
        let appState = AppState(settingsStore: store, openAIClient: client)

        appState.beginSettingsEditing()
        appState.draftSettings.topic = "Saved draft topic"
        appState.draftAPIKey = "sk-existing"
        appState.draftAdminAPIKey = "sk-admin-updated"
        appState.draftOpenAIUsageProjectID = "proj_updated"
        appState.draftOpenAIUsageAPIKeyID = "key_updated"

        await appState.saveSettingsAndValidateAPIKey()

        XCTAssertEqual(appState.settings.topic, "Saved draft topic")
        XCTAssertEqual(store.loadSettings().topic, "Saved draft topic")
        XCTAssertEqual(store.loadAdminAPIKey(), "sk-admin-updated")
        XCTAssertEqual(store.loadOpenAIUsageProjectID(), "proj_updated")
        XCTAssertEqual(store.loadOpenAIUsageAPIKeyID(), "key_updated")
        XCTAssertEqual(client.validateCallCount, 0)
        XCTAssertFalse(appState.hasUnsavedSettingsChanges)
    }

    @MainActor
    func testRefreshOpenAIBillingStatusUsesAdminAPIKey() async {
        let suiteName = "StudyMateTests-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defer {
            defaults.removePersistentDomain(forName: suiteName)
        }

        let store = SettingsStore(defaults: defaults)
        store.saveAPIKey("sk-project")
        store.saveAdminAPIKey("sk-admin")
        store.saveOpenAIUsageProjectID("proj_studymate")
        store.saveOpenAIUsageAPIKeyID("key_studymate")
        let client = SpyOpenAIClient()
        let appState = AppState(settingsStore: store, openAIClient: client)

        await appState.refreshOpenAIBillingStatus()

        XCTAssertEqual(client.billingStatusAdminAPIKeys, ["sk-admin"])
        XCTAssertEqual(client.usageStatusAdminAPIKeys, ["sk-admin"])
        XCTAssertEqual(client.billingStatusProjectIDs, ["proj_studymate"])
        XCTAssertEqual(client.billingStatusAPIKeyIDs, ["key_studymate"])
        XCTAssertEqual(client.usageStatusProjectIDs, ["proj_studymate"])
        XCTAssertEqual(client.usageStatusAPIKeyIDs, ["key_studymate"])
        XCTAssertFalse(appState.hasAPIKeyError)
    }

    @MainActor
    func testRefreshOpenAIBillingStatusWarnsWhenProjectCostIsZeroButOrganizationHasCost() async {
        let suiteName = "StudyMateTests-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defer {
            defaults.removePersistentDomain(forName: suiteName)
        }

        let store = SettingsStore(defaults: defaults)
        store.saveAPIKey("sk-project")
        store.saveAdminAPIKey("sk-admin")
        store.saveOpenAIUsageProjectID("proj_empty")
        let client = SpyOpenAIClient()
        client.billingStatusesByProjectID = [
            "proj_empty": OpenAIBillingStatus(
                spentAmount: 0,
                currency: "usd",
                periodStart: Date(timeIntervalSince1970: 0),
                periodEnd: Date(timeIntervalSince1970: 1),
                checkedAt: Date(timeIntervalSince1970: 1)
            ),
            "": OpenAIBillingStatus(
                spentAmount: 10.8,
                currency: "usd",
                periodStart: Date(timeIntervalSince1970: 0),
                periodEnd: Date(timeIntervalSince1970: 1),
                checkedAt: Date(timeIntervalSince1970: 1)
            )
        ]
        let appState = AppState(settingsStore: store, openAIClient: client)

        await appState.refreshOpenAIBillingStatus()

        XCTAssertEqual(client.billingStatusProjectIDs, ["proj_empty", nil])
        XCTAssertEqual(client.billingStatusAPIKeyIDs, [nil, nil])
        XCTAssertEqual(appState.openAIBillingStatus?.spentAmount, 0)
        XCTAssertTrue(appState.openAIBillingMessage?.contains("$10.80") == true)
    }

    @MainActor
    func testSaveSettingsWithAPIKeyChangeValidatesTrimmedSecret() async {
        let suiteName = "StudyMateTests-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defer {
            defaults.removePersistentDomain(forName: suiteName)
        }

        let store = SettingsStore(defaults: defaults)
        store.saveAPIKey("sk-old")
        let client = SpyOpenAIClient()
        let appState = AppState(settingsStore: store, openAIClient: client)

        appState.apiKey = "  sk-new  "

        await appState.saveSettingsAndValidateAPIKey()

        XCTAssertEqual(client.validateCallCount, 1)
        XCTAssertEqual(client.validatedAPIKeys, ["sk-new"])
        XCTAssertEqual(store.loadAPIKey(), "sk-new")
    }

    @MainActor
    func testEmptyAPIKeyStartsWithAPIKeyErrorIndicator() {
        let suiteName = "StudyMateTests-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defer {
            defaults.removePersistentDomain(forName: suiteName)
        }

        let store = SettingsStore(defaults: defaults)
        store.saveIsRunning(false)

        let appState = AppState(settingsStore: store)

        XCTAssertTrue(appState.hasAPIKeyError)
    }

    func testAppLogsArePersistedAndCapped() {
        let suiteName = "StudyMateTests-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defer {
            defaults.removePersistentDomain(forName: suiteName)
        }

        let store = SettingsStore(defaults: defaults)

        for index in 1...1005 {
            store.appendAppLog(AppLogEntry(level: .info, message: "Log \(index)"))
        }

        let logs = store.loadAppLogs()

        XCTAssertEqual(logs.count, 1000)
        XCTAssertEqual(logs.first?.message, "Log 6")
        XCTAssertEqual(logs.last?.message, "Log 1005")
    }

    func testLoadingOversizedAppLogsPersistsCappedLogs() throws {
        let suiteName = "StudyMateTests-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defer {
            defaults.removePersistentDomain(forName: suiteName)
        }

        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let oversizedLogs = (1...1205).map { index in
            AppLogEntry(level: .info, message: "Log \(index)")
        }
        defaults.set(try encoder.encode(oversizedLogs), forKey: "appLogs")

        let store = SettingsStore(defaults: defaults)
        let logs = store.loadAppLogs()
        let persistedData = try XCTUnwrap(defaults.data(forKey: "appLogs"))
        let persistedLogs = try decoder.decode([AppLogEntry].self, from: persistedData)

        XCTAssertEqual(logs.count, SettingsStore.maxLogCount)
        XCTAssertEqual(persistedLogs.count, SettingsStore.maxLogCount)
        XCTAssertEqual(logs.first?.message, "Log 206")
        XCTAssertEqual(persistedLogs.first?.message, "Log 206")
    }

    func testAppLogsLoadNewestFirstPages() {
        let suiteName = "StudyMateTests-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defer {
            defaults.removePersistentDomain(forName: suiteName)
        }

        let store = SettingsStore(defaults: defaults)

        for index in 1...125 {
            store.appendAppLog(AppLogEntry(level: .info, message: "Log \(index)"))
        }

        let firstPage = store.loadAppLogs(page: 0, pageSize: 50)
        let thirdPage = store.loadAppLogs(page: 2, pageSize: 50)
        let overflowPage = store.loadAppLogs(page: 99, pageSize: 50)

        XCTAssertEqual(firstPage.totalCount, 125)
        XCTAssertEqual(firstPage.pageCount, 3)
        XCTAssertEqual(firstPage.entries.count, 50)
        XCTAssertEqual(firstPage.entries.first?.message, "Log 125")
        XCTAssertEqual(firstPage.entries.last?.message, "Log 76")
        XCTAssertEqual(thirdPage.entries.count, 25)
        XCTAssertEqual(thirdPage.entries.first?.message, "Log 25")
        XCTAssertEqual(thirdPage.entries.last?.message, "Log 1")
        XCTAssertEqual(overflowPage.page, 2)
    }

    @MainActor
    func testAppendingAppLogPreservesCurrentLogPage() {
        let suiteName = "StudyMateTests-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defer {
            defaults.removePersistentDomain(forName: suiteName)
        }

        let store = SettingsStore(defaults: defaults)
        for index in 1...125 {
            store.appendAppLog(AppLogEntry(level: .info, message: "Log \(index)"))
        }

        let appState = AppState(settingsStore: store, openAIClient: SpyOpenAIClient())
        appState.loadAppLogPage(2)

        XCTAssertEqual(appState.appLogPage, 2)
        let totalCountBeforeAppending = appState.appLogTotalCount

        appState.setDebuggingEnabled(true)

        XCTAssertEqual(appState.appLogPage, 2)
        XCTAssertEqual(appState.appLogTotalCount, totalCountBeforeAppending + 1)
        XCTAssertFalse(appState.appLogs.contains { $0.message == "디버깅 모드를 켰습니다." })
    }

    @MainActor
    func testAppLogPaginationMovesRepeatedly() {
        let suiteName = "StudyMateTests-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defer {
            defaults.removePersistentDomain(forName: suiteName)
        }

        let store = SettingsStore(defaults: defaults)
        for index in 1...175 {
            store.appendAppLog(AppLogEntry(level: .info, message: "Log \(index)"))
        }

        let appState = AppState(settingsStore: store, openAIClient: SpyOpenAIClient())

        XCTAssertEqual(appState.appLogPage, 0)
        XCTAssertEqual(appState.appLogPageCount, 4)

        appState.loadNextAppLogPage()
        XCTAssertEqual(appState.appLogPage, 1)

        appState.loadNextAppLogPage()
        XCTAssertEqual(appState.appLogPage, 2)

        appState.loadPreviousAppLogPage()
        XCTAssertEqual(appState.appLogPage, 1)

        appState.loadPreviousAppLogPage()
        XCTAssertEqual(appState.appLogPage, 0)
    }

    func testDebuggingSettingRoundTripUsesUserDefaults() {
        let suiteName = "StudyMateTests-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defer {
            defaults.removePersistentDomain(forName: suiteName)
        }

        let store = SettingsStore(defaults: defaults)

        XCTAssertFalse(store.loadIsDebuggingEnabled())

        store.saveIsDebuggingEnabled(true)

        XCTAssertTrue(store.loadIsDebuggingEnabled())
    }

    func testQuestionHistoryKeepsMostRecentUniqueQuestions() {
        let suiteName = "StudyMateTests-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defer {
            defaults.removePersistentDomain(forName: suiteName)
        }

        let store = SettingsStore(defaults: defaults)

        for index in 1...22 {
            store.appendQuestionToHistory(
                QuestionItem(question: "Question \(index)", expectedAnswerHint: nil, createdAt: Date())
            )
        }
        store.appendQuestionToHistory(
            QuestionItem(question: "  QUESTION   22  ", expectedAnswerHint: nil, createdAt: Date())
        )

        let history = store.loadQuestionHistory()

        XCTAssertEqual(history.count, 20)
        XCTAssertEqual(history.first?.question, "Question 3")
        XCTAssertEqual(history.last?.question, "  QUESTION   22  ")
    }

    @MainActor
    func testNotificationReplyLandsOnMatchingStudyQuestion() {
        let suiteName = "StudyMateTests-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defer {
            defaults.removePersistentDomain(forName: suiteName)
        }

        let store = SettingsStore(defaults: defaults)
        let settings = StudySettings(
            topic: "Swift",
            difficulty: .beginner,
            customPrompt: "짧게",
            intervalMinutes: 15
        )
        let question = QuestionItem(
            question: "actor는 어떤 문제를 해결하나요?",
            expectedAnswerHint: nil,
            createdAt: Date()
        )
        store.appendStudyRecord(question: question, settings: settings)
        let appState = AppState(settingsStore: store, openAIClient: SpyOpenAIClient())

        appState.openRecordFromNotification(
            questionCreatedAt: question.createdAt.timeIntervalSince1970,
            replyText: "공유 상태 경쟁을 막습니다."
        )

        let updatedRecord = store.loadStudyRecords()[0]
        XCTAssertEqual(appState.selectedTab, .study)
        XCTAssertNil(appState.focusedRecordRequest)
        XCTAssertEqual(appState.currentQuestion?.question, question.question)
        XCTAssertEqual(appState.lastAnswer, "공유 상태 경쟁을 막습니다.")
        XCTAssertEqual(updatedRecord.answer, "공유 상태 경쟁을 막습니다.")
        XCTAssertNil(updatedRecord.gradingResult)
    }

    @MainActor
    func testDeletedNotificationQuestionDoesNotOpenFallbackRecord() {
        let suiteName = "StudyMateTests-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defer {
            defaults.removePersistentDomain(forName: suiteName)
        }

        let store = SettingsStore(defaults: defaults)
        let settings = StudySettings(
            topic: "Swift",
            difficulty: .beginner,
            customPrompt: "짧게",
            intervalMinutes: 15
        )
        let deletedQuestion = QuestionItem(
            question: "삭제된 질문입니다.",
            expectedAnswerHint: nil,
            createdAt: Date(timeIntervalSince1970: 1_000)
        )
        let remainingQuestion = QuestionItem(
            question: "남아있는 질문입니다.",
            expectedAnswerHint: nil,
            createdAt: Date(timeIntervalSince1970: 2_000)
        )
        store.appendStudyRecord(question: deletedQuestion, settings: settings)
        store.appendStudyRecord(question: remainingQuestion, settings: settings)

        let appState = AppState(settingsStore: store, openAIClient: SpyOpenAIClient())
        let deletedRecord = store.loadStudyRecords().first {
            $0.question.createdAt == deletedQuestion.createdAt
        }
        guard let deletedRecord else {
            XCTFail("Expected deleted question record to exist before deleting it.")
            return
        }

        appState.deleteStudyRecord(deletedRecord)

        let didOpen = appState.openRecordFromNotification(
            questionCreatedAt: deletedQuestion.createdAt.timeIntervalSince1970
        )

        XCTAssertFalse(didOpen)
        XCTAssertEqual(appState.selectedTab, .study)
        XCTAssertNil(appState.currentQuestion)
        XCTAssertEqual(appState.notificationLandingMessage, appState.strings.notificationQuestionUnavailable)
        XCTAssertEqual(appState.statusMessage, appState.strings.notificationQuestionUnavailable)
        XCTAssertTrue(store.loadStudyRecords().contains { $0.question == remainingQuestion })
    }

    @MainActor
    func testMissingNotificationQuestionPreservesActiveDraft() {
        let suiteName = "StudyMateTests-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defer {
            defaults.removePersistentDomain(forName: suiteName)
        }

        let store = SettingsStore(defaults: defaults)
        let settings = StudySettings(
            topic: "Swift",
            difficulty: .level5,
            customPrompt: "짧게",
            intervalMinutes: 15
        )
        let deletedQuestion = QuestionItem(
            question: "이미 넘긴 알림 질문입니다.",
            expectedAnswerHint: nil,
            createdAt: Date(timeIntervalSince1970: 1_000)
        )
        let activeQuestion = QuestionItem(
            question: "작성 중인 답변은 유지되어야 합니다.",
            expectedAnswerHint: nil,
            createdAt: Date(timeIntervalSince1970: 2_000)
        )
        store.appendStudyRecord(question: deletedQuestion, settings: settings)
        store.appendStudyRecord(question: activeQuestion, settings: settings)

        let appState = AppState(settingsStore: store, openAIClient: SpyOpenAIClient())
        guard let deletedRecord = store.loadStudyRecords().first(where: { $0.question == deletedQuestion }),
              let activeRecord = store.loadStudyRecords().first(where: { $0.question == activeQuestion }) else {
            XCTFail("Expected records to exist before deleting one.")
            return
        }

        appState.selectStudyRecord(activeRecord)
        appState.updateAnswer("작성 중인 답변")
        appState.deleteStudyRecord(deletedRecord)

        let didOpen = appState.openRecordFromNotification(
            questionCreatedAt: deletedQuestion.createdAt.timeIntervalSince1970
        )

        XCTAssertFalse(didOpen)
        XCTAssertEqual(appState.selectedTab, .study)
        XCTAssertEqual(appState.currentQuestion?.question, activeQuestion.question)
        XCTAssertEqual(appState.lastAnswer, "작성 중인 답변")
        XCTAssertEqual(appState.notificationLandingMessage, appState.strings.notificationQuestionUnavailable)
        XCTAssertEqual(appState.statusMessage, appState.strings.notificationQuestionUnavailable)
    }

    @MainActor
    func testNotificationWithoutCreatedAtPreservesActiveDraft() {
        let suiteName = "StudyMateTests-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defer {
            defaults.removePersistentDomain(forName: suiteName)
        }

        let store = SettingsStore(defaults: defaults)
        let settings = StudySettings(
            topic: "Swift",
            difficulty: .level5,
            customPrompt: "짧게",
            intervalMinutes: 15
        )
        let activeQuestion = QuestionItem(
            question: "작성 중인 답변은 알림 오류 뒤에도 유지되어야 합니다.",
            expectedAnswerHint: nil,
            createdAt: Date(timeIntervalSince1970: 2_000)
        )
        store.appendStudyRecord(question: activeQuestion, settings: settings)

        let appState = AppState(settingsStore: store, openAIClient: SpyOpenAIClient())
        guard let activeRecord = store.loadStudyRecords().first(where: { $0.question == activeQuestion }) else {
            XCTFail("Expected active record to exist.")
            return
        }

        appState.selectStudyRecord(activeRecord)
        appState.updateAnswer("작성 중인 답변")

        let didOpen = appState.openRecordFromNotification(questionCreatedAt: nil)

        XCTAssertFalse(didOpen)
        XCTAssertEqual(appState.selectedTab, .study)
        XCTAssertEqual(appState.currentQuestion?.question, activeQuestion.question)
        XCTAssertEqual(appState.lastAnswer, "작성 중인 답변")
        XCTAssertEqual(appState.notificationLandingMessage, appState.strings.notificationQuestionUnavailable)
        XCTAssertEqual(appState.statusMessage, appState.strings.notificationQuestionUnavailable)
    }

    @MainActor
    func testSkippedNotificationQuestionShowsUnavailableLanding() {
        let suiteName = "StudyMateTests-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defer {
            defaults.removePersistentDomain(forName: suiteName)
        }

        let store = SettingsStore(defaults: defaults)
        let settings = StudySettings(topic: "Notifications", difficulty: .level5, customPrompt: "짧게", intervalMinutes: 15)
        let skippedQuestion = QuestionItem(
            question: "넘긴 질문 알림을 누르면 어떻게 되나요?",
            expectedAnswerHint: nil,
            createdAt: Date(timeIntervalSince1970: 1_000)
        )
        store.saveQuestion(skippedQuestion)
        store.appendStudyRecord(question: skippedQuestion, settings: settings)
        let appState = AppState(settingsStore: store, openAIClient: SpyOpenAIClient())

        appState.skipCurrentQuestion()
        let didOpen = appState.openRecordFromNotification(
            questionCreatedAt: skippedQuestion.createdAt.timeIntervalSince1970
        )

        XCTAssertFalse(didOpen)
        XCTAssertEqual(appState.selectedTab, .study)
        XCTAssertNil(appState.currentQuestion)
        XCTAssertEqual(appState.notificationLandingMessage, appState.strings.notificationQuestionUnavailable)
        XCTAssertEqual(appState.statusMessage, appState.strings.notificationQuestionUnavailable)
    }

    @MainActor
    func testSelectingPendingStudyRecordLoadsDraftAnswer() {
        let suiteName = "StudyMateTests-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defer {
            defaults.removePersistentDomain(forName: suiteName)
        }

        let store = SettingsStore(defaults: defaults)
        let settings = StudySettings(
            topic: "운영체제",
            difficulty: .intermediate,
            customPrompt: "짧게",
            intervalMinutes: 15
        )
        let question = QuestionItem(
            question: "프로세스와 스레드의 차이는?",
            expectedAnswerHint: nil,
            createdAt: Date()
        )
        store.appendStudyRecord(question: question, settings: settings)
        store.updateStudyRecordAnswer(question: question, answer: "프로세스는 자원을 갖고 스레드는 실행 흐름입니다.")

        let record = store.loadStudyRecords()[0]
        let appState = AppState(settingsStore: store, openAIClient: SpyOpenAIClient())

        appState.selectStudyRecord(record)

        XCTAssertEqual(appState.selectedTab, .study)
        XCTAssertEqual(appState.currentQuestion?.question, question.question)
        XCTAssertEqual(appState.lastAnswer, "프로세스는 자원을 갖고 스레드는 실행 흐름입니다.")
        XCTAssertNil(appState.gradingResult)
        XCTAssertEqual(appState.pendingStudyRecords.count, 1)
    }

    @MainActor
    func testGradeCurrentAnswerUsesSubmittedDraftAnswer() async {
        let suiteName = "StudyMateTests-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defer {
            defaults.removePersistentDomain(forName: suiteName)
        }

        let store = SettingsStore(defaults: defaults)
        store.saveAPIKey("sk-test")
        let settings = StudySettings(
            topic: "네트워크",
            difficulty: .intermediate,
            customPrompt: "짧게",
            intervalMinutes: 15
        )
        store.saveSettings(settings)
        let question = QuestionItem(
            question: "TCP와 UDP의 차이는?",
            expectedAnswerHint: nil,
            createdAt: Date()
        )
        store.saveQuestion(question)
        store.appendStudyRecord(question: question, settings: settings)
        store.saveLastAnswer("")

        let client = SpyOpenAIClient()
        client.gradingResult = GradingResult(score: 88, isCorrect: true, feedback: "좋아요.", explanation: "핵심을 설명했습니다.")
        let appState = AppState(settingsStore: store, openAIClient: client)

        await appState.gradeCurrentAnswer(answer: "TCP는 연결형이고 UDP는 비연결형입니다.")

        XCTAssertEqual(client.gradedAnswers, ["TCP는 연결형이고 UDP는 비연결형입니다."])
        XCTAssertEqual(appState.lastAnswer, "TCP는 연결형이고 UDP는 비연결형입니다.")
        XCTAssertEqual(store.loadStudyRecords().first?.answer, "TCP는 연결형이고 UDP는 비연결형입니다.")
        XCTAssertEqual(store.loadStudyRecords().first?.gradingResult?.score, 88)
    }

    @MainActor
    func testRefreshVisibleDataReloadsPersistedStudyState() async {
        let suiteName = "StudyMateTests-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defer {
            defaults.removePersistentDomain(forName: suiteName)
        }

        let store = SettingsStore(defaults: defaults)
        let appState = AppState(settingsStore: store, openAIClient: SpyOpenAIClient())
        XCTAssertTrue(appState.studyRecords.isEmpty)

        let settings = StudySettings(
            topic: "운영체제",
            difficulty: .level6,
            customPrompt: "짧게",
            intervalMinutes: 20
        )
        let question = QuestionItem(
            question: "스케줄러는 무엇을 하나요?",
            expectedAnswerHint: nil,
            createdAt: Date()
        )
        store.saveSettings(settings)
        store.saveQuestion(question)
        store.saveLastAnswer("CPU 시간을 배분합니다.")
        store.appendStudyRecord(question: question, settings: settings)

        await appState.refreshVisibleData()

        XCTAssertEqual(appState.settings.topic, "운영체제")
        XCTAssertEqual(appState.currentQuestion?.question, question.question)
        XCTAssertEqual(appState.lastAnswer, "CPU 시간을 배분합니다.")
        XCTAssertEqual(appState.studyRecords.count, 1)
        XCTAssertEqual(appState.statusMessage, appState.strings.refreshed)
    }

    @MainActor
    func testSkippingCurrentQuestionDeletesUngradedRecordAndOpensNextPending() {
        let suiteName = "StudyMateTests-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defer {
            defaults.removePersistentDomain(forName: suiteName)
        }

        let store = SettingsStore(defaults: defaults)
        let settings = StudySettings(
            topic: "Redis",
            difficulty: .intermediate,
            customPrompt: "짧게",
            intervalMinutes: 15
        )
        let olderQuestion = QuestionItem(
            question: "Stream ID는 어떤 의미인가요?",
            expectedAnswerHint: nil,
            createdAt: Date(timeIntervalSince1970: 100)
        )
        let newerQuestion = QuestionItem(
            question: "MAXLEN ~ 옵션은 언제 쓰나요?",
            expectedAnswerHint: nil,
            createdAt: Date(timeIntervalSince1970: 200)
        )

        store.appendStudyRecord(question: olderQuestion, settings: settings)
        store.appendStudyRecord(question: newerQuestion, settings: settings)

        let newerRecord = store.loadStudyRecords().last!
        let appState = AppState(settingsStore: store, openAIClient: SpyOpenAIClient())
        appState.selectStudyRecord(newerRecord)

        appState.skipCurrentQuestion()

        let records = store.loadStudyRecords()
        XCTAssertEqual(records.count, 1)
        XCTAssertEqual(records.first?.question.question, olderQuestion.question)
        XCTAssertEqual(appState.currentQuestion?.question, olderQuestion.question)
        XCTAssertEqual(appState.pendingStudyRecords.count, 1)
    }

    @MainActor
    func testSkippingNonCurrentPendingQuestionPreservesCurrentQuestion() {
        let suiteName = "StudyMateTests-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defer {
            defaults.removePersistentDomain(forName: suiteName)
        }

        let store = SettingsStore(defaults: defaults)
        let settings = StudySettings(
            topic: "Redis",
            difficulty: .intermediate,
            customPrompt: "짧게",
            intervalMinutes: 15
        )
        let currentQuestion = QuestionItem(
            question: "현재 답변 중인 질문",
            expectedAnswerHint: nil,
            createdAt: Date(timeIntervalSince1970: 300)
        )
        let skippedQuestion = QuestionItem(
            question: "리스트에서 넘길 질문",
            expectedAnswerHint: nil,
            createdAt: Date(timeIntervalSince1970: 200)
        )

        store.appendStudyRecord(question: skippedQuestion, settings: settings)
        store.appendStudyRecord(question: currentQuestion, settings: settings)
        let records = store.loadStudyRecords()
        let skippedRecord = records.first { $0.question == skippedQuestion }!
        let currentRecord = records.first { $0.question == currentQuestion }!
        let appState = AppState(settingsStore: store, openAIClient: SpyOpenAIClient())
        appState.selectStudyRecord(currentRecord)

        appState.skipPendingQuestion(skippedRecord)

        XCTAssertEqual(appState.currentQuestion?.question, currentQuestion.question)
        XCTAssertEqual(appState.studyRecords.count, 1)
        XCTAssertFalse(appState.studyRecords.contains { $0.question == skippedQuestion })
        XCTAssertEqual(appState.pendingStudyRecords.count, 1)
    }

    @MainActor
    func testPendingQuestionLimitPreventsNewQuestionGeneration() async {
        let suiteName = "StudyMateTests-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defer {
            defaults.removePersistentDomain(forName: suiteName)
        }

        let store = SettingsStore(defaults: defaults)
        let settings = StudySettings(
            topic: "Redis",
            difficulty: .intermediate,
            customPrompt: "짧게",
            intervalMinutes: 15
        )
        store.saveSettings(settings)

        for index in 0..<3 {
            let question = QuestionItem(
                question: "미채점 질문 \(index)",
                expectedAnswerHint: nil,
                createdAt: Date(timeIntervalSince1970: Double(index))
            )
            store.appendStudyRecord(question: question, settings: settings)
        }

        let client = SpyOpenAIClient()
        let appState = AppState(settingsStore: store, openAIClient: client)

        await appState.generateQuestion()

        XCTAssertTrue(appState.hasReachedPendingQuestionLimit)
        XCTAssertEqual(appState.statusMessage, appState.strings.pendingQuestionLimitTitle)
        XCTAssertEqual(client.generateCallCount, 0)
        XCTAssertEqual(appState.pendingStudyRecords.count, 3)
    }

    @MainActor
    func testPendingQuestionLimitCountsCurrentQuestionWithoutRecord() async {
        let suiteName = "StudyMateTests-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defer {
            defaults.removePersistentDomain(forName: suiteName)
        }

        let store = SettingsStore(defaults: defaults)
        let settings = StudySettings(
            topic: "Swift",
            difficulty: .level5,
            customPrompt: "짧게",
            intervalMinutes: 15
        )
        store.saveSettings(settings)

        for index in 0..<2 {
            let question = QuestionItem(
                question: "기록된 미채점 질문 \(index)",
                expectedAnswerHint: nil,
                createdAt: Date(timeIntervalSince1970: Double(index))
            )
            store.appendStudyRecord(question: question, settings: settings)
        }

        let currentQuestion = QuestionItem(
            question: "현재 화면의 미채점 질문",
            expectedAnswerHint: nil,
            createdAt: Date(timeIntervalSince1970: 3)
        )
        store.saveQuestion(currentQuestion)
        store.saveGradingResult(nil)
        store.saveLastAnswer("")

        let client = SpyOpenAIClient()
        let appState = AppState(settingsStore: store, openAIClient: client)

        await appState.generateQuestion()

        XCTAssertTrue(appState.hasReachedPendingQuestionLimit)
        XCTAssertEqual(client.generateCallCount, 0)
        XCTAssertEqual(appState.pendingStudyRecords.count, 3)
        XCTAssertEqual(store.loadStudyRecords().count, 2)
    }

    @MainActor
    func testCloudQuestionPushDoesNotAddRecordWhenPendingLimitReached() async {
        let suiteName = "StudyMateTests-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defer {
            defaults.removePersistentDomain(forName: suiteName)
        }

        let store = SettingsStore(defaults: defaults)
        let settings = StudySettings(
            topic: "CloudKit",
            difficulty: .level5,
            customPrompt: "짧게",
            intervalMinutes: 15
        )
        store.saveSettings(settings)
        store.saveIsCloudSyncEnabled(true)

        for index in 0..<3 {
            let question = QuestionItem(
                question: "기존 미채점 질문 \(index)",
                expectedAnswerHint: nil,
                createdAt: Date(timeIntervalSince1970: Double(index))
            )
            store.appendStudyRecord(question: question, settings: settings)
        }

        let pushedQuestion = QuestionItem(
            question: "초과 CloudKit push 질문",
            expectedAnswerHint: nil,
            createdAt: Date(timeIntervalSince1970: 100)
        )
        let syncService = FakeCloudSyncService(remoteSnapshot: nil)
        syncService.questionPushesByRecordName["question-100000"] = CloudQuestionPush(
            question: pushedQuestion,
            topic: "CloudKit",
            difficulty: .level5
        )
        let appState = AppState(settingsStore: store, openAIClient: SpyOpenAIClient(), cloudSyncService: syncService)

        let didHandle = await appState.handleCloudQuestionPush(
            recordName: "question-100000",
            openStudy: false
        )

        XCTAssertTrue(didHandle)
        XCTAssertEqual(appState.pendingStudyRecords.count, 3)
        XCTAssertFalse(appState.studyRecords.contains { $0.question == pushedQuestion })
    }

    @MainActor
    func testCloudSyncPreservesRemoteUngradedOverflow() async {
        let suiteName = "StudyMateTests-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defer {
            defaults.removePersistentDomain(forName: suiteName)
        }

        let store = SettingsStore(defaults: defaults)
        store.saveIsCloudSyncEnabled(true)

        let settings = StudySettings(
            topic: "CloudKit",
            difficulty: .level5,
            customPrompt: "짧게",
            intervalMinutes: 15
        )
        let questions = (0..<4).map { index in
            QuestionItem(
                question: "원격 미채점 질문 \(index)",
                expectedAnswerHint: nil,
                createdAt: Date(timeIntervalSince1970: Double(index))
            )
        }
        let snapshot = CloudSyncSnapshot(
            updatedAt: Date(timeIntervalSince1970: 100),
            settings: settings,
            currentQuestion: questions[3],
            questionHistory: questions,
            lastAnswer: "",
            gradingResult: nil,
            isRunning: true,
            hasCompletedOnboarding: true,
            studyRecords: questions.map {
                StudyRecord(question: $0, topic: "CloudKit", difficulty: .level5)
            }
        )
        let syncService = FakeCloudSyncService(remoteSnapshot: snapshot)
        let appState = AppState(settingsStore: store, openAIClient: SpyOpenAIClient(), cloudSyncService: syncService)

        await appState.syncCloudNow()

        XCTAssertEqual(appState.pendingStudyRecords.count, 4)
        XCTAssertEqual(store.loadStudyRecords().filter { $0.gradingResult == nil }.count, 4)
        XCTAssertTrue(appState.studyRecords.contains { $0.question == questions[3] })
    }

    @MainActor
    func testGenerateQuestionSyncsCloudBeforeCreatingWhenRemotePendingLimitReached() async {
        let suiteName = "StudyMateTests-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defer {
            defaults.removePersistentDomain(forName: suiteName)
        }

        let store = SettingsStore(defaults: defaults)
        let settings = StudySettings(
            topic: "CloudKit",
            difficulty: .level5,
            customPrompt: "짧게",
            intervalMinutes: 15
        )
        store.saveSettings(settings)
        store.saveIsCloudSyncEnabled(true)
        store.saveCloudSyncSnapshotUpdatedAt(Date(timeIntervalSince1970: 50))

        for index in 0..<2 {
            store.appendStudyRecord(
                question: QuestionItem(
                    question: "로컬 미채점 질문 \(index)",
                    expectedAnswerHint: nil,
                    createdAt: Date(timeIntervalSince1970: Double(index))
                ),
                settings: settings
            )
        }

        let remoteQuestions = (0..<3).map { index in
            QuestionItem(
                question: "원격 미채점 질문 \(index)",
                expectedAnswerHint: nil,
                createdAt: Date(timeIntervalSince1970: Double(100 + index))
            )
        }
        let remoteSnapshot = CloudSyncSnapshot(
            updatedAt: Date(timeIntervalSince1970: 100),
            settings: settings,
            currentQuestion: remoteQuestions[2],
            questionHistory: remoteQuestions,
            lastAnswer: "",
            gradingResult: nil,
            isRunning: true,
            hasCompletedOnboarding: true,
            studyRecords: remoteQuestions.map {
                StudyRecord(question: $0, topic: "CloudKit", difficulty: .level5)
            }
        )
        let client = SpyOpenAIClient()
        let appState = AppState(
            settingsStore: store,
            openAIClient: client,
            cloudSyncService: FakeCloudSyncService(remoteSnapshot: remoteSnapshot)
        )

        await appState.generateQuestion()

        XCTAssertEqual(client.generateCallCount, 0)
        XCTAssertEqual(appState.pendingStudyRecords.count, 5)
        XCTAssertEqual(appState.statusMessage, appState.strings.pendingQuestionLimitTitle)
    }

    @MainActor
    func testGeneratedQuestionDoesNotSendPushWhenPostSyncPendingLimitIsExceeded() async {
        let suiteName = "StudyMateTests-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defer {
            defaults.removePersistentDomain(forName: suiteName)
        }

        let store = SettingsStore(defaults: defaults)
        let settings = StudySettings(
            topic: "CloudKit",
            difficulty: .level5,
            customPrompt: "짧게",
            intervalMinutes: 15
        )
        store.saveSettings(settings)
        store.saveAPIKey("sk-test")
        store.saveIsCloudSyncEnabled(true)
        store.saveIsRunning(true)

        for index in 0..<2 {
            store.appendStudyRecord(
                question: QuestionItem(
                    question: "로컬 미채점 질문 \(index)",
                    expectedAnswerHint: nil,
                    createdAt: Date(timeIntervalSince1970: Double(index))
                ),
                settings: settings
            )
        }

        let remoteQuestions = (0..<2).map { index in
            QuestionItem(
                question: "생성 후 도착한 원격 질문 \(index)",
                expectedAnswerHint: nil,
                createdAt: Date(timeIntervalSince1970: Double(100 + index))
            )
        }
        let remoteSnapshot = CloudSyncSnapshot(
            updatedAt: Date(timeIntervalSince1970: 100),
            settings: settings,
            currentQuestion: remoteQuestions[1],
            questionHistory: remoteQuestions,
            lastAnswer: "",
            gradingResult: nil,
            isRunning: true,
            hasCompletedOnboarding: true,
            studyRecords: remoteQuestions.map {
                StudyRecord(question: $0, topic: "CloudKit", difficulty: .level5)
            }
        )
        let generatedQuestion = QuestionItem(
            question: "방금 생성한 질문",
            expectedAnswerHint: nil,
            createdAt: Date(timeIntervalSince1970: 200)
        )
        let client = SpyOpenAIClient()
        client.generatedQuestionResult = GeneratedQuestionResult(question: generatedQuestion, responseID: "resp_new")
        let syncService = FakeCloudSyncService(remoteSnapshot: nil)
        syncService.fetchSnapshots = [nil, nil, remoteSnapshot]
        let appState = AppState(settingsStore: store, openAIClient: client, cloudSyncService: syncService)

        await appState.generateQuestion(manual: false)

        XCTAssertEqual(client.generateCallCount, 1)
        XCTAssertGreaterThan(appState.pendingStudyRecords.count, AppState.maxPendingQuestionCount)
        XCTAssertEqual(syncService.savedQuestionPushes.count, 0)
        XCTAssertEqual(appState.statusMessage, appState.strings.pendingQuestionLimitTitle)
    }

    @MainActor
    func testCloudQuestionPushSyncsBeforeAddingWhenRemotePendingLimitReached() async {
        let suiteName = "StudyMateTests-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defer {
            defaults.removePersistentDomain(forName: suiteName)
        }

        let store = SettingsStore(defaults: defaults)
        let settings = StudySettings(
            topic: "CloudKit",
            difficulty: .level5,
            customPrompt: "짧게",
            intervalMinutes: 15
        )
        store.saveSettings(settings)
        store.saveIsCloudSyncEnabled(true)
        store.saveCloudSyncSnapshotUpdatedAt(Date(timeIntervalSince1970: 50))

        for index in 0..<2 {
            store.appendStudyRecord(
                question: QuestionItem(
                    question: "로컬 push 전 질문 \(index)",
                    expectedAnswerHint: nil,
                    createdAt: Date(timeIntervalSince1970: Double(index))
                ),
                settings: settings
            )
        }

        let remoteQuestions = (0..<3).map { index in
            QuestionItem(
                question: "원격 push 전 질문 \(index)",
                expectedAnswerHint: nil,
                createdAt: Date(timeIntervalSince1970: Double(200 + index))
            )
        }
        let pushedQuestion = QuestionItem(
            question: "초과 push 질문",
            expectedAnswerHint: nil,
            createdAt: Date(timeIntervalSince1970: 300)
        )
        let remoteSnapshot = CloudSyncSnapshot(
            updatedAt: Date(timeIntervalSince1970: 100),
            settings: settings,
            currentQuestion: remoteQuestions[2],
            questionHistory: remoteQuestions,
            lastAnswer: "",
            gradingResult: nil,
            isRunning: true,
            hasCompletedOnboarding: true,
            studyRecords: remoteQuestions.map {
                StudyRecord(question: $0, topic: "CloudKit", difficulty: .level5)
            }
        )
        let syncService = FakeCloudSyncService(remoteSnapshot: remoteSnapshot)
        syncService.questionPushesByRecordName["question-300000"] = CloudQuestionPush(
            question: pushedQuestion,
            topic: "CloudKit",
            difficulty: .level5
        )
        let appState = AppState(settingsStore: store, openAIClient: SpyOpenAIClient(), cloudSyncService: syncService)

        let didHandle = await appState.handleCloudQuestionPush(
            recordName: "question-300000",
            openStudy: false
        )

        XCTAssertTrue(didHandle)
        XCTAssertEqual(appState.pendingStudyRecords.count, 5)
        XCTAssertFalse(appState.studyRecords.contains { $0.question == pushedQuestion })
    }

    @MainActor
    func testCloudSyncPreservesLocalUngradedOverflowAfterPushingSnapshot() async {
        let suiteName = "StudyMateTests-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defer {
            defaults.removePersistentDomain(forName: suiteName)
        }

        let store = SettingsStore(defaults: defaults)
        let settings = StudySettings(
            topic: "Redis",
            difficulty: .level5,
            customPrompt: "짧게",
            intervalMinutes: 15
        )
        store.saveSettings(settings)
        store.saveIsCloudSyncEnabled(true)
        store.saveCloudSyncSnapshotUpdatedAt(Date(timeIntervalSince1970: 200))

        for index in 0..<5 {
            store.appendStudyRecord(
                question: QuestionItem(
                    question: "초과 로컬 미채점 질문 \(index)",
                    expectedAnswerHint: nil,
                    createdAt: Date(timeIntervalSince1970: Double(index))
                ),
                settings: settings
            )
        }

        let remoteSnapshot = CloudSyncSnapshot(
            updatedAt: Date(timeIntervalSince1970: 100),
            settings: settings,
            currentQuestion: nil,
            questionHistory: [],
            lastAnswer: "",
            gradingResult: nil,
            isRunning: true,
            hasCompletedOnboarding: true,
            studyRecords: []
        )
        let syncService = FakeCloudSyncService(remoteSnapshot: remoteSnapshot)
        let appState = AppState(settingsStore: store, openAIClient: SpyOpenAIClient(), cloudSyncService: syncService)

        await appState.syncCloudNow()

        XCTAssertEqual(appState.pendingStudyRecords.count, 5)
        XCTAssertEqual(store.loadStudyRecords().filter { $0.gradingResult == nil }.count, 5)
        XCTAssertEqual(syncService.savedSnapshot?.studyRecords.filter { $0.gradingResult == nil }.count, 5)
    }

    @MainActor
    func testFirstCloudSyncPreservesRemoteUngradedOverflowWithoutOverwritingRemoteSnapshot() async {
        let suiteName = "StudyMateTests-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defer {
            defaults.removePersistentDomain(forName: suiteName)
        }

        let store = SettingsStore(defaults: defaults)
        let settings = StudySettings(
            topic: "Redis",
            difficulty: .level5,
            customPrompt: "짧게",
            intervalMinutes: 15
        )
        store.saveIsCloudSyncEnabled(true)

        let remoteQuestions = (0..<5).map { index in
            QuestionItem(
                question: "초과 원격 미채점 질문 \(index)",
                expectedAnswerHint: nil,
                createdAt: Date(timeIntervalSince1970: Double(index))
            )
        }
        let remoteSnapshot = CloudSyncSnapshot(
            updatedAt: Date(timeIntervalSince1970: 100),
            settings: settings,
            currentQuestion: remoteQuestions[4],
            questionHistory: remoteQuestions,
            lastAnswer: "",
            gradingResult: nil,
            isRunning: true,
            hasCompletedOnboarding: true,
            studyRecords: remoteQuestions.map {
                StudyRecord(question: $0, topic: "Redis", difficulty: .level5)
            }
        )
        let syncService = FakeCloudSyncService(remoteSnapshot: remoteSnapshot)
        let appState = AppState(settingsStore: store, openAIClient: SpyOpenAIClient(), cloudSyncService: syncService)

        await appState.syncCloudNow()

        XCTAssertEqual(appState.pendingStudyRecords.count, 5)
        XCTAssertNil(syncService.savedSnapshot)
    }

    func testQuestionPromptIncludesRecentQuestionsToAvoid() {
        let settings = StudySettings(
            topic: "Swift Concurrency",
            difficulty: .intermediate,
            appLanguage: .english,
            language: .english,
            customPrompt: "면접 질문처럼",
            intervalMinutes: 15
        )
        let recentQuestions = [
            QuestionItem(question: "actor는 어떤 문제를 해결하나요?", expectedAnswerHint: nil, createdAt: Date()),
            QuestionItem(question: "Task와 Thread의 차이는 무엇인가요?", expectedAnswerHint: nil, createdAt: Date())
        ]

        let prompt = OpenAIClient.questionPrompt(settings: settings, recentQuestions: recentQuestions)

        XCTAssertTrue(prompt.contains("Previous questions to avoid:"))
        XCTAssertTrue(prompt.contains("Language: English"))
        XCTAssertTrue(prompt.contains("Question language instruction: Ask the question in English."))
        XCTAssertTrue(prompt.contains("- Ask the question in English."))
        XCTAssertTrue(prompt.contains("Write the question and expectedAnswerHint in English."))
        XCTAssertTrue(prompt.contains("actor는 어떤 문제를 해결하나요?"))
        XCTAssertTrue(prompt.contains("Do not repeat or closely paraphrase any previous question."))
    }

    func testQuestionPromptUsesAppLanguageOverLegacyStudyLanguage() {
        let settings = StudySettings(
            topic: "Redis",
            difficulty: .level5,
            appLanguage: .korean,
            language: .english,
            customPrompt: "Ask in English if possible.",
            intervalMinutes: 15
        )

        let prompt = OpenAIClient.questionPrompt(settings: settings, recentQuestions: [])

        XCTAssertTrue(prompt.contains("Language: Korean"))
        XCTAssertTrue(prompt.contains("Question language instruction: 한국어로 질문해."))
        XCTAssertTrue(prompt.contains("- 한국어로 질문해."))
        XCTAssertTrue(prompt.contains("Write the question and expectedAnswerHint in Korean."))
    }

    func testStudyRecordIsUpdatedAfterGrading() {
        let suiteName = "StudyMateTests-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defer {
            defaults.removePersistentDomain(forName: suiteName)
        }

        let store = SettingsStore(defaults: defaults)
        let settings = StudySettings(
            topic: "네트워크",
            difficulty: .intermediate,
            customPrompt: "짧게",
            intervalMinutes: 15
        )
        let question = QuestionItem(
            question: "HTTP와 HTTPS의 차이는?",
            expectedAnswerHint: nil,
            createdAt: Date()
        )
        let grading = GradingResult(
            score: 82,
            isCorrect: true,
            feedback: "핵심을 설명했습니다.",
            explanation: "TLS 암호화 차이를 언급했습니다."
        )

        store.appendStudyRecord(question: question, settings: settings)
        store.updateStudyRecord(question: question, answer: "HTTPS는 암호화합니다.", gradingResult: grading)

        let records = store.loadStudyRecords()

        XCTAssertEqual(records.count, 1)
        XCTAssertEqual(records[0].topic, "네트워크")
        XCTAssertEqual(records[0].answer, "HTTPS는 암호화합니다.")
        XCTAssertEqual(records[0].gradingResult?.score, 82)
        XCTAssertNotNil(records[0].answeredAt)
    }

    func testStudyRecordsRespectConfiguredLimit() {
        let suiteName = "StudyMateTests-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defer {
            defaults.removePersistentDomain(forName: suiteName)
        }

        let store = SettingsStore(defaults: defaults)
        let settings = StudySettings(
            topic: "운영체제",
            difficulty: .intermediate,
            customPrompt: "짧게",
            intervalMinutes: 15,
            maxHistoryCount: 10
        )

        store.saveSettings(settings)

        for index in 1...12 {
            store.appendStudyRecord(
                question: QuestionItem(question: "Question \(index)", expectedAnswerHint: nil, createdAt: Date()),
                settings: settings
            )
        }

        let records = store.loadStudyRecords()

        XCTAssertEqual(records.count, 10)
        XCTAssertEqual(records.first?.question.question, "Question 3")
    }

    func testStudyRecordCanBeDeletedIndividually() throws {
        let suiteName = "StudyMateTests-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defer {
            defaults.removePersistentDomain(forName: suiteName)
        }

        let store = SettingsStore(defaults: defaults)
        let settings = StudySettings(
            topic: "Swift",
            difficulty: .beginner,
            customPrompt: "짧게",
            intervalMinutes: 15
        )

        store.appendStudyRecord(
            question: QuestionItem(question: "Question A", expectedAnswerHint: nil, createdAt: Date()),
            settings: settings
        )
        store.appendStudyRecord(
            question: QuestionItem(question: "Question B", expectedAnswerHint: nil, createdAt: Date()),
            settings: settings
        )

        let recordToDelete = try XCTUnwrap(store.loadStudyRecords().first)

        store.deleteStudyRecord(recordToDelete)

        let records = store.loadStudyRecords()
        XCTAssertEqual(records.count, 1)
        XCTAssertEqual(records.first?.question.question, "Question B")
    }

    func testStudyRecordsPersistInSQLiteAcrossStoreInstances() {
        let suiteName = "StudyMateTests-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        let databaseURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("StudyMateTests-\(UUID().uuidString).sqlite")
        defer {
            defaults.removePersistentDomain(forName: suiteName)
            try? FileManager.default.removeItem(at: databaseURL)
        }

        let settings = StudySettings(
            topic: "SQLite",
            difficulty: .intermediate,
            customPrompt: "짧게",
            intervalMinutes: 15
        )
        let firstStore = SettingsStore(defaults: defaults, recordDatabaseURL: databaseURL)
        firstStore.appendStudyRecord(
            question: QuestionItem(question: "FTS5는 무엇인가요?", expectedAnswerHint: nil, createdAt: Date()),
            settings: settings
        )

        let secondStore = SettingsStore(defaults: defaults, recordDatabaseURL: databaseURL)
        let records = secondStore.loadStudyRecords()

        XCTAssertEqual(records.count, 1)
        XCTAssertEqual(records.first?.topic, "SQLite")
        XCTAssertEqual(records.first?.question.question, "FTS5는 무엇인가요?")
    }

    func testLegacyUserDefaultsStudyRecordsMigrateToSQLite() throws {
        let suiteName = "StudyMateTests-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        let databaseURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("StudyMateTests-\(UUID().uuidString).sqlite")
        defer {
            defaults.removePersistentDomain(forName: suiteName)
            try? FileManager.default.removeItem(at: databaseURL)
        }

        let legacyRecord = StudyRecord(
            question: QuestionItem(question: "마이그레이션 질문", expectedAnswerHint: nil, createdAt: Date()),
            topic: "Migration",
            difficulty: .beginner
        )
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        defaults.set(try encoder.encode([legacyRecord]), forKey: "studyRecords")

        let store = SettingsStore(defaults: defaults, recordDatabaseURL: databaseURL)
        let migratedRecords = store.loadStudyRecords()
        let reloadedStore = SettingsStore(defaults: defaults, recordDatabaseURL: databaseURL)

        XCTAssertNil(defaults.data(forKey: "studyRecords"))
        XCTAssertEqual(migratedRecords.count, 1)
        XCTAssertEqual(migratedRecords.first?.question.question, "마이그레이션 질문")
        XCTAssertEqual(reloadedStore.loadStudyRecords().first?.topic, "Migration")
    }

    func testQuestionResponseIDRoundTripUsesUserDefaults() {
        let suiteName = "StudyMateTests-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defer {
            defaults.removePersistentDomain(forName: suiteName)
        }

        let store = SettingsStore(defaults: defaults)

        store.saveQuestionResponseID("resp_123")

        XCTAssertEqual(store.loadQuestionResponseID(), "resp_123")

        store.saveQuestionResponseID(nil)

        XCTAssertNil(store.loadQuestionResponseID())
    }

    func testStructuredRequestBodyUsesModelSpecificTextInterface() throws {
        let schema: [String: Any] = [
            "type": "object",
            "additionalProperties": false,
            "properties": [
                "value": ["type": "string"]
            ],
            "required": ["value"]
        ]

        for option in OpenAIModelOption.all {
            let body = OpenAIClient.structuredRequestBody(
                model: option.id,
                instructions: "Answer as JSON.",
                input: "Question",
                previousResponseID: "resp_123",
                schemaName: "model_interface_test",
                schema: schema
            )

            let text = try XCTUnwrap(body["text"] as? [String: Any], option.id)
            let format = try XCTUnwrap(text["format"] as? [String: Any], option.id)

            XCTAssertEqual(body["model"] as? String, option.id, option.id)
            XCTAssertEqual(body["previous_response_id"] as? String, "resp_123", option.id)
            XCTAssertEqual(format["type"] as? String, "json_schema", option.id)
            XCTAssertEqual(format["name"] as? String, "model_interface_test", option.id)

            if option.supportsTextVerbosity {
                XCTAssertEqual(text["verbosity"] as? String, "low", option.id)
            } else {
                XCTAssertNil(text["verbosity"], "\(option.id) must not send text.verbosity")
            }
        }
    }

    func testExtractOutputTextFromTopLevelOutputText() throws {
        let data = try XCTUnwrap("""
        {
          "output_text": "{\\"question\\":\\"What is Swift?\\",\\"expectedAnswerHint\\":null}"
        }
        """.data(using: .utf8))

        XCTAssertEqual(
            OpenAIClient.extractOutputText(from: data),
            "{\"question\":\"What is Swift?\",\"expectedAnswerHint\":null}"
        )
        XCTAssertNil(OpenAIClient.extractResponseID(from: data))
    }

    func testExtractOutputTextFromResponsesOutputContent() throws {
        let data = try XCTUnwrap("""
        {
          "id": "resp_abc",
          "output": [
            {
              "content": [
                {
                  "type": "output_text",
                  "text": "{\\"score\\":90,\\"isCorrect\\":true,\\"feedback\\":\\"좋아요\\",\\"explanation\\":\\"핵심을 설명했습니다.\\"}"
                }
              ]
            }
          ]
        }
        """.data(using: .utf8))

        XCTAssertEqual(
            OpenAIClient.extractOutputText(from: data),
            "{\"score\":90,\"isCorrect\":true,\"feedback\":\"좋아요\",\"explanation\":\"핵심을 설명했습니다.\"}"
        )
        XCTAssertEqual(OpenAIClient.extractResponseID(from: data), "resp_abc")
    }

    func testGradingResultNormalizesCorrectFlagFromScore() {
        let result = GradingResult(
            score: 6,
            isCorrect: true,
            feedback: "정답에 가까워요.",
            explanation: "설명이 부족합니다."
        )

        let normalized = OpenAIClient.normalizedGradingResult(result)

        XCTAssertEqual(normalized.score, 6)
        XCTAssertFalse(normalized.isCorrect)
    }

    func testGradingResultClampsScore() {
        let result = GradingResult(
            score: 140,
            isCorrect: false,
            feedback: "좋아요.",
            explanation: "충분합니다."
        )

        let normalized = OpenAIClient.normalizedGradingResult(result)

        XCTAssertEqual(normalized.score, 100)
        XCTAssertTrue(normalized.isCorrect)
    }

    func testTopicLevelRangeCombinesMixedDifficultyEvidence() throws {
        let intermediateRecord = StudyRecord(
            question: QuestionItem(question: "Redis Stream은 무엇인가요?", expectedAnswerHint: nil, createdAt: Date()),
            answer: "이벤트 로그입니다.",
            gradingResult: GradingResult(score: 96, isCorrect: true, feedback: "좋아요.", explanation: "충분합니다."),
            topic: "Redis",
            difficulty: .intermediate
        )
        let advancedRecord = StudyRecord(
            question: QuestionItem(question: "Consumer lag를 어떻게 해석하나요?", expectedAnswerHint: nil, createdAt: Date()),
            answer: "대략적인 지연입니다.",
            gradingResult: GradingResult(score: 62, isCorrect: false, feedback: "부분적입니다.", explanation: "핵심 근거가 부족합니다."),
            topic: "Redis",
            difficulty: .advanced
        )

        let range = try XCTUnwrap(TopicLevelRange.calculate(records: [intermediateRecord, advancedRecord]))

        XCTAssertEqual(range.level, .level7)
        XCTAssertEqual(range.startDifficulty, .intermediate)
        XCTAssertEqual(range.endDifficulty, .advanced)
        XCTAssertGreaterThan(range.width, 0.25)
    }

    func testTopicLevelRangeWidensWhenHighLevelFailureAndLowerLevelMasteryConflict() throws {
        let masteredLevelFiveRecord = StudyRecord(
            question: QuestionItem(question: "기본 개념을 설명하세요.", expectedAnswerHint: nil, createdAt: Date()),
            answer: "정확히 설명했습니다.",
            gradingResult: GradingResult(score: 100, isCorrect: true, feedback: "좋아요.", explanation: "충분합니다."),
            topic: "Redis",
            difficulty: .intermediate
        )
        let failedLevelNineRecord = StudyRecord(
            question: QuestionItem(question: "고급 장애 복구 전략을 설명하세요.", expectedAnswerHint: nil, createdAt: Date()),
            answer: "잘 모르겠습니다.",
            gradingResult: GradingResult(score: 5, isCorrect: false, feedback: "부족합니다.", explanation: "핵심을 놓쳤습니다."),
            topic: "Redis",
            difficulty: .advanced
        )

        let range = try XCTUnwrap(TopicLevelRange.calculate(records: [masteredLevelFiveRecord, failedLevelNineRecord]))

        XCTAssertEqual(range.level, .level7)
        XCTAssertEqual(range.startDifficulty, .intermediate)
        XCTAssertEqual(range.endDifficulty, .level8)
        XCTAssertGreaterThan(range.width, 0.2)
    }

    func testTopicLevelRangeHighScoreExtendsTowardNextDifficulty() {
        let range = TopicLevelRange.calculate(level: .advanced, average: 91, sampleCount: 3)

        XCTAssertEqual(range.level, .expert)
        XCTAssertEqual(range.startDifficulty, .advanced)
        XCTAssertEqual(range.endDifficulty, .expert)
        XCTAssertGreaterThan(range.upperBound, range.lowerBound)
    }
}

@MainActor
private final class SpyOpenAIClient: OpenAIClientProtocol {
    var lastUsage: OpenAIUsage?
    var validateCallCount = 0
    var validatedAPIKeys: [String] = []
    var billingStatusAdminAPIKeys: [String] = []
    var billingStatusProjectIDs: [String?] = []
    var billingStatusAPIKeyIDs: [String?] = []
    var usageStatusAdminAPIKeys: [String] = []
    var usageStatusProjectIDs: [String?] = []
    var usageStatusAPIKeyIDs: [String?] = []
    var billingStatusesByProjectID: [String: OpenAIBillingStatus] = [:]
    var generateCallCount = 0
    var generatedQuestionResult: GeneratedQuestionResult?
    var generatedQuestionResults: [GeneratedQuestionResult] = []
    var gradingResult: GradingResult?
    var gradedAnswers: [String] = []

    func validateAPIKey(_ apiKey: String) async throws {
        validateCallCount += 1
        validatedAPIKeys.append(apiKey)
    }

    func fetchBillingStatus(adminAPIKey: String, projectID: String?, apiKeyID: String?) async throws -> OpenAIBillingStatus {
        billingStatusAdminAPIKeys.append(adminAPIKey)
        billingStatusProjectIDs.append(projectID)
        billingStatusAPIKeyIDs.append(apiKeyID)
        if let status = billingStatusesByProjectID[projectID ?? ""] {
            return status
        }

        return OpenAIBillingStatus(
            spentAmount: 1.23,
            currency: "usd",
            periodStart: Date(timeIntervalSince1970: 0),
            periodEnd: Date(timeIntervalSince1970: 1),
            checkedAt: Date(timeIntervalSince1970: 1)
        )
    }

    func fetchUsageStatus(adminAPIKey: String, projectID: String?, apiKeyID: String?) async throws -> OpenAIUsageStatus {
        usageStatusAdminAPIKeys.append(adminAPIKey)
        usageStatusProjectIDs.append(projectID)
        usageStatusAPIKeyIDs.append(apiKeyID)
        return OpenAIUsageStatus(
            inputTokens: 100,
            cachedInputTokens: 20,
            outputTokens: 30,
            requestCount: 2,
            periodStart: Date(timeIntervalSince1970: 0),
            periodEnd: Date(timeIntervalSince1970: 1),
            checkedAt: Date(timeIntervalSince1970: 1)
        )
    }

    func generateQuestion(
        settings: StudySettings,
        recentQuestions: [QuestionItem],
        previousResponseID: String?,
        apiKey: String
    ) async throws -> GeneratedQuestionResult {
        generateCallCount += 1
        if !generatedQuestionResults.isEmpty {
            return generatedQuestionResults.removeFirst()
        }
        if let generatedQuestionResult {
            return generatedQuestionResult
        }
        throw OpenAIClientError.invalidResponse
    }

    func gradeAnswer(question: QuestionItem, answer: String, settings: StudySettings, apiKey: String) async throws -> GradingResult {
        gradedAnswers.append(answer)
        if let gradingResult {
            return gradingResult
        }
        throw OpenAIClientError.invalidResponse
    }
}

private final class URLRequestRecorder: @unchecked Sendable {
    private let lock = NSLock()
    private var values: [String?] = []

    var pageValues: [String?] {
        lock.lock()
        defer {
            lock.unlock()
        }
        return values
    }

    func append(_ value: String?) {
        lock.lock()
        values.append(value)
        lock.unlock()
    }
}

@MainActor
private final class FakeCloudSyncService: CloudSyncServiceProtocol {
    var remoteSnapshot: CloudSyncSnapshot?
    var fetchSnapshots: [CloudSyncSnapshot?] = []
    var savedSnapshot: CloudSyncSnapshot?
    var saveSnapshotCallCount = 0
    var savedQuestionPushes: [(question: QuestionItem, settings: StudySettings)] = []
    var questionPushesByRecordName: [String: CloudQuestionPush] = [:]
    var didEnsureQuestionPushSubscription = false
    var fetchError: Error?
    var saveError: Error?

    init(remoteSnapshot: CloudSyncSnapshot?, fetchError: Error? = nil, saveError: Error? = nil) {
        self.remoteSnapshot = remoteSnapshot
        self.fetchError = fetchError
        self.saveError = saveError
    }

    func fetchSnapshot() async throws -> CloudSyncSnapshot? {
        if let fetchError {
            throw fetchError
        }

        if !fetchSnapshots.isEmpty {
            return fetchSnapshots.removeFirst()
        }

        return remoteSnapshot
    }

    func saveSnapshot(_ snapshot: CloudSyncSnapshot) async throws {
        if let saveError {
            throw saveError
        }

        saveSnapshotCallCount += 1
        savedSnapshot = snapshot
        remoteSnapshot = snapshot
    }

    func ensureQuestionPushSubscription(language: AppLanguage, sound: NotificationSoundOption) async throws {
        didEnsureQuestionPushSubscription = true
    }

    func saveQuestionPush(question: QuestionItem, settings: StudySettings) async throws {
        savedQuestionPushes.append((question, settings))
    }

    func fetchQuestionPush(recordName: String) async throws -> CloudQuestionPush? {
        questionPushesByRecordName[recordName]
    }
}
