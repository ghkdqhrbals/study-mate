import XCTest
@testable import StudyMate

final class StudyMateTests: XCTestCase {
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

        XCTAssertEqual(store.loadSettings().maxHistoryCount, 500)
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

    func testQuestionPromptIncludesRecentQuestionsToAvoid() {
        let settings = StudySettings(
            topic: "Swift Concurrency",
            difficulty: .intermediate,
            language: .english,
            customPrompt: "면접 질문처럼",
            intervalMinutes: 15
        )
        let recentQuestions = [
            QuestionItem(question: "actor는 어떤 문제를 해결하나요?", expectedAnswerHint: nil, createdAt: Date()),
            QuestionItem(question: "Task와 Thread의 차이는 무엇인가요?", expectedAnswerHint: nil, createdAt: Date())
        ]

        let prompt = OpenAIClient.questionPrompt(settings: settings, recentQuestions: recentQuestions)

        XCTAssertTrue(prompt.contains("Recent questions to avoid:"))
        XCTAssertTrue(prompt.contains("Language: English"))
        XCTAssertTrue(prompt.contains("Write the question and expectedAnswerHint in English."))
        XCTAssertTrue(prompt.contains("actor는 어떤 문제를 해결하나요?"))
        XCTAssertTrue(prompt.contains("Do not repeat or closely paraphrase any recent question."))
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
}

@MainActor
private final class SpyOpenAIClient: OpenAIClientProtocol {
    var validateCallCount = 0
    var validatedAPIKeys: [String] = []

    func validateAPIKey(_ apiKey: String) async throws {
        validateCallCount += 1
        validatedAPIKeys.append(apiKey)
    }

    func generateQuestion(
        settings: StudySettings,
        recentQuestions: [QuestionItem],
        previousResponseID: String?,
        apiKey: String
    ) async throws -> GeneratedQuestionResult {
        throw OpenAIClientError.invalidResponse
    }

    func gradeAnswer(question: QuestionItem, answer: String, settings: StudySettings, apiKey: String) async throws -> GradingResult {
        throw OpenAIClientError.invalidResponse
    }
}
