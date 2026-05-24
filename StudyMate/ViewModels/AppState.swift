import AppKit
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
    @Published var selectedTab: AppTab = .study
    @Published var focusedRecordRequest: FocusedRecordRequest?

    private let settingsStore: SettingsStore
    private let openAIClient: OpenAIClientProtocol
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

    init(
        settingsStore: SettingsStore = SettingsStore(),
        openAIClient: OpenAIClientProtocol? = nil,
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
        let trimmedAPIKey = apiKey.trimmingCharacters(in: .whitespacesAndNewlines)
        let didAPIKeyChange = trimmedAPIKey != savedAPIKey

        settings.language = settings.appLanguage.studyLanguage
        settings.openAIModel = settings.sanitizedOpenAIModel
        settings.intervalMinutes = settings.sanitizedIntervalMinutes
        settings.maxHistoryCount = settings.sanitizedMaxHistoryCount
        settingsStore.saveSettings(settings)
        if didAPIKeyChange {
            settingsStore.saveAPIKey(apiKey)
        }
        savedSettings = normalizedSettings(settings)
        savedAPIKey = trimmedAPIKey
        studyRecords = settingsStore.loadStudyRecords()
        if trimmedAPIKey.isEmpty {
            hasAPIKeyError = true
            errorMessage = strings.apiKeyEmptyDetailed
        } else if didAPIKeyChange || !hasAPIKeyError {
            errorMessage = nil
        }
        statusMessage = "설정을 저장했습니다."
        log(.info, "설정을 저장했습니다. interval=\(settings.sanitizedIntervalMinutes), maxHistory=\(settings.sanitizedMaxHistoryCount)")

        restartTimer()
    }

    func saveSettingsAndValidateAPIKey() async {
        let trimmedAPIKey = apiKey.trimmingCharacters(in: .whitespacesAndNewlines)
        let didAPIKeyChange = trimmedAPIKey != savedAPIKey

        saveSettings()

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
                subtitle: notificationSubtitle,
                sound: settings.notificationSound,
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

    private var notificationSubtitle: String {
        let topic = settings.topic.trimmingCharacters(in: .whitespacesAndNewlines)
        let difficulty = settings.difficulty.displayName(language: settings.appLanguage)

        guard !topic.isEmpty else {
            return difficulty
        }

        return "\(topic) · \(difficulty)"
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
        } catch {
            handleOpenAIError(error)
            statusMessage = nil
        }

        isGradingAnswer = false
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

        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(trimmedText, forType: .string)
        statusMessage = message ?? strings.copiedToClipboard
        log(.info, "텍스트를 클립보드에 복사했습니다.")
    }

    func updateAnswer(_ answer: String) {
        lastAnswer = answer
        settingsStore.saveLastAnswer(answer)
        if let currentQuestion {
            settingsStore.updateStudyRecordAnswer(question: currentQuestion, answer: answer, onlyIfUngraded: true)
            studyRecords = settingsStore.loadStudyRecords()
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

    func uninstallApplication() {
        let appURL = Bundle.main.bundleURL

        do {
            try launchUninstaller(for: appURL)
            log(.warning, "앱 제거를 실행했습니다.")
            NSApp.terminate(nil)
        } catch {
            errorMessage = strings.uninstallFailed(error.localizedDescription)
            log(.error, "앱 제거 실패: \(error.localizedDescription)")
        }
    }

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
}
