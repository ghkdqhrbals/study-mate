import Foundation

@MainActor
final class AppState: ObservableObject {
    @Published var settings: StudySettings
    @Published var currentQuestion: QuestionItem?
    @Published var lastAnswer: String
    @Published var gradingResult: GradingResult?
    @Published var apiKey: String = ""
    @Published var isGeneratingQuestion = false
    @Published var isGradingAnswer = false
    @Published var isRunning: Bool
    @Published var studyRecords: [StudyRecord]
    @Published var hasAPIKeyError = false
    @Published var isValidatingAPIKey = false
    @Published var appLogs: [AppLogEntry]
    @Published var isDebuggingEnabled: Bool
    @Published var statusMessage: String?
    @Published var errorMessage: String?

    private let settingsStore: SettingsStore
    private let openAIClient: OpenAIClient
    private let notificationService: NotificationService
    private var timerTask: Task<Void, Never>?
    private var didStart = false
    private var savedSettings: StudySettings
    private var savedAPIKey: String

    var strings: AppStrings {
        AppStrings(language: settings.appLanguage)
    }

    var statusTitle: String {
        strings.statusTitle(isRunning: isRunning)
    }

    var hasUnsavedSettingsChanges: Bool {
        normalizedSettings(settings) != savedSettings ||
            apiKey.trimmingCharacters(in: .whitespacesAndNewlines) != savedAPIKey
    }

    var apiKeyValidationMessage: String? {
        guard hasAPIKeyError else {
            return nil
        }

        if apiKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return strings.apiKeyEmpty
        }

        return errorMessage ?? strings.apiKeyCheck
    }

    var pendingQuestionCount: Int {
        studyRecords.filter { $0.gradingResult == nil }.count
    }

    init(
        settingsStore: SettingsStore = SettingsStore(),
        openAIClient: OpenAIClient? = nil,
        notificationService: NotificationService = NotificationService()
    ) {
        let loadedSettings = settingsStore.loadSettings()
        let loadedAPIKey = settingsStore.loadAPIKey()

        self.settingsStore = settingsStore
        self.settings = loadedSettings
        self.currentQuestion = settingsStore.loadQuestion()
        self.lastAnswer = settingsStore.loadLastAnswer()
        self.gradingResult = settingsStore.loadGradingResult()
        self.isRunning = settingsStore.loadIsRunning()
        self.studyRecords = settingsStore.loadStudyRecords()
        self.apiKey = loadedAPIKey
        self.savedSettings = loadedSettings
        self.savedAPIKey = loadedAPIKey
        self.appLogs = settingsStore.loadAppLogs()
        self.isDebuggingEnabled = settingsStore.loadIsDebuggingEnabled()
        self.notificationService = notificationService
        self.openAIClient = openAIClient ?? OpenAIClient()
        self.hasAPIKeyError = apiKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty

        if hasAPIKeyError {
            log(.warning, "OpenAI API 키가 비어 있습니다.")
        } else {
            log(.info, "앱 상태를 불러왔습니다.")
        }

        restartTimer()
    }

    deinit {
        timerTask?.cancel()
    }

    func start() async {
        guard !didStart else {
            return
        }

        didStart = true
        _ = await notificationService.requestAuthorizationIfNeeded(language: settings.appLanguage)
        await validateAPIKeyOnStartup()
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

    func saveSettings() {
        settings.intervalMinutes = settings.sanitizedIntervalMinutes
        settings.maxHistoryCount = settings.sanitizedMaxHistoryCount
        settingsStore.saveSettings(settings)
        settingsStore.saveAPIKey(apiKey)
        savedSettings = normalizedSettings(settings)
        savedAPIKey = apiKey.trimmingCharacters(in: .whitespacesAndNewlines)
        studyRecords = settingsStore.loadStudyRecords()
        if apiKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            hasAPIKeyError = true
        }
        errorMessage = hasAPIKeyError ? strings.apiKeyEmptyDetailed : nil
        statusMessage = "설정을 저장했습니다."
        log(.info, "설정을 저장했습니다. interval=\(settings.sanitizedIntervalMinutes), maxHistory=\(settings.sanitizedMaxHistoryCount)")

        restartTimer()
    }

    func saveSettingsAndValidateAPIKey() async {
        saveSettings()

        isValidatingAPIKey = true
        statusMessage = "API 키를 확인 중입니다."
        errorMessage = nil

        do {
            try await openAIClient.validateAPIKey(apiKey)
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
        restartTimer()
    }

    func setTimerInterval(_ minutes: Int) {
        settings.intervalMinutes = min(max(minutes, 1), 240)
        settingsStore.saveSettings(settings)
        savedSettings = normalizedSettings(settings)
        studyRecords = settingsStore.loadStudyRecords()
        statusMessage = "질문 간격을 \(settings.intervalMinutes)분으로 설정했습니다."
        log(.info, "질문 간격을 \(settings.intervalMinutes)분으로 변경했습니다.")
        restartTimer()
    }

    func setAppLanguage(_ language: AppLanguage) {
        settings.appLanguage = language
        settingsStore.saveSettings(settings)
        savedSettings = normalizedSettings(settings)
        studyRecords = settingsStore.loadStudyRecords()
        StudyNotificationDelegate.shared.register(language: language)
        statusMessage = language == .korean ? "앱 언어를 한국어로 설정했습니다." : "App language set to English."
        log(.info, "앱 언어를 \(language.rawValue)로 변경했습니다.")
    }

    func generateQuestion(manual: Bool = true) async {
        if !manual && !isRunning {
            return
        }

        guard !isGeneratingQuestion else {
            return
        }

        guard pendingQuestionCount < 3 else {
            statusMessage = "미채점 질문이 3개 쌓여 있어 새 질문을 만들지 않습니다."
            errorMessage = nil
            log(.warning, "미채점 질문이 3개라 새 질문 생성을 건너뛰었습니다.")
            return
        }

        isGeneratingQuestion = true
        errorMessage = nil
        statusMessage = manual ? "질문을 생성 중입니다." : "예약된 질문을 생성 중입니다."

        do {
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
            statusMessage = "새 질문이 준비됐습니다."
            log(.info, "질문을 생성했습니다: \(question.question)")
            await notificationService.showQuestionNotification(
                question: question,
                title: strings.notificationTitle,
                language: settings.appLanguage
            )
        } catch {
            handleOpenAIError(error)
            statusMessage = nil
        }

        isGeneratingQuestion = false
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

    func gradeCurrentAnswer() async {
        guard let currentQuestion else {
            errorMessage = "먼저 질문을 생성하세요."
            return
        }

        let trimmedAnswer = lastAnswer.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedAnswer.isEmpty else {
            errorMessage = "답변을 입력하세요."
            return
        }

        isGradingAnswer = true
        errorMessage = nil
        statusMessage = "답변을 채점 중입니다."

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
        } catch {
            handleOpenAIError(error)
            statusMessage = nil
        }

        isGradingAnswer = false
    }

    func gradeRecord(_ record: StudyRecord, answer: String) async {
        let trimmedAnswer = answer.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedAnswer.isEmpty else {
            errorMessage = "답변을 입력하세요."
            return
        }

        isGradingAnswer = true
        errorMessage = nil
        statusMessage = "기록의 답변을 채점 중입니다."

        let gradingSettings = StudySettings(
            topic: record.topic.isEmpty ? settings.topic : record.topic,
            difficulty: record.difficulty,
            appLanguage: settings.appLanguage,
            language: settings.language,
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
        } catch {
            handleOpenAIError(error)
            statusMessage = nil
        }

        isGradingAnswer = false
    }

    func updateAnswer(_ answer: String) {
        lastAnswer = answer
        settingsStore.saveLastAnswer(answer)
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
    }

    func clearAppLogs() {
        settingsStore.clearAppLogs()
        appLogs = []
        log(.info, "로그를 초기화했습니다.")
    }

    func setDebuggingEnabled(_ isEnabled: Bool) {
        isDebuggingEnabled = isEnabled
        settingsStore.saveIsDebuggingEnabled(isEnabled)
        log(.info, isEnabled ? "디버깅 모드를 켰습니다." : "디버깅 모드를 껐습니다.")
    }

    private func restartTimer() {
        timerTask?.cancel()
        guard isRunning else {
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
        appLogs = settingsStore.loadAppLogs()
    }

    private func normalizedSettings(_ settings: StudySettings) -> StudySettings {
        StudySettings(
            topic: settings.topic,
            difficulty: settings.difficulty,
            appLanguage: settings.appLanguage,
            language: settings.language,
            customPrompt: settings.customPrompt,
            intervalMinutes: settings.sanitizedIntervalMinutes,
            maxHistoryCount: settings.sanitizedMaxHistoryCount
        )
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
}
