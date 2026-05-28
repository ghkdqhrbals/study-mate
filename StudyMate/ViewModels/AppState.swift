import Foundation
#if os(macOS)
import AppKit
#elseif os(iOS)
import UIKit
#endif

@MainActor
final class AppState: ObservableObject {
    static let developerLogPageSize = 50

    @Published var settings: StudySettings
    @Published var draftSettings: StudySettings
    @Published var currentQuestion: QuestionItem?
    @Published var lastAnswer: String
    @Published var gradingResult: GradingResult?
    @Published var apiKey: String = ""
    @Published var draftAPIKey: String = ""
    @Published var adminAPIKey: String = ""
    @Published var draftAdminAPIKey: String = ""
    @Published var openAIUsageProjectID: String = ""
    @Published var draftOpenAIUsageProjectID: String = ""
    @Published var openAIUsageAPIKeyID: String = ""
    @Published var draftOpenAIUsageAPIKeyID: String = ""
    @Published var isGeneratingQuestion = false
    @Published var isGradingAnswer = false
    @Published var isRunning: Bool
    @Published var studyRecords: [StudyRecord]
    @Published var hasAPIKeyError = false
    @Published var isValidatingAPIKey = false
    @Published var appLogs: [AppLogEntry]
    @Published var appLogTotalCount: Int
    @Published var appLogPage: Int
    @Published var isDebuggingEnabled: Bool
    @Published var statusMessage: String?
    @Published var errorMessage: String?
    @Published var selectedTab: AppTab = .study
    @Published var focusedRecordRequest: FocusedRecordRequest?
    @Published var hasCompletedOnboarding: Bool
    @Published var openAIBillingStatus: OpenAIBillingStatus?
    @Published var openAIUsageStatus: OpenAIUsageStatus?
    @Published var isRefreshingBillingStatus = false
    @Published var isRefreshingVisibleData = false
    @Published var openAIBillingMessage: String?
    @Published var isCloudSyncEnabled: Bool
    @Published var isCloudSyncing = false
    @Published var cloudSyncMessage: String?
    @Published var hasCloudSyncError = false
    @Published var cloudLastSyncedAt: Date?

    private let settingsStore: SettingsStore
    private let openAIClient: OpenAIClientProtocol
    private let notificationService: NotificationService
    private var cloudSyncService: CloudSyncServiceProtocol?
    private var timerTask: Task<Void, Never>?
    private var cloudSyncTask: Task<Void, Never>?
    private var didStart = false
    private var savedSettings: StudySettings
    private var savedAPIKey: String
    private var savedAdminAPIKey: String
    private var savedOpenAIUsageProjectID: String
    private var savedOpenAIUsageAPIKeyID: String
    private var isEditingSettings = false

    var strings: AppStrings {
        AppStrings(language: settings.appLanguage)
    }

    var settingsEditorStrings: AppStrings {
        AppStrings(language: draftSettings.appLanguage)
    }

    var statusTitle: String {
        strings.statusTitle(isRunning: isRunning)
    }

    var hasUnsavedSettingsChanges: Bool {
        normalizedSettings(activeSettingsForEditing) != savedSettings ||
            activeAPIKeyForEditing.trimmingCharacters(in: .whitespacesAndNewlines) != savedAPIKey ||
            activeAdminAPIKeyForEditing.trimmingCharacters(in: .whitespacesAndNewlines) != savedAdminAPIKey ||
            activeOpenAIUsageProjectIDForEditing.trimmingCharacters(in: .whitespacesAndNewlines) != savedOpenAIUsageProjectID ||
            activeOpenAIUsageAPIKeyIDForEditing.trimmingCharacters(in: .whitespacesAndNewlines) != savedOpenAIUsageAPIKeyID
    }

    var apiKeyValidationMessage: String? {
        guard hasAPIKeyError else {
            return nil
        }

        let strings = AppStrings(language: activeSettingsForEditing.appLanguage)
        if activeAPIKeyForEditing.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return strings.apiKeyEmpty
        }

        return errorMessage ?? strings.apiKeyCheck
    }

    private var activeSettingsForEditing: StudySettings {
        isEditingSettings ? draftSettings : settings
    }

    private var activeAPIKeyForEditing: String {
        isEditingSettings ? draftAPIKey : apiKey
    }

    private var activeAdminAPIKeyForEditing: String {
        isEditingSettings ? draftAdminAPIKey : adminAPIKey
    }

    private var activeOpenAIUsageProjectIDForEditing: String {
        isEditingSettings ? draftOpenAIUsageProjectID : openAIUsageProjectID
    }

    private var activeOpenAIUsageAPIKeyIDForEditing: String {
        isEditingSettings ? draftOpenAIUsageAPIKeyID : openAIUsageAPIKeyID
    }

    var pendingQuestionCount: Int {
        studyRecords.filter { $0.gradingResult == nil }.count
    }

    var hasReachedPendingQuestionLimit: Bool {
        pendingQuestionCount >= 3
    }

    var pendingStudyRecords: [StudyRecord] {
        studyRecords
            .filter { $0.gradingResult == nil }
            .sorted { $0.question.createdAt > $1.question.createdAt }
    }

    var canSkipCurrentQuestion: Bool {
        guard let currentRecord = studyRecord(matching: currentQuestion) else {
            return currentQuestion != nil
        }

        return currentRecord.gradingResult == nil
    }

    var appLogPageCount: Int {
        max(1, (appLogTotalCount + Self.developerLogPageSize - 1) / Self.developerLogPageSize)
    }

    var appLogPageStart: Int {
        guard appLogTotalCount > 0 else {
            return 0
        }

        return appLogPage * Self.developerLogPageSize + 1
    }

    var appLogPageEnd: Int {
        guard appLogTotalCount > 0 else {
            return 0
        }

        return min(appLogPageStart + appLogs.count - 1, appLogTotalCount)
    }

    init(
        settingsStore: SettingsStore = SettingsStore(),
        openAIClient: OpenAIClientProtocol? = nil,
        notificationService: NotificationService = NotificationService(),
        cloudSyncService: CloudSyncServiceProtocol? = nil
    ) {
        let loadedSettings = settingsStore.loadSettings()
        let loadedAPIKey = settingsStore.loadAPIKey()
        let loadedAdminAPIKey = settingsStore.loadAdminAPIKey()
        let loadedOpenAIUsageProjectID = settingsStore.loadOpenAIUsageProjectID()
        let loadedOpenAIUsageAPIKeyID = settingsStore.loadOpenAIUsageAPIKeyID()
        let loadedLogPage = settingsStore.loadAppLogs(page: 0, pageSize: Self.developerLogPageSize)
        let loadedHasCompletedOnboarding = settingsStore.loadHasCompletedOnboarding()
        let loadedOpenAIBillingStatus = settingsStore.loadOpenAIBillingStatus()
        let loadedOpenAIUsageStatus = settingsStore.loadOpenAIUsageStatus()
        let loadedCloudLastSyncedAt = settingsStore.loadCloudSyncSnapshotUpdatedAt()

        self.settingsStore = settingsStore
        self.settings = loadedSettings
        self.draftSettings = loadedSettings
        self.currentQuestion = settingsStore.loadQuestion()
        self.lastAnswer = settingsStore.loadLastAnswer()
        self.gradingResult = settingsStore.loadGradingResult()
        self.isRunning = settingsStore.loadIsRunning()
        self.studyRecords = settingsStore.loadStudyRecords()
        self.apiKey = loadedAPIKey
        self.draftAPIKey = loadedAPIKey
        self.adminAPIKey = loadedAdminAPIKey
        self.draftAdminAPIKey = loadedAdminAPIKey
        self.openAIUsageProjectID = loadedOpenAIUsageProjectID
        self.draftOpenAIUsageProjectID = loadedOpenAIUsageProjectID
        self.openAIUsageAPIKeyID = loadedOpenAIUsageAPIKeyID
        self.draftOpenAIUsageAPIKeyID = loadedOpenAIUsageAPIKeyID
        self.savedSettings = loadedSettings
        self.savedAPIKey = loadedAPIKey
        self.savedAdminAPIKey = loadedAdminAPIKey
        self.savedOpenAIUsageProjectID = loadedOpenAIUsageProjectID
        self.savedOpenAIUsageAPIKeyID = loadedOpenAIUsageAPIKeyID
        self.appLogs = loadedLogPage.entries
        self.appLogTotalCount = loadedLogPage.totalCount
        self.appLogPage = loadedLogPage.page
        self.isDebuggingEnabled = settingsStore.loadIsDebuggingEnabled()
        self.hasCompletedOnboarding = loadedHasCompletedOnboarding
        self.openAIBillingStatus = loadedOpenAIBillingStatus
        self.openAIUsageStatus = loadedOpenAIUsageStatus
        self.isCloudSyncEnabled = settingsStore.loadIsCloudSyncEnabled()
        self.cloudLastSyncedAt = loadedCloudLastSyncedAt
        self.notificationService = notificationService
        self.cloudSyncService = cloudSyncService
        self.openAIClient = openAIClient ?? OpenAIClient()
        self.hasAPIKeyError = apiKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty

        if !hasCompletedOnboarding {
            log(.info, "첫 실행 온보딩이 필요합니다.")
        } else if hasAPIKeyError {
            log(.warning, "OpenAI API 키가 비어 있습니다.")
        } else {
            log(.info, "앱 상태를 불러왔습니다.")
        }

        restartTimer()
    }

    deinit {
        timerTask?.cancel()
        cloudSyncTask?.cancel()
    }

    func start() async {
        guard !didStart else {
            return
        }

        didStart = true
        guard hasCompletedOnboarding else {
            log(.info, "온보딩 완료 전이라 시작 작업을 대기합니다.")
            return
        }

        if isCloudSyncEnabled {
            await syncCloudNow()
        }

        _ = await notificationService.requestAuthorizationIfNeeded(language: settings.appLanguage)
        await validateAPIKeyOnStartup()
        restartTimer()
    }

    func refreshVisibleData() async {
        guard !isRefreshingVisibleData else {
            return
        }

        isRefreshingVisibleData = true
        defer {
            isRefreshingVisibleData = false
        }

        reloadPersistedState()
        if isCloudSyncEnabled {
            await syncCloudNow()
        } else {
            statusMessage = strings.refreshed
            log(.info, "화면 데이터를 새로고침했습니다.")
        }
    }

    private func reloadPersistedState() {
        let loadedSettings = settingsStore.loadSettings()
        let loadedAPIKey = settingsStore.loadAPIKey()
        let loadedAdminAPIKey = settingsStore.loadAdminAPIKey()
        let loadedOpenAIUsageProjectID = settingsStore.loadOpenAIUsageProjectID()
        let loadedOpenAIUsageAPIKeyID = settingsStore.loadOpenAIUsageAPIKeyID()

        settings = loadedSettings
        currentQuestion = settingsStore.loadQuestion()
        lastAnswer = settingsStore.loadLastAnswer()
        gradingResult = settingsStore.loadGradingResult()
        isRunning = settingsStore.loadIsRunning()
        studyRecords = settingsStore.loadStudyRecords()
        apiKey = loadedAPIKey
        adminAPIKey = loadedAdminAPIKey
        openAIUsageProjectID = loadedOpenAIUsageProjectID
        openAIUsageAPIKeyID = loadedOpenAIUsageAPIKeyID
        savedSettings = loadedSettings
        savedAPIKey = loadedAPIKey.trimmingCharacters(in: .whitespacesAndNewlines)
        savedAdminAPIKey = loadedAdminAPIKey.trimmingCharacters(in: .whitespacesAndNewlines)
        savedOpenAIUsageProjectID = loadedOpenAIUsageProjectID
        savedOpenAIUsageAPIKeyID = loadedOpenAIUsageAPIKeyID
        hasCompletedOnboarding = settingsStore.loadHasCompletedOnboarding()
        openAIBillingStatus = settingsStore.loadOpenAIBillingStatus()
        openAIUsageStatus = settingsStore.loadOpenAIUsageStatus()
        isCloudSyncEnabled = settingsStore.loadIsCloudSyncEnabled()
        cloudLastSyncedAt = settingsStore.loadCloudSyncSnapshotUpdatedAt()
        loadAppLogPage(appLogPage)

        if !isEditingSettings {
            draftSettings = loadedSettings
            draftAPIKey = loadedAPIKey
            draftAdminAPIKey = loadedAdminAPIKey
            draftOpenAIUsageProjectID = loadedOpenAIUsageProjectID
            draftOpenAIUsageAPIKeyID = loadedOpenAIUsageAPIKeyID
        }

        hasAPIKeyError = loadedAPIKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        restartTimer()
    }

    private func validateAPIKeyOnStartup() async {
        let trimmedAPIKey = apiKey.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedAPIKey.isEmpty else {
            hasAPIKeyError = true
            errorMessage = strings.apiKeyEmptyDetailed
            log(.warning, "시작 시 API 키 검증을 건너뛰었습니다. API 키가 비어 있습니다.")
            return
        }

        isValidatingAPIKey = true
        log(.info, "시작 시 OpenAI API 키를 검증합니다.")

        do {
            try await openAIClient.validateAPIKey(trimmedAPIKey)
            hasAPIKeyError = false
            if errorMessage?.contains("API 키") == true {
                errorMessage = nil
            }
            log(.info, "시작 시 OpenAI API 키 검증에 성공했습니다.")
        } catch {
            handleOpenAIError(error)
        }

        isValidatingAPIKey = false
    }

    func beginSettingsEditing() {
        draftSettings = settings
        draftAPIKey = apiKey
        draftAdminAPIKey = adminAPIKey
        draftOpenAIUsageProjectID = openAIUsageProjectID
        draftOpenAIUsageAPIKeyID = openAIUsageAPIKeyID
        isEditingSettings = true
    }

    func cancelSettingsEditing() {
        guard isEditingSettings else {
            return
        }

        draftSettings = settings
        draftAPIKey = apiKey
        draftAdminAPIKey = adminAPIKey
        draftOpenAIUsageProjectID = openAIUsageProjectID
        draftOpenAIUsageAPIKeyID = openAIUsageAPIKeyID
        isEditingSettings = false
    }

    func updateDraftAppLanguage(_ language: AppLanguage) {
        draftSettings.appLanguage = language
        draftSettings.language = language.studyLanguage
    }

    func setDraftNotificationSound(_ sound: NotificationSoundOption, preview: Bool = true) {
        draftSettings.notificationSound = sound

        guard preview else {
            return
        }

        notificationService.playPreview(sound: sound)
        statusMessage = sound == .none
            ? "알림음을 없음으로 설정했습니다."
            : "\(sound.displayName(language: draftSettings.appLanguage)) 알림음을 재생했습니다."
    }

    func saveSettings() {
        persistSettings(
            activeSettingsForEditing,
            apiKey: activeAPIKeyForEditing,
            adminAPIKey: activeAdminAPIKeyForEditing,
            openAIUsageProjectID: activeOpenAIUsageProjectIDForEditing,
            openAIUsageAPIKeyID: activeOpenAIUsageAPIKeyIDForEditing
        )
    }

    func completeOnboarding(settings pendingSettings: StudySettings, apiKey pendingAPIKey: String) async {
        persistSettings(
            pendingSettings,
            apiKey: pendingAPIKey,
            adminAPIKey: adminAPIKey,
            openAIUsageProjectID: openAIUsageProjectID,
            openAIUsageAPIKeyID: openAIUsageAPIKeyID
        )
        settingsStore.saveHasCompletedOnboarding(true)
        hasCompletedOnboarding = true
        selectedTab = .study
        markCloudDataChanged()

        let trimmedAPIKey = pendingAPIKey.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedAPIKey.isEmpty else {
            isRunning = false
            settingsStore.saveIsRunning(false)
            hasAPIKeyError = true
            errorMessage = strings.apiKeyEmptyDetailed
            statusMessage = strings.onboardingCompletedWithoutAPIKey
            log(.warning, "온보딩을 완료했지만 API 키가 비어 있어 타이머를 일시정지했습니다.")
            restartTimer()
            return
        }

        _ = await notificationService.requestAuthorizationIfNeeded(language: settings.appLanguage)
        isValidatingAPIKey = true
        statusMessage = strings.apiKeyCheckingAfterOnboarding
        errorMessage = nil

        do {
            try await openAIClient.validateAPIKey(trimmedAPIKey)
            hasAPIKeyError = false
            statusMessage = strings.onboardingCompleted
            log(.info, "온보딩 완료 후 OpenAI API 키 검증에 성공했습니다.")
        } catch {
            handleOpenAIError(error)
            statusMessage = nil
        }

        isValidatingAPIKey = false
        restartTimer()
    }

    func skipOnboarding() {
        settingsStore.saveHasCompletedOnboarding(true)
        hasCompletedOnboarding = true
        selectedTab = .settings

        if apiKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            isRunning = false
            settingsStore.saveIsRunning(false)
            hasAPIKeyError = true
            errorMessage = strings.apiKeyEmptyDetailed
        }

        statusMessage = strings.onboardingSkipped
        log(.info, "온보딩을 나중에 설정하도록 건너뛰었습니다.")
        markCloudDataChanged()
        restartTimer()
    }

    private func persistSettings(
        _ pendingSettings: StudySettings,
        apiKey pendingAPIKey: String,
        adminAPIKey pendingAdminAPIKey: String,
        openAIUsageProjectID pendingOpenAIUsageProjectID: String,
        openAIUsageAPIKeyID pendingOpenAIUsageAPIKeyID: String
    ) {
        let sanitizedSettings = normalizedSettings(pendingSettings)
        let trimmedAPIKey = pendingAPIKey.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedAdminAPIKey = pendingAdminAPIKey.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedOpenAIUsageProjectID = pendingOpenAIUsageProjectID.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedOpenAIUsageAPIKeyID = pendingOpenAIUsageAPIKeyID.trimmingCharacters(in: .whitespacesAndNewlines)
        let didAPIKeyChange = trimmedAPIKey != savedAPIKey
        let didAdminAPIKeyChange = trimmedAdminAPIKey != savedAdminAPIKey
        let didOpenAIUsageScopeChange = trimmedOpenAIUsageProjectID != savedOpenAIUsageProjectID ||
            trimmedOpenAIUsageAPIKeyID != savedOpenAIUsageAPIKeyID

        settings = sanitizedSettings
        apiKey = pendingAPIKey
        adminAPIKey = pendingAdminAPIKey
        openAIUsageProjectID = trimmedOpenAIUsageProjectID
        openAIUsageAPIKeyID = trimmedOpenAIUsageAPIKeyID
        draftSettings = sanitizedSettings
        draftAPIKey = pendingAPIKey
        draftAdminAPIKey = pendingAdminAPIKey
        draftOpenAIUsageProjectID = trimmedOpenAIUsageProjectID
        draftOpenAIUsageAPIKeyID = trimmedOpenAIUsageAPIKeyID

        settingsStore.saveSettings(sanitizedSettings)
        if didAPIKeyChange {
            settingsStore.saveAPIKey(pendingAPIKey)
        }
        if didAdminAPIKeyChange {
            settingsStore.saveAdminAPIKey(pendingAdminAPIKey)
        }
        if didOpenAIUsageScopeChange {
            settingsStore.saveOpenAIUsageProjectID(trimmedOpenAIUsageProjectID)
            settingsStore.saveOpenAIUsageAPIKeyID(trimmedOpenAIUsageAPIKeyID)
            openAIBillingStatus = nil
            openAIUsageStatus = nil
            settingsStore.saveOpenAIBillingStatus(nil)
            settingsStore.saveOpenAIUsageStatus(nil)
            openAIBillingMessage = strings.openAIUsageScopeChanged
        }
        savedSettings = sanitizedSettings
        savedAPIKey = trimmedAPIKey
        savedAdminAPIKey = trimmedAdminAPIKey
        savedOpenAIUsageProjectID = trimmedOpenAIUsageProjectID
        savedOpenAIUsageAPIKeyID = trimmedOpenAIUsageAPIKeyID
        studyRecords = settingsStore.loadStudyRecords()
        if trimmedAPIKey.isEmpty {
            hasAPIKeyError = true
            errorMessage = strings.apiKeyEmptyDetailed
        } else if didAPIKeyChange || !hasAPIKeyError {
            errorMessage = nil
        }
        statusMessage = "설정을 저장했습니다."
        StudyNotificationDelegate.shared.register(language: sanitizedSettings.appLanguage)
        log(.info, "설정을 저장했습니다. interval=\(sanitizedSettings.sanitizedIntervalMinutes), maxHistory=\(sanitizedSettings.sanitizedMaxHistoryCount)")
        markCloudDataChanged()

        restartTimer()
    }

    func saveSettingsAndValidateAPIKey() async {
        let pendingSettings = activeSettingsForEditing
        let pendingAPIKey = activeAPIKeyForEditing
        let pendingAdminAPIKey = activeAdminAPIKeyForEditing
        let pendingOpenAIUsageProjectID = activeOpenAIUsageProjectIDForEditing
        let pendingOpenAIUsageAPIKeyID = activeOpenAIUsageAPIKeyIDForEditing
        let trimmedAPIKey = pendingAPIKey.trimmingCharacters(in: .whitespacesAndNewlines)
        let didAPIKeyChange = trimmedAPIKey != savedAPIKey

        persistSettings(
            pendingSettings,
            apiKey: pendingAPIKey,
            adminAPIKey: pendingAdminAPIKey,
            openAIUsageProjectID: pendingOpenAIUsageProjectID,
            openAIUsageAPIKeyID: pendingOpenAIUsageAPIKeyID
        )

        guard didAPIKeyChange else {
            log(.info, "API 키 변경사항이 없어 저장 후 검증을 건너뛰었습니다.")
            return
        }

        guard !trimmedAPIKey.isEmpty else {
            hasAPIKeyError = true
            errorMessage = strings.apiKeyEmptyDetailed
            statusMessage = nil
            log(.warning, "API 키가 비어 있어 검증을 건너뛰었습니다.")
            return
        }

        isValidatingAPIKey = true
        statusMessage = "API 키를 확인 중입니다."
        errorMessage = nil

        do {
            try await openAIClient.validateAPIKey(trimmedAPIKey)
            hasAPIKeyError = false
            statusMessage = "설정을 저장했고 API 키도 확인했습니다."
            log(.info, "OpenAI API 키 검증에 성공했습니다.")
        } catch {
            handleOpenAIError(error)
            statusMessage = nil
        }

        isValidatingAPIKey = false
    }

    func setRunning(_ running: Bool) {
        isRunning = running
        settingsStore.saveIsRunning(running)
        statusMessage = running ? "질문 타이머가 실행 중입니다." : "질문 타이머를 일시정지했습니다."
        log(.info, running ? "질문 타이머를 실행했습니다." : "질문 타이머를 중지했습니다.")
        markCloudDataChanged()
        restartTimer()
    }

    func setTimerInterval(_ minutes: Int) {
        settings.intervalMinutes = min(max(minutes, 1), 240)
        settingsStore.saveSettings(settings)
        savedSettings = normalizedSettings(settings)
        studyRecords = settingsStore.loadStudyRecords()
        statusMessage = "질문 간격을 \(settings.intervalMinutes)분으로 설정했습니다."
        log(.info, "질문 간격을 \(settings.intervalMinutes)분으로 변경했습니다.")
        markCloudDataChanged()
        restartTimer()
    }

    func updateAppLanguage(_ language: AppLanguage) {
        settings.appLanguage = language
        settings.language = language.studyLanguage
        StudyNotificationDelegate.shared.register(language: language)
    }

    func setNotificationSound(_ sound: NotificationSoundOption, preview: Bool = true) {
        settings.notificationSound = sound

        guard preview else {
            return
        }

        notificationService.playPreview(sound: sound)
        statusMessage = sound == .none
            ? "알림음을 없음으로 설정했습니다."
            : "\(sound.displayName(language: settings.appLanguage)) 알림음을 재생했습니다."
    }

    func openSystemNotificationSettings() {
        notificationService.openSystemNotificationSettings()
    }

    func setAppLanguage(_ language: AppLanguage) {
        updateAppLanguage(language)
        settingsStore.saveSettings(settings)
        savedSettings = normalizedSettings(settings)
        studyRecords = settingsStore.loadStudyRecords()
        StudyNotificationDelegate.shared.register(language: language)
        statusMessage = language == .korean ? "앱 언어를 한국어로 설정했습니다." : "App language set to English."
        log(.info, "앱 언어를 \(language.rawValue)로 변경했습니다.")
        markCloudDataChanged()
    }

    func generateQuestion(manual: Bool = true) async {
        if !manual && !isRunning {
            log(.info, "타이머가 중지되어 예약 질문 생성을 건너뛰었습니다.")
            return
        }

        guard !isGeneratingQuestion else {
            log(.info, "이미 질문 생성 중이라 새 요청을 무시했습니다.")
            return
        }

        guard !hasReachedPendingQuestionLimit else {
            statusMessage = strings.pendingQuestionLimitTitle
            errorMessage = nil
            log(.warning, "미채점 질문이 3개라 새 질문 생성을 건너뛰었습니다.")
            return
        }

        isGeneratingQuestion = true
        defer {
            isGeneratingQuestion = false
        }
        errorMessage = nil
        statusMessage = manual ? "질문을 생성 중입니다." : "예약된 질문을 생성 중입니다."
        log(.info, "새 질문 생성 요청을 전송합니다. topic=\(settings.topic), difficulty=\(settings.difficulty.level), model=\(settings.sanitizedOpenAIModel)")

        do {
            let question = try await createAndStoreQuestion()
            statusMessage = "새 질문이 준비됐습니다."
            log(.info, "질문을 생성했습니다: \(question.question)")
            let didScheduleNotification = await notificationService.showQuestionNotification(
                question: question,
                title: strings.notificationTitle,
                subtitle: notificationSubtitle,
                sound: settings.notificationSound,
                language: settings.appLanguage
            )
            if !didScheduleNotification {
                statusMessage = strings.testNotificationFailed
                log(.warning, "질문 알림을 표시하지 못했습니다. 알림 권한 또는 시스템 설정을 확인하세요.")
            }
            markCloudDataChanged()
        } catch {
            handleOpenAIError(error)
            statusMessage = nil
            log(.error, "질문 생성에 실패했습니다: \(error.localizedDescription)")
        }
    }

    func sendTestNotification() async {
        let question = QuestionItem(
            question: strings.testNotificationBody,
            expectedAnswerHint: nil,
            createdAt: Date()
        )

        let didSend = await notificationService.showQuestionNotification(
            question: question,
            title: strings.notificationTitle,
            subtitle: strings.notifications,
            sound: settings.notificationSound,
            language: settings.appLanguage
        )

        if didSend {
            statusMessage = strings.testNotificationSent
            log(.info, "테스트 알림을 보냈습니다.")
        } else {
            statusMessage = strings.testNotificationFailed
            log(.warning, "테스트 알림 전송에 실패했습니다. 알림 권한 또는 시스템 설정을 확인하세요.")
        }
    }

    private func createAndStoreQuestion() async throws -> QuestionItem {
        let generated = try await generateUniqueQuestion()
        let question = generated.question

        currentQuestion = question
        gradingResult = nil
        lastAnswer = ""
        settingsStore.saveQuestion(question)
        settingsStore.appendQuestionToHistory(question)
        settingsStore.appendStudyRecord(question: question, settings: settings)
        settingsStore.saveQuestionResponseID(generated.responseID)
        settingsStore.saveGradingResult(nil)
        settingsStore.saveLastAnswer("")
        studyRecords = settingsStore.loadStudyRecords()
        hasAPIKeyError = false

        return question
    }

    private func generateUniqueQuestion() async throws -> GeneratedQuestionResult {
        var recentQuestions = settingsStore.loadQuestionHistory()

        if let currentQuestion {
            recentQuestions.append(currentQuestion)
        }

        for attempt in 0..<2 {
            let generated = try await openAIClient.generateQuestion(
                settings: settings,
                recentQuestions: Array(recentQuestions.suffix(20)),
                previousResponseID: settingsStore.loadQuestionResponseID(),
                apiKey: apiKey
            )

            if !Self.isDuplicate(generated.question, in: recentQuestions) || attempt == 1 {
                return generated
            }

            recentQuestions.append(generated.question)
        }

        return try await openAIClient.generateQuestion(
            settings: settings,
            recentQuestions: Array(recentQuestions.suffix(20)),
            previousResponseID: settingsStore.loadQuestionResponseID(),
            apiKey: apiKey
        )
    }

    private var notificationSubtitle: String {
        let topic = settings.topic.trimmingCharacters(in: .whitespacesAndNewlines)
        let difficulty = settings.difficulty.displayName(language: settings.appLanguage)

        guard !topic.isEmpty else {
            return difficulty
        }

        return "\(topic) · \(difficulty)"
    }

    func gradeCurrentAnswer(answer submittedAnswer: String? = nil) async {
        guard let currentQuestion else {
            errorMessage = "먼저 질문을 생성하세요."
            return
        }

        let answerToGrade = submittedAnswer ?? lastAnswer
        let trimmedAnswer = answerToGrade.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedAnswer.isEmpty else {
            errorMessage = "답변을 입력하세요."
            return
        }

        isGradingAnswer = true
        defer {
            isGradingAnswer = false
        }
        errorMessage = nil
        statusMessage = "답변을 채점 중입니다."
        lastAnswer = answerToGrade
        settingsStore.saveLastAnswer(answerToGrade)
        settingsStore.updateStudyRecordAnswer(question: currentQuestion, answer: answerToGrade, onlyIfUngraded: true)
        studyRecords = settingsStore.loadStudyRecords()
        log(.info, "현재 질문 답변 채점 요청을 전송합니다.")

        do {
            let result = try await openAIClient.gradeAnswer(
                question: currentQuestion,
                answer: trimmedAnswer,
                settings: settings,
                apiKey: apiKey
            )
            gradingResult = result
            settingsStore.saveGradingResult(result)
            settingsStore.saveLastAnswer(trimmedAnswer)
            settingsStore.updateStudyRecord(
                question: currentQuestion,
                answer: trimmedAnswer,
                gradingResult: result
            )
            studyRecords = settingsStore.loadStudyRecords()
            hasAPIKeyError = false
            statusMessage = "채점이 완료됐습니다."
            log(.info, "현재 질문 답변을 채점했습니다. score=\(result.score)")
            markCloudDataChanged()
        } catch {
            handleOpenAIError(error)
            statusMessage = nil
        }
    }

    func gradeRecord(_ record: StudyRecord, answer: String) async {
        let trimmedAnswer = answer.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedAnswer.isEmpty else {
            errorMessage = "답변을 입력하세요."
            return
        }

        isGradingAnswer = true
        defer {
            isGradingAnswer = false
        }
        errorMessage = nil
        statusMessage = "기록의 답변을 채점 중입니다."
        log(.info, "기록 답변 채점 요청을 전송합니다.")

        let gradingSettings = StudySettings(
            topic: record.topic.isEmpty ? settings.topic : record.topic,
            difficulty: record.difficulty,
            appLanguage: settings.appLanguage,
            language: settings.appLanguage.studyLanguage,
            openAIModel: settings.sanitizedOpenAIModel,
            customPrompt: settings.customPrompt,
            intervalMinutes: settings.sanitizedIntervalMinutes,
            maxHistoryCount: settings.sanitizedMaxHistoryCount
        )

        do {
            let result = try await openAIClient.gradeAnswer(
                question: record.question,
                answer: trimmedAnswer,
                settings: gradingSettings,
                apiKey: apiKey
            )

            currentQuestion = record.question
            lastAnswer = trimmedAnswer
            gradingResult = result
            settingsStore.saveQuestion(record.question)
            settingsStore.saveLastAnswer(trimmedAnswer)
            settingsStore.saveGradingResult(result)
            settingsStore.updateStudyRecord(
                question: record.question,
                answer: trimmedAnswer,
                gradingResult: result
            )
            studyRecords = settingsStore.loadStudyRecords()
            hasAPIKeyError = false
            statusMessage = "채점이 완료됐습니다."
            log(.info, "기록 답변을 채점했습니다. score=\(result.score)")
            markCloudDataChanged()
        } catch {
            handleOpenAIError(error)
            statusMessage = nil
        }
    }

    func skipCurrentQuestion() {
        guard let currentQuestion else {
            return
        }

        let skippedRecord = studyRecord(matching: currentQuestion)
        if let skippedRecord, skippedRecord.gradingResult == nil {
            settingsStore.deleteStudyRecord(skippedRecord)
        }

        studyRecords = settingsStore.loadStudyRecords()

        if let nextRecord = pendingStudyRecords.first {
            self.currentQuestion = nextRecord.question
            lastAnswer = nextRecord.answer ?? ""
            gradingResult = nil
            settingsStore.saveQuestion(nextRecord.question)
            settingsStore.saveLastAnswer(nextRecord.answer ?? "")
            settingsStore.saveGradingResult(nil)
            statusMessage = "질문을 넘기고 다음 미제출 질문을 열었습니다."
        } else {
            self.currentQuestion = nil
            lastAnswer = ""
            gradingResult = nil
            settingsStore.saveQuestion(nil)
            settingsStore.saveLastAnswer("")
            settingsStore.saveGradingResult(nil)
            statusMessage = "질문을 넘겼습니다."
        }

        errorMessage = nil
        log(.info, "현재 미제출 질문을 넘겼습니다.")
        markCloudDataChanged()
    }

    func openOldestPendingQuestion() {
        guard let record = pendingStudyRecords.last else {
            return
        }

        selectStudyRecord(record)
        statusMessage = "가장 오래된 미제출 질문을 열었습니다."
        log(.info, "가장 오래된 미제출 질문을 열었습니다.")
    }

    func copyToClipboard(_ text: String, message: String? = nil) {
        let trimmedText = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedText.isEmpty else {
            return
        }

        #if os(macOS)
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(trimmedText, forType: .string)
        #elseif os(iOS)
        UIPasteboard.general.string = trimmedText
        #endif
        statusMessage = message ?? strings.copiedToClipboard
        log(.info, "텍스트를 클립보드에 복사했습니다.")
    }

    func updateAnswer(_ answer: String) {
        lastAnswer = answer
        settingsStore.saveLastAnswer(answer)
        if let currentQuestion {
            settingsStore.updateStudyRecordAnswer(question: currentQuestion, answer: answer, onlyIfUngraded: true)
            studyRecords = settingsStore.loadStudyRecords()
            markCloudDataChanged(syncDelaySeconds: 4)
        }
    }

    func selectStudyRecord(_ record: StudyRecord) {
        currentQuestion = record.question
        lastAnswer = record.answer ?? ""
        gradingResult = record.gradingResult
        settingsStore.saveQuestion(record.question)
        settingsStore.saveLastAnswer(record.answer ?? "")
        settingsStore.saveGradingResult(record.gradingResult)
        selectedTab = .study
        focusedRecordRequest = nil
        statusMessage = record.gradingResult == nil ? "미제출 질문을 열었습니다." : "학습 기록을 열었습니다."
        markCloudDataChanged(syncDelaySeconds: 4)
    }

    func openRecordFromNotification(questionCreatedAt: TimeInterval?, replyText: String? = nil) {
        studyRecords = settingsStore.loadStudyRecords()

        let record = recordMatching(questionCreatedAt: questionCreatedAt) ?? studyRecords.last
        guard let record else {
            selectedTab = .study
            statusMessage = "알림에서 열린 질문입니다."
            return
        }

        let trimmedReply = replyText?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        if !trimmedReply.isEmpty {
            settingsStore.updateStudyRecordAnswer(question: record.question, answer: trimmedReply)
        }

        studyRecords = settingsStore.loadStudyRecords()
        let refreshedRecord = recordMatching(questionCreatedAt: questionCreatedAt) ??
            studyRecords.first { $0.id == record.id } ??
            record
        selectStudyRecord(refreshedRecord)
        statusMessage = trimmedReply.isEmpty ? "알림에서 열린 질문입니다." : "알림 답장을 기록에 저장했습니다."
        markCloudDataChanged()
    }

    func clearStatus() {
        statusMessage = nil
        errorMessage = nil
    }

    func clearStudyRecords() {
        settingsStore.clearStudyRecords()
        studyRecords = []
        statusMessage = "학습 기록을 삭제했습니다."
        log(.warning, "학습 기록을 모두 삭제했습니다.")
        markCloudDataChanged()
    }

    func deleteStudyRecord(_ record: StudyRecord) {
        settingsStore.deleteStudyRecord(record)
        studyRecords = settingsStore.loadStudyRecords()

        if SettingsStore.normalizedQuestionText(currentQuestion?.question ?? "") ==
            SettingsStore.normalizedQuestionText(record.question.question) {
            currentQuestion = nil
            gradingResult = nil
            lastAnswer = ""
            settingsStore.saveQuestion(nil)
            settingsStore.saveGradingResult(nil)
            settingsStore.saveLastAnswer("")
        }

        statusMessage = "기록을 삭제했습니다."
        log(.info, "학습 기록을 1개 삭제했습니다.")
        markCloudDataChanged()
    }

    func clearAppLogs() {
        settingsStore.clearAppLogs()
        appLogs = []
        appLogTotalCount = 0
        appLogPage = 0
    }

    func loadAppLogPage(_ page: Int) {
        let logPage = settingsStore.loadAppLogs(page: page, pageSize: Self.developerLogPageSize)
        appLogs = logPage.entries
        appLogTotalCount = logPage.totalCount
        appLogPage = logPage.page
    }

    func setDebuggingEnabled(_ isEnabled: Bool) {
        isDebuggingEnabled = isEnabled
        settingsStore.saveIsDebuggingEnabled(isEnabled)
        log(.info, isEnabled ? "디버깅 모드를 켰습니다." : "디버깅 모드를 껐습니다.")
    }

    func setCloudSyncEnabled(_ isEnabled: Bool) {
        isCloudSyncEnabled = isEnabled
        settingsStore.saveIsCloudSyncEnabled(isEnabled)
        cloudSyncMessage = isEnabled ? strings.iCloudSyncOn : strings.iCloudSyncOff
        hasCloudSyncError = false

        guard isEnabled else {
            cloudSyncTask?.cancel()
            return
        }

        Task {
            await syncCloudNow()
        }
    }

    func syncCloudNow() async {
        guard isCloudSyncEnabled else {
            return
        }

        guard !isCloudSyncing else {
            cloudSyncMessage = strings.syncAlreadyInProgress
            return
        }

        guard cloudSyncService != nil || CloudSyncService.canUseCloudKitContainer() else {
            cloudSyncMessage = strings.syncEntitlementMissing
            hasCloudSyncError = true
            log(.error, "이 앱 빌드에 iCloud CloudKit entitlement가 없어 동기화할 수 없습니다.")
            return
        }

        let cloudSyncService = resolvedCloudSyncService()
        guard let cloudSyncService else {
            cloudSyncMessage = strings.syncUnavailable
            hasCloudSyncError = true
            log(.warning, cloudSyncMessage ?? "iCloud 동기화를 사용할 수 없습니다.")
            return
        }

        isCloudSyncing = true
        defer {
            isCloudSyncing = false
        }

        do {
            let storedLocalUpdatedAt = settingsStore.loadCloudSyncSnapshotUpdatedAt()
            let localUpdatedAt = storedLocalUpdatedAt ?? .distantPast
            let fetchedRemoteSnapshot = try await cloudSyncService.fetchSnapshot()

            if let fetchedRemoteSnapshot {
                let apiKeyMerge = remoteSnapshotByFillingMissingAPIKey(fetchedRemoteSnapshot)
                let remoteSnapshot = apiKeyMerge.snapshot
                if storedLocalUpdatedAt == nil {
                    let firstSync = firstSyncSnapshot(from: remoteSnapshot)
                    applyCloudSnapshot(firstSync.snapshot)

                    if firstSync.shouldPushMergedSnapshot {
                        try await cloudSyncService.saveSnapshot(firstSync.snapshot)
                        settingsStore.saveCloudSyncSnapshotUpdatedAt(firstSync.snapshot.updatedAt)
                        cloudLastSyncedAt = firstSync.snapshot.updatedAt
                        cloudSyncMessage = strings.syncMergedRemote
                        log(.info, "iCloud 데이터를 불러오고 이 기기의 기록을 병합했습니다.")
                    } else {
                        cloudSyncMessage = strings.syncPulledRemote
                        log(.info, "첫 iCloud 동기화에서 원격 학습 데이터를 불러왔습니다.")
                    }
                } else if remoteSnapshot.updatedAt > localUpdatedAt {
                    applyCloudSnapshot(remoteSnapshot)
                    if apiKeyMerge.shouldPush {
                        try await cloudSyncService.saveSnapshot(remoteSnapshot)
                        settingsStore.saveCloudSyncSnapshotUpdatedAt(remoteSnapshot.updatedAt)
                        cloudLastSyncedAt = remoteSnapshot.updatedAt
                        cloudSyncMessage = strings.syncMergedRemote
                        log(.info, "iCloud 최신 데이터에 이 기기의 OpenAI API 키를 병합했습니다.")
                    } else {
                        cloudSyncMessage = strings.syncPulledRemote
                        log(.info, "iCloud에서 최신 학습 데이터를 불러왔습니다.")
                    }
                } else {
                    let updatedAt = max(localUpdatedAt, Date())
                    let snapshot = outgoingSnapshotPreservingRemoteAPIKey(
                        makeCloudSnapshot(updatedAt: updatedAt),
                        remoteSnapshot: remoteSnapshot
                    )
                    try await cloudSyncService.saveSnapshot(snapshot)
                    settingsStore.saveCloudSyncSnapshotUpdatedAt(snapshot.updatedAt)
                    cloudLastSyncedAt = snapshot.updatedAt
                    cloudSyncMessage = strings.syncPushedLocal
                    log(.info, "학습 데이터를 iCloud에 저장했습니다.")
                }
            } else {
                let updatedAt = max(localUpdatedAt, Date())
                let snapshot = makeCloudSnapshot(updatedAt: updatedAt)
                try await cloudSyncService.saveSnapshot(snapshot)
                settingsStore.saveCloudSyncSnapshotUpdatedAt(snapshot.updatedAt)
                cloudLastSyncedAt = snapshot.updatedAt
                cloudSyncMessage = strings.syncPushedLocal
                log(.info, "학습 데이터를 iCloud에 저장했습니다.")
            }

            hasCloudSyncError = false
        } catch {
            cloudSyncMessage = cloudSyncFailureMessage(for: error)
            hasCloudSyncError = true
            settingsStore.saveIsCloudSyncEnabled(isCloudSyncEnabled)
            log(.warning, cloudSyncMessage ?? "iCloud 동기화에 실패했습니다.")
        }
    }

    func refreshOpenAIBillingStatus() async {
        let trimmedAdminAPIKey = adminAPIKey.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedAdminAPIKey.isEmpty else {
            openAIBillingMessage = strings.openAIAdminKeyEmptyDetailed
            return
        }

        let projectID = Self.trimmedOptional(openAIUsageProjectID)
        let apiKeyID = Self.trimmedOptional(openAIUsageAPIKeyID)
        isRefreshingBillingStatus = true
        openAIBillingMessage = nil

        do {
            let status = try await openAIClient.fetchBillingStatus(
                adminAPIKey: trimmedAdminAPIKey,
                projectID: projectID,
                apiKeyID: apiKeyID
            )
            let organizationWideStatus = try await organizationWideBillingStatusIfUseful(
                adminAPIKey: trimmedAdminAPIKey,
                filteredStatus: status,
                projectID: projectID,
                apiKeyID: apiKeyID
            )
            let usageStatus = try await openAIClient.fetchUsageStatus(
                adminAPIKey: trimmedAdminAPIKey,
                projectID: projectID,
                apiKeyID: apiKeyID
            )
            openAIBillingStatus = status
            openAIUsageStatus = usageStatus
            settingsStore.saveOpenAIBillingStatus(status)
            settingsStore.saveOpenAIUsageStatus(usageStatus)
            if let organizationWideStatus {
                openAIBillingMessage = strings.openAIBillingProjectZeroButOrganizationHasCost(
                    organizationWideStatus.formattedSpentAmount
                )
            } else {
                openAIBillingMessage = strings.openAIBillingUpdated
            }
            log(
                .info,
                "OpenAI 사용량/비용 정보를 업데이트했습니다. scope=\(openAIUsageScopeDescription(strings: strings)), amount=\(status.spentAmount), currency=\(status.currency), organizationAmount=\(organizationWideStatus?.spentAmount.description ?? "n/a"), billingPages=\(status.sourcePageCount ?? 1), billingBuckets=\(status.sourceBucketCount ?? 0), billingResults=\(status.sourceResultCount ?? 0), usagePages=\(usageStatus.sourcePageCount ?? 1), usageBuckets=\(usageStatus.sourceBucketCount ?? 0), usageResults=\(usageStatus.sourceResultCount ?? 0), requests=\(usageStatus.requestCount), tokens=\(usageStatus.totalTokens)"
            )
        } catch {
            let message: String
            if case OpenAIClientError.httpError(let status, _) = error,
               status == 401 || status == 403 {
                message = billingPermissionMessage(for: error)
            } else {
                message = strings.openAIBillingFetchFailed(error.localizedDescription)
            }
            openAIBillingMessage = message
            log(.warning, message)
        }

        isRefreshingBillingStatus = false
    }

    private func organizationWideBillingStatusIfUseful(
        adminAPIKey: String,
        filteredStatus: OpenAIBillingStatus,
        projectID: String?,
        apiKeyID: String?
    ) async throws -> OpenAIBillingStatus? {
        guard (projectID != nil || apiKeyID != nil), filteredStatus.spentAmount <= 0 else {
            return nil
        }

        let organizationWideStatus = try await openAIClient.fetchBillingStatus(
            adminAPIKey: adminAPIKey,
            projectID: nil,
            apiKeyID: nil
        )

        return organizationWideStatus.spentAmount > 0 ? organizationWideStatus : nil
    }

    func openAIUsageScopeDescription(strings: AppStrings) -> String {
        let projectID = Self.trimmedOptional(openAIUsageProjectID)
        let apiKeyID = Self.trimmedOptional(openAIUsageAPIKeyID)

        switch (projectID, apiKeyID) {
        case (.some, .some):
            return strings.openAIUsageScopeProjectAndAPIKey
        case (.some, .none):
            return strings.openAIUsageScopeProject
        case (.none, .some):
            return strings.openAIUsageScopeAPIKey
        case (.none, .none):
            return strings.openAIUsageScopeOrganization
        }
    }

    func openOpenAIBillingPage() {
        openURLString("https://platform.openai.com/settings/organization/billing/overview")
    }

    func openOpenAIUsageDashboardPage() {
        openURLString("https://platform.openai.com/usage")
    }

    func openOpenAICreditGrantsPage() {
        openURLString("https://platform.openai.com/settings/organization/billing/credit-grants")
    }

    func openOpenAIAdminKeysPage() {
        openURLString("https://platform.openai.com/settings/organization/admin-keys")
    }

    func uninstallApplication() {
        #if os(macOS)
        let appURL = Bundle.main.bundleURL

        do {
            try launchUninstaller(for: appURL)
            log(.warning, "앱 제거를 실행했습니다.")
            NSApp.terminate(nil)
        } catch {
            errorMessage = strings.uninstallFailed(error.localizedDescription)
            log(.error, "앱 제거 실패: \(error.localizedDescription)")
        }
        #else
        errorMessage = strings.uninstallFailed("iOS")
        #endif
    }

    #if os(macOS)
    private func launchUninstaller(for appURL: URL) throws {
        let scriptURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("studymate-uninstall-\(UUID().uuidString).sh")
        let script = Self.makeUninstallScript(appPath: appURL.path)

        try script.write(to: scriptURL, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: scriptURL.path)

        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/sh")
        process.arguments = [
            "-c",
            "nohup /bin/sh \(Self.shellEscaped(scriptURL.path)) >/dev/null 2>&1 &"
        ]
        try process.run()
        process.waitUntilExit()

        if process.terminationStatus != 0 {
            throw CocoaError(.executableLoad)
        }
    }
    #endif

    nonisolated static func makeUninstallScript(appPath: String) -> String {
        let escapedAppPath = shellEscaped(appPath)
        let escapedHomeApplicationsPath = shellEscaped("~/Applications/StudyMate.app")

        return """
        #!/bin/sh
        set +e

        APP_PATH=\(escapedAppPath)
        LOG_PATH="${TMPDIR:-/tmp}/studymate-uninstall.log"

        echo "StudyMate uninstall started at $(date)" > "${LOG_PATH}"

        /usr/bin/osascript -e 'tell application id "io.github.ghkdqhrbals.StudyMate" to quit' >> "${LOG_PATH}" 2>&1
        /usr/bin/osascript -e 'tell application "StudyMate" to quit' >> "${LOG_PATH}" 2>&1

        ATTEMPT=0
        while /usr/bin/pgrep -x "StudyMate" >/dev/null 2>&1 && [ "${ATTEMPT}" -lt 30 ]; do
          /bin/sleep 0.2
          ATTEMPT=$((ATTEMPT + 1))
        done

        /usr/bin/pkill -x "StudyMate" >> "${LOG_PATH}" 2>&1
        /bin/sleep 0.5

        remove_path() {
          TARGET_PATH="$1"
          EXPANDED_PATH="$(eval printf '%s' "${TARGET_PATH}")"

          [ -e "${EXPANDED_PATH}" ] || return 0
          echo "Removing ${EXPANDED_PATH}" >> "${LOG_PATH}"

          TRASH_TARGET="${HOME}/.Trash/$(basename "${EXPANDED_PATH}")-$(date +%Y%m%d%H%M%S)"
          /bin/mv "${EXPANDED_PATH}" "${TRASH_TARGET}" >> "${LOG_PATH}" 2>&1
          [ ! -e "${EXPANDED_PATH}" ] && return 0

          /bin/rm -rf "${EXPANDED_PATH}" >> "${LOG_PATH}" 2>&1
          [ ! -e "${EXPANDED_PATH}" ] && return 0

          ESCAPED_TARGET="$(printf "%s" "${EXPANDED_PATH}" | /usr/bin/sed "s/'/'\\\\''/g")"
          /usr/bin/osascript -e "do shell script \\"/bin/rm -rf '${ESCAPED_TARGET}'\\" with administrator privileges" >> "${LOG_PATH}" 2>&1
          [ ! -e "${EXPANDED_PATH}" ] && return 0

          echo "Failed to remove ${EXPANDED_PATH}" >> "${LOG_PATH}"
        }

        remove_path "${APP_PATH}"
        remove_path "/Applications/StudyMate.app"
        remove_path \(escapedHomeApplicationsPath)

        remove_data() {
          BUNDLE_ID="$1"
          /usr/bin/defaults delete "${BUNDLE_ID}" >> "${LOG_PATH}" 2>&1
          /bin/rm -f "${HOME}/Library/Preferences/${BUNDLE_ID}.plist"
          /bin/rm -rf "${HOME}/Library/Application Support/${BUNDLE_ID}"
          /bin/rm -rf "${HOME}/Library/Caches/${BUNDLE_ID}"
          /bin/rm -rf "${HOME}/Library/Caches/Sparkle/${BUNDLE_ID}"
          /bin/rm -rf "${HOME}/Library/Logs/${BUNDLE_ID}"
          /bin/rm -rf "${HOME}/Library/Saved Application State/${BUNDLE_ID}.savedState"
        }

        remove_data "io.github.ghkdqhrbals.StudyMate"
        remove_data "com.local.StudyMate"

        /usr/bin/osascript -e 'display dialog "사용해주셔서 감사합니다." with title "StudyMate" buttons {"확인"} default button "확인" giving up after 8' >> "${LOG_PATH}" 2>&1
        echo "StudyMate uninstall finished at $(date)" >> "${LOG_PATH}"
        /bin/rm -f "$0"
        """
    }

    nonisolated private static func shellEscaped(_ value: String) -> String {
        "'\(value.replacingOccurrences(of: "'", with: "'\\''"))'"
    }

    nonisolated private static func appleScriptEscaped(_ value: String) -> String {
        value
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"")
    }

    private func restartTimer() {
        timerTask?.cancel()
        guard hasCompletedOnboarding, isRunning else {
            return
        }

        let interval = settings.sanitizedIntervalMinutes

        timerTask = Task { [weak self] in
            while !Task.isCancelled {
                let seconds = UInt64(interval * 60)
                try? await Task.sleep(nanoseconds: seconds * 1_000_000_000)

                guard !Task.isCancelled else {
                    return
                }

                await self?.generateQuestion(manual: false)
            }
        }
    }

    private func markCloudDataChanged(syncDelaySeconds: UInt64 = 2) {
        guard isCloudSyncEnabled else {
            return
        }

        let updatedAt = Date()
        settingsStore.saveCloudSyncSnapshotUpdatedAt(updatedAt)
        cloudLastSyncedAt = updatedAt
        scheduleCloudSync(delaySeconds: syncDelaySeconds)
    }

    private func scheduleCloudSync(delaySeconds: UInt64 = 2) {
        guard isCloudSyncEnabled else {
            return
        }

        cloudSyncTask?.cancel()
        cloudSyncTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: delaySeconds * 1_000_000_000)
            guard !Task.isCancelled else {
                return
            }

            await self?.syncCloudNow()
        }
    }

    private func makeCloudSnapshot(updatedAt: Date) -> CloudSyncSnapshot {
        CloudSyncSnapshot(
            updatedAt: updatedAt,
            apiKey: Self.trimmedOptional(apiKey),
            settings: normalizedSettings(settings),
            currentQuestion: currentQuestion,
            questionHistory: settingsStore.loadQuestionHistory(),
            lastAnswer: lastAnswer,
            gradingResult: gradingResult,
            isRunning: isRunning,
            hasCompletedOnboarding: hasCompletedOnboarding,
            studyRecords: studyRecords
        )
    }

    private func remoteSnapshotByFillingMissingAPIKey(_ snapshot: CloudSyncSnapshot) -> (snapshot: CloudSyncSnapshot, shouldPush: Bool) {
        guard Self.trimmedOptional(snapshot.apiKey ?? "") == nil,
              let localAPIKey = Self.trimmedOptional(apiKey) else {
            return (snapshot, false)
        }

        var mergedSnapshot = snapshot
        mergedSnapshot.apiKey = localAPIKey
        mergedSnapshot.updatedAt = max(snapshot.updatedAt, Date())
        return (mergedSnapshot, true)
    }

    private func outgoingSnapshotPreservingRemoteAPIKey(
        _ snapshot: CloudSyncSnapshot,
        remoteSnapshot: CloudSyncSnapshot
    ) -> CloudSyncSnapshot {
        guard Self.trimmedOptional(snapshot.apiKey ?? "") == nil,
              let remoteAPIKey = Self.trimmedOptional(remoteSnapshot.apiKey ?? "") else {
            return snapshot
        }

        var mergedSnapshot = snapshot
        mergedSnapshot.apiKey = remoteAPIKey
        apiKey = remoteAPIKey
        draftAPIKey = remoteAPIKey
        savedAPIKey = remoteAPIKey
        settingsStore.saveAPIKey(remoteAPIKey)
        hasAPIKeyError = false
        if errorMessage == strings.apiKeyEmptyDetailed || errorMessage == strings.apiKeyInvalidDetailed {
            errorMessage = nil
        }
        log(.info, "iCloud 원격 OpenAI API 키를 보존해 로컬 변경사항과 함께 저장합니다.")
        return mergedSnapshot
    }

    private func firstSyncSnapshot(from remoteSnapshot: CloudSyncSnapshot) -> (snapshot: CloudSyncSnapshot, shouldPushMergedSnapshot: Bool) {
        guard hasMeaningfulLocalCloudData else {
            return (remoteSnapshot, false)
        }

        var mergedSnapshot = remoteSnapshot
        mergedSnapshot.updatedAt = Date()
        if Self.trimmedOptional(mergedSnapshot.apiKey ?? "") == nil {
            mergedSnapshot.apiKey = Self.trimmedOptional(apiKey)
        }
        mergedSnapshot.hasCompletedOnboarding = remoteSnapshot.hasCompletedOnboarding || hasCompletedOnboarding
        mergedSnapshot.studyRecords = mergedStudyRecords(
            remote: remoteSnapshot.studyRecords,
            local: studyRecords,
            maxCount: max(
                remoteSnapshot.settings.sanitizedMaxHistoryCount,
                settings.sanitizedMaxHistoryCount
            )
        )
        mergedSnapshot.questionHistory = mergedQuestionHistory(
            remote: remoteSnapshot.questionHistory,
            local: settingsStore.loadQuestionHistory()
        )

        if mergedSnapshot.currentQuestion == nil {
            mergedSnapshot.currentQuestion = currentQuestion
        }
        if mergedSnapshot.lastAnswer.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            mergedSnapshot.lastAnswer = lastAnswer
        }
        if mergedSnapshot.gradingResult == nil {
            mergedSnapshot.gradingResult = gradingResult
        }

        return (mergedSnapshot, true)
    }

    private var hasMeaningfulLocalCloudData: Bool {
        !studyRecords.isEmpty ||
            !settingsStore.loadQuestionHistory().isEmpty ||
            currentQuestion != nil ||
            !lastAnswer.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ||
            gradingResult != nil ||
            !apiKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ||
            normalizedSettings(settings) != .default
    }

    private func mergedStudyRecords(
        remote remoteRecords: [StudyRecord],
        local localRecords: [StudyRecord],
        maxCount: Int
    ) -> [StudyRecord] {
        var recordsByKey: [String: StudyRecord] = [:]

        for record in remoteRecords + localRecords {
            let key = studyRecordMergeKey(record)
            if let existingRecord = recordsByKey[key] {
                recordsByKey[key] = preferredStudyRecord(existingRecord, record)
            } else {
                recordsByKey[key] = record
            }
        }

        let sortedRecords = recordsByKey.values.sorted {
            studyRecordSortDate($0) < studyRecordSortDate($1)
        }
        return Array(sortedRecords.suffix(max(10, maxCount)))
    }

    private func mergedQuestionHistory(remote: [QuestionItem], local: [QuestionItem]) -> [QuestionItem] {
        var questionsByKey: [String: QuestionItem] = [:]

        for question in remote + local {
            let key = SettingsStore.normalizedQuestionText(question.question)
            if let existingQuestion = questionsByKey[key] {
                questionsByKey[key] = question.createdAt >= existingQuestion.createdAt ? question : existingQuestion
            } else {
                questionsByKey[key] = question
            }
        }

        let sortedQuestions = questionsByKey.values.sorted {
            $0.createdAt < $1.createdAt
        }
        return Array(sortedQuestions.suffix(20))
    }

    private func studyRecordMergeKey(_ record: StudyRecord) -> String {
        [
            record.topic.trimmingCharacters(in: .whitespacesAndNewlines).lowercased(),
            String(record.difficulty.level),
            SettingsStore.normalizedQuestionText(record.question.question)
        ].joined(separator: "|")
    }

    private func preferredStudyRecord(_ existingRecord: StudyRecord, _ candidateRecord: StudyRecord) -> StudyRecord {
        if existingRecord.gradingResult == nil && candidateRecord.gradingResult != nil {
            return candidateRecord
        }
        if (existingRecord.answer ?? "").trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
           !(candidateRecord.answer ?? "").trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return candidateRecord
        }

        return studyRecordSortDate(candidateRecord) >= studyRecordSortDate(existingRecord)
            ? candidateRecord
            : existingRecord
    }

    private func studyRecordSortDate(_ record: StudyRecord) -> Date {
        record.answeredAt ?? record.question.createdAt
    }

    private func cloudSyncFailureMessage(for error: Error) -> String {
        switch CloudSyncErrorClassifier.kind(for: error) {
        case .quotaExceeded:
            return strings.syncQuotaExceeded
        case .notAuthenticated:
            return strings.syncNotAuthenticated
        case .permissionDenied:
            return strings.syncPermissionDenied
        case .network:
            return strings.syncNetworkUnavailable
        case .serviceUnavailable, .unavailable:
            return strings.syncServiceUnavailable
        case .rateLimited:
            return strings.syncRateLimited
        case .limitExceeded:
            return strings.syncLimitExceeded
        case .conflict:
            return strings.syncConflictRetry
        case .unknown:
            return strings.syncFailed(error.localizedDescription)
        }
    }

    private func applyCloudSnapshot(_ snapshot: CloudSyncSnapshot) {
        let preservedCloudSyncEnabled = isCloudSyncEnabled
        let sanitizedSettings = normalizedSettings(snapshot.settings)
        let mergedHasCompletedOnboarding = hasCompletedOnboarding || snapshot.hasCompletedOnboarding
        let syncedAPIKey = Self.trimmedOptional(snapshot.apiKey ?? "")

        settings = sanitizedSettings
        draftSettings = sanitizedSettings
        if let syncedAPIKey {
            apiKey = syncedAPIKey
            draftAPIKey = syncedAPIKey
            savedAPIKey = syncedAPIKey
            settingsStore.saveAPIKey(syncedAPIKey)
            hasAPIKeyError = false
            if errorMessage == strings.apiKeyEmptyDetailed || errorMessage == strings.apiKeyInvalidDetailed {
                errorMessage = nil
            }
            log(.info, "iCloud에서 OpenAI API 키를 불러왔습니다.")
        }
        currentQuestion = snapshot.currentQuestion
        lastAnswer = snapshot.lastAnswer
        gradingResult = snapshot.gradingResult
        isRunning = snapshot.isRunning
        hasCompletedOnboarding = mergedHasCompletedOnboarding
        isCloudSyncEnabled = preservedCloudSyncEnabled

        settingsStore.saveSettings(sanitizedSettings)
        settingsStore.saveQuestion(snapshot.currentQuestion)
        settingsStore.saveQuestionHistory(snapshot.questionHistory)
        settingsStore.saveLastAnswer(snapshot.lastAnswer)
        settingsStore.saveGradingResult(snapshot.gradingResult)
        settingsStore.saveIsRunning(snapshot.isRunning)
        settingsStore.saveHasCompletedOnboarding(mergedHasCompletedOnboarding)
        settingsStore.saveIsCloudSyncEnabled(preservedCloudSyncEnabled)
        settingsStore.replaceStudyRecords(snapshot.studyRecords)
        settingsStore.saveCloudSyncSnapshotUpdatedAt(snapshot.updatedAt)

        studyRecords = settingsStore.loadStudyRecords()
        savedSettings = sanitizedSettings
        cloudLastSyncedAt = snapshot.updatedAt
        restartTimer()
    }

    private func resolvedCloudSyncService() -> CloudSyncServiceProtocol? {
        if cloudSyncService == nil {
            guard CloudSyncService.canUseCloudKitContainer() else {
                return nil
            }

            cloudSyncService = CloudSyncService()
        }

        return cloudSyncService
    }

    nonisolated private static func isDuplicate(_ question: QuestionItem, in recentQuestions: [QuestionItem]) -> Bool {
        let normalizedQuestion = SettingsStore.normalizedQuestionText(question.question)
        return recentQuestions.contains {
            SettingsStore.normalizedQuestionText($0.question) == normalizedQuestion
        }
    }

    private func handleOpenAIError(_ error: Error) {
        if Self.isAPIKeyError(error) {
            hasAPIKeyError = true
            errorMessage = apiKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                ? strings.apiKeyEmptyDetailed
                : strings.apiKeyInvalidDetailed
            log(.error, errorMessage ?? "OpenAI API 키 오류가 발생했습니다.")
        } else {
            hasAPIKeyError = true
            errorMessage = error.localizedDescription
            log(.error, error.localizedDescription)
        }
    }

    private func log(_ level: LogLevel, _ message: String) {
        let entry = AppLogEntry(level: level, message: message)
        settingsStore.appendAppLog(entry)
        loadAppLogPage(0)
    }

    private func openURLString(_ urlString: String) {
        guard let url = URL(string: urlString) else {
            return
        }

        #if os(macOS)
        NSWorkspace.shared.open(url)
        #elseif os(iOS)
        UIApplication.shared.open(url)
        #endif
    }

    private func billingPermissionMessage(for error: Error) -> String {
        guard case OpenAIClientError.httpError(_, let body) = error else {
            return strings.openAIBillingNeedsPermission
        }

        let lowercasedBody = body.lowercased()
        if lowercasedBody.contains("api.usage.read") {
            return strings.openAIUsageScopeMissing
        }

        return strings.openAIBillingNeedsPermission
    }

    private func normalizedSettings(_ settings: StudySettings) -> StudySettings {
        StudySettings(
            topic: settings.topic,
            difficulty: settings.difficulty,
            appLanguage: settings.appLanguage,
            language: settings.appLanguage.studyLanguage,
            openAIModel: settings.sanitizedOpenAIModel,
            notificationSound: settings.notificationSound,
            customPrompt: settings.customPrompt,
            intervalMinutes: settings.sanitizedIntervalMinutes,
            maxHistoryCount: settings.sanitizedMaxHistoryCount
        )
    }

    private func recordMatching(questionCreatedAt: TimeInterval?) -> StudyRecord? {
        guard let questionCreatedAt else {
            return nil
        }

        return studyRecords.last {
            abs($0.question.createdAt.timeIntervalSince1970 - questionCreatedAt) < 0.001
        }
    }

    private func studyRecord(matching question: QuestionItem?) -> StudyRecord? {
        guard let question else {
            return nil
        }

        let normalizedQuestion = SettingsStore.normalizedQuestionText(question.question)
        return studyRecords.last {
            $0.question.createdAt == question.createdAt ||
                SettingsStore.normalizedQuestionText($0.question.question) == normalizedQuestion
        }
    }

    nonisolated private static func isAPIKeyError(_ error: Error) -> Bool {
        if let clientError = error as? OpenAIClientError {
            switch clientError {
            case .missingAPIKey:
                return true
            case .httpError(let status, let body):
                let lowercasedBody = body.lowercased()
                return status == 401 ||
                    status == 403 ||
                    lowercasedBody.contains("invalid api key") ||
                    lowercasedBody.contains("incorrect api key") ||
                    lowercasedBody.contains("unauthorized")
            default:
                return false
            }
        }

        return false
    }

    nonisolated private static func trimmedOptional(_ value: String) -> String? {
        let trimmedValue = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmedValue.isEmpty ? nil : trimmedValue
    }
}
