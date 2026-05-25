import Foundation

enum Difficulty: String, CaseIterable, Codable, Identifiable {
    case novice
    case beginner
    case elementary
    case intermediate
    case upperIntermediate
    case advanced
    case expert

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .novice:
            "완전 입문"
        case .beginner:
            "입문"
        case .elementary:
            "초급"
        case .intermediate:
            "중급"
        case .upperIntermediate:
            "중상급"
        case .advanced:
            "고급"
        case .expert:
            "전문가"
        }
    }

    var promptLabel: String {
        switch self {
        case .novice:
            "absolute beginner"
        case .beginner:
            "beginner"
        case .elementary:
            "elementary"
        case .intermediate:
            "intermediate"
        case .upperIntermediate:
            "upper-intermediate"
        case .advanced:
            "advanced"
        case .expert:
            "expert"
        }
    }
}

enum StudyLanguage: String, CaseIterable, Codable, Identifiable {
    case korean
    case english

    var id: String { rawValue }

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        let rawValue = try container.decode(String.self)
        self = StudyLanguage(rawValue: rawValue) ?? .korean
    }

    var displayName: String {
        switch self {
        case .korean:
            "한국어"
        case .english:
            "English"
        }
    }

    var promptLabel: String {
        switch self {
        case .korean:
            "Korean"
        case .english:
            "English"
        }
    }
}

enum AppLanguage: String, CaseIterable, Codable, Identifiable {
    case korean
    case english

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .korean:
            "한국어"
        case .english:
            "English"
        }
    }
}

enum NotificationSoundOption: String, CaseIterable, Codable, Identifiable {
    case defaultSound
    case softPing
    case chime
    case pop
    case bell
    case tap
    case none

    var id: String { rawValue }

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        let rawValue = try container.decode(String.self)
        self = NotificationSoundOption(rawValue: rawValue) ?? .defaultSound
    }

    var bundledFileName: String? {
        switch self {
        case .defaultSound, .none:
            nil
        case .softPing:
            "study_ping.wav"
        case .chime:
            "study_chime.wav"
        case .pop:
            "study_pop.wav"
        case .bell:
            "study_bell.wav"
        case .tap:
            "study_tap.wav"
        }
    }

    func displayName(language: AppLanguage) -> String {
        switch (self, language) {
        case (.defaultSound, .korean):
            "기본음"
        case (.defaultSound, .english):
            "Default"
        case (.softPing, .korean):
            "부드러운 핑"
        case (.softPing, .english):
            "Soft Ping"
        case (.chime, .korean):
            "차임"
        case (.chime, .english):
            "Chime"
        case (.pop, .korean):
            "팝"
        case (.pop, .english):
            "Pop"
        case (.bell, .korean):
            "벨"
        case (.bell, .english):
            "Bell"
        case (.tap, .korean):
            "탭"
        case (.tap, .english):
            "Tap"
        case (.none, .korean):
            "없음"
        case (.none, .english):
            "None"
        }
    }
}

enum AppTab: Int, Hashable {
    case study
    case settings
    case records
    case statistics
}

struct FocusedRecordRequest: Equatable {
    var token = UUID()
    var recordID: String
}

extension AppLanguage {
    var studyLanguage: StudyLanguage {
        switch self {
        case .korean:
            .korean
        case .english:
            .english
        }
    }
}

struct StudySettings: Codable, Equatable {
    static let defaultOpenAIModel = "gpt-5.4"

    var topic: String
    var difficulty: Difficulty
    var appLanguage: AppLanguage
    var language: StudyLanguage
    var openAIModel: String
    var notificationSound: NotificationSoundOption
    var customPrompt: String
    var intervalMinutes: Int
    var maxHistoryCount: Int

    init(
        topic: String,
        difficulty: Difficulty,
        appLanguage: AppLanguage = .korean,
        language: StudyLanguage = .korean,
        openAIModel: String = StudySettings.defaultOpenAIModel,
        notificationSound: NotificationSoundOption = .defaultSound,
        customPrompt: String,
        intervalMinutes: Int,
        maxHistoryCount: Int = 100
    ) {
        self.topic = topic
        self.difficulty = difficulty
        self.appLanguage = appLanguage
        self.language = language
        self.openAIModel = openAIModel
        self.notificationSound = notificationSound
        self.customPrompt = customPrompt
        self.intervalMinutes = intervalMinutes
        self.maxHistoryCount = maxHistoryCount
    }

    private enum CodingKeys: String, CodingKey {
        case topic
        case difficulty
        case appLanguage
        case language
        case openAIModel
        case notificationSound
        case customPrompt
        case intervalMinutes
        case maxHistoryCount
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        topic = try container.decode(String.self, forKey: .topic)
        difficulty = try container.decode(Difficulty.self, forKey: .difficulty)
        appLanguage = try container.decodeIfPresent(AppLanguage.self, forKey: .appLanguage) ?? .korean
        language = try container.decodeIfPresent(StudyLanguage.self, forKey: .language) ?? .korean
        openAIModel = try container.decodeIfPresent(String.self, forKey: .openAIModel) ?? Self.defaultOpenAIModel
        notificationSound = try container.decodeIfPresent(NotificationSoundOption.self, forKey: .notificationSound) ?? .defaultSound
        customPrompt = try container.decode(String.self, forKey: .customPrompt)
        intervalMinutes = try container.decode(Int.self, forKey: .intervalMinutes)
        maxHistoryCount = try container.decodeIfPresent(Int.self, forKey: .maxHistoryCount) ?? 100
    }

    static let `default` = StudySettings(
        topic: "Swift",
        difficulty: .beginner,
        customPrompt: "짧고 명확하게 질문하세요. 사용자가 답하기 좋은 한 문제만 내세요.",
        intervalMinutes: 15
    )

    var sanitizedIntervalMinutes: Int {
        min(max(intervalMinutes, 1), 240)
    }

    var sanitizedMaxHistoryCount: Int {
        min(max(maxHistoryCount, 10), 500)
    }

    var sanitizedOpenAIModel: String {
        let trimmedModel = openAIModel.trimmingCharacters(in: .whitespacesAndNewlines)
        guard OpenAIModelOption.supportedIDs.contains(trimmedModel) else {
            return Self.defaultOpenAIModel
        }

        return trimmedModel
    }
}

struct OpenAIModelOption: Identifiable, Equatable {
    var id: String
    var displayName: String
    var supportsTextVerbosity: Bool

    static let all: [OpenAIModelOption] = [
        OpenAIModelOption(id: "gpt-5.4", displayName: "GPT-5.4", supportsTextVerbosity: true)
    ]

    static var supportedIDs: Set<String> {
        Set(all.map(\.id))
    }

    static func supportsTextVerbosity(modelID: String) -> Bool {
        all.first { $0.id == modelID }?.supportsTextVerbosity ?? false
    }
}

struct QuestionItem: Codable, Equatable {
    var question: String
    var expectedAnswerHint: String?
    var createdAt: Date
}

struct GradingResult: Codable, Equatable {
    var score: Int
    var isCorrect: Bool
    var feedback: String
    var explanation: String
}

struct StudyRecord: Codable, Equatable, Identifiable {
    var id: String
    var question: QuestionItem
    var answer: String?
    var gradingResult: GradingResult?
    var topic: String
    var difficulty: Difficulty
    var answeredAt: Date?

    init(
        id: String = UUID().uuidString,
        question: QuestionItem,
        answer: String? = nil,
        gradingResult: GradingResult? = nil,
        topic: String,
        difficulty: Difficulty,
        answeredAt: Date? = nil
    ) {
        self.id = id
        self.question = question
        self.answer = answer
        self.gradingResult = gradingResult
        self.topic = topic
        self.difficulty = difficulty
        self.answeredAt = answeredAt
    }
}

struct AppLogEntry: Codable, Equatable, Identifiable {
    var id: String
    var createdAt: Date
    var level: LogLevel
    var message: String

    init(
        id: String = UUID().uuidString,
        createdAt: Date = Date(),
        level: LogLevel,
        message: String
    ) {
        self.id = id
        self.createdAt = createdAt
        self.level = level
        self.message = message
    }
}

enum LogLevel: String, Codable, CaseIterable {
    case info
    case warning
    case error

    var displayName: String {
        switch self {
        case .info:
            "Info"
        case .warning:
            "Warning"
        case .error:
            "Error"
        }
    }
}

extension Difficulty {
    func displayName(language: AppLanguage) -> String {
        switch language {
        case .korean:
            return displayName
        case .english:
            switch self {
            case .novice:
                return "Novice"
            case .beginner:
                return "Beginner"
            case .elementary:
                return "Elementary"
            case .intermediate:
                return "Intermediate"
            case .upperIntermediate:
                return "Upper Intermediate"
            case .advanced:
                return "Advanced"
            case .expert:
                return "Expert"
            }
        }
    }
}

struct AppStrings {
    var language: AppLanguage

    private var isKorean: Bool {
        language == .korean
    }

    private func text(_ korean: String, _ english: String) -> String {
        isKorean ? korean : english
    }

    var tabStudy: String { text("학습", "Study") }
    var tabSettings: String { text("설정", "Settings") }
    var tabRecords: String { text("기록", "Records") }
    var tabStatistics: String { text("통계", "Stats") }

    func statusTitle(isRunning: Bool) -> String {
        if isRunning {
            return text("StudyMate 실행 중", "StudyMate is running")
        }
        return text("StudyMate 정지됨", "StudyMate is stopped")
    }

    var invalidAPIKey: String { text("API 키가 잘못되었습니다", "Invalid API key") }
    var notificationTitle: String { "StudyMate" }
    var reply: String { text("답장", "Reply") }
    var send: String { text("보내기", "Send") }
    var answerPlaceholder: String { text("답변 입력", "Enter answer") }
    var otherAnswer: String { text("다른 응답", "Other Answer") }
    var ignore: String { text("무시", "Ignore") }
    var openStudy: String { text("학습 열기...", "Open Study...") }
    var aboutStudyMate: String { text("StudyMate 정보", "About StudyMate") }
    func timerTitle(minutes: Int) -> String { text("타이머: \(minutes)분", "Timer: \(minutes) min") }
    func minuteLabel(_ minutes: Int) -> String { text("\(minutes)분", "\(minutes) min") }
    var languageMenu: String { text("언어", "Language") }
    var pause: String { text("일시정지", "Pause") }
    var resume: String { text("재개", "Resume") }
    var quit: String { text("StudyMate 종료", "Quit StudyMate") }

    var general: String { "General" }
    var secrets: String { "Secrets" }
    var study: String { "Study" }
    var records: String { "Records" }
    var developer: String { "Developer" }

    var checking: String { text("확인 중", "Checking") }
    var save: String { text("저장", "Save") }
    var saved: String { text("저장됨", "Saved") }
    var apiKey: String { text("API 키", "API key") }
    var hide: String { text("숨기기", "Hide") }
    var show: String { text("보기", "Show") }
    var apiKeyEmpty: String { text("API 키를 입력하세요.", "Enter an API key.") }
    var apiKeyCheck: String { text("API 키를 확인하세요.", "Check the API key.") }
    var apiKeyEmptyDetailed: String { text("API 키가 비어 있습니다. Settings > Secrets에서 OpenAI API 키를 입력하세요.", "API key is empty. Enter an OpenAI API key in Settings > Secrets.") }
    var apiKeyInvalidDetailed: String { text("API 키가 잘못되었습니다. Settings > Secrets에서 OpenAI API 키를 확인하세요.", "API key is invalid. Check your OpenAI API key in Settings > Secrets.") }
    var openAIModel: String { text("모델", "Model") }
    var openAIModelHelp: String {
        text("질문 생성과 채점에 사용할 OpenAI 모델입니다.", "OpenAI model for question generation and grading.")
    }
    var unsavedAPIKeyHelp: String {
        text("변경사항이 있습니다. 저장해도 API 키 검증 실패 시 값은 유지됩니다.", "You have unsaved changes. Values are kept even if API key validation fails.")
    }
    var apiKeyStorageHelp: String { text("API 키는 앱 설정에 저장됩니다.", "The API key is stored in app settings.") }

    var generalSettings: String { text("일반", "General") }
    var appLanguageHelp: String { text("언어를 바꾸면 학습 언어도 같은 언어로 설정됩니다.", "Changing Language also sets the study language to match.") }
    var notifications: String { text("알림", "Notifications") }
    var notificationPermissionHelp: String {
        text("macOS 설정에서 StudyMate 알림과 사운드 허용 여부를 직접 확인하세요.", "Check StudyMate notification and sound permissions directly in macOS Settings.")
    }
    var openNotificationSettings: String { text("시스템 알림 설정 열기", "Open Notification Settings") }
    var notificationSound: String { text("알림음", "Notification sound") }
    var notificationSoundHelp: String { text("질문 알림을 받을 때 소리를 낼지 선택합니다.", "Choose whether question notifications play a sound.") }
    var updates: String { text("업데이트", "Updates") }
    var automaticallyCheckForUpdates: String { text("자동으로 업데이트 확인", "Automatically check for updates") }
    var automaticallyDownloadUpdates: String { text("가능하면 자동으로 다운로드", "Automatically download updates when available") }
    var checkForUpdates: String { text("업데이트 확인...", "Check for Updates...") }
    var updateHelp: String {
        text("GitHub Releases에 새 DMG가 올라오면 StudyMate가 업데이트를 안내합니다.", "StudyMate checks GitHub Releases and offers updates when a new DMG is available.")
    }
    var updateInstallHelp: String {
        text(
            "DMG 안이나 임시 위치에서 실행 중이면 업데이트할 수 없습니다. StudyMate.app을 Applications 폴더로 옮긴 뒤 다시 실행하세요.",
            "Updates are unavailable when StudyMate is running from a DMG or temporary location. Move StudyMate.app to Applications and relaunch it."
        )
    }
    var uninstall: String { text("StudyMate 제거", "Uninstall StudyMate") }
    var uninstallHelp: String {
        text("앱을 휴지통으로 이동하고 로컬 설정과 캐시를 삭제합니다.", "Move the app to Trash and delete local settings and caches.")
    }
    var uninstallConfirmationTitle: String { text("StudyMate를 제거할까요?", "Uninstall StudyMate?") }
    var uninstallConfirmationMessage: String {
        text("앱, 로컬 설정, 캐시가 삭제되고 StudyMate가 종료됩니다.", "The app, local settings, and caches will be deleted, then StudyMate will quit.")
    }
    func uninstallFailed(_ reason: String) -> String {
        text("앱 제거 실패: \(reason)", "Uninstall failed: \(reason)")
    }
    var studySettings: String { text("학습 설정", "Study Settings") }
    var appLanguage: String { text("언어", "Language") }
    var studyTopic: String { text("공부할 주제", "Study topic") }
    var difficulty: String { text("난이도", "Difficulty") }
    func questionInterval(minutes: Int) -> String { text("질문 간격: \(minutes)분", "Question interval: \(minutes) min") }
    var recommendedPrompt: String { text("추천 프롬프트", "Recommended Prompt") }
    var relatedPrompt: String { text("관련 프롬프트", "Prompt") }

    var maxRecordCount: String { text("기록 최대 개수", "Max records") }
    var countUnit: String { text("개", "") }
    func recordLimitHelp(limit: Int, count: Int) -> String {
        text("저장 시 \(limit)개 범위로 정리됩니다. 현재 저장된 기록: \(count)개", "Records are trimmed to \(limit) on save. Current records: \(count)")
    }
    var deleteRecords: String { text("기록 전체삭제", "Delete All Records") }
    var deleteRecordsHelp: String { text("저장된 질문, 답변, 채점 기록을 모두 삭제합니다.", "Delete all saved questions, answers, and grading results.") }
    var debuggingMode: String { text("디버깅 모드", "Debugging Mode") }
    var debuggingHelp: String { text("켜면 왼쪽 메뉴에 Developer 탭이 표시되고 앱 로그를 확인할 수 있습니다.", "When enabled, the Developer tab appears in the left menu with app logs.") }
    var developerOptions: String { text("개발자 옵션", "Developer Options") }
    var apiStatus: String { text("API 상태", "API Status") }
    var apiKeyErrorDetected: String { text("API 키 오류가 감지됐습니다.", "An API key error was detected.") }
    var apiKeyNoError: String { text("API 키 오류가 없습니다.", "No API key error.") }
    var logs: String { text("로그", "Logs") }
    var deleteLogs: String { text("로그 삭제", "Delete Logs") }
    var logLimitHelp: String { text("최근 로그는 최대 1000개까지만 보관됩니다. 초과하면 오래된 로그부터 자동 삭제됩니다.", "Only the latest 1000 logs are kept. Older logs are deleted automatically.") }
    var noLogs: String { text("로그 없음", "No Logs") }
    var noLogsDescription: String { text("앱 이벤트와 오류가 여기에 표시됩니다.", "App events and errors appear here.") }

    var newQuestion: String { text("새 질문", "New Question") }
    var studyOverview: String { text("학습 현황", "Study Overview") }
    var pendingShort: String { text("대기", "Pending") }
    var latestScoreShort: String { text("최근 점수", "Latest") }
    var averageScoreShort: String { text("평균", "Average") }
    var noScoreShort: String { text("-", "-") }
    var draftSaved: String { text("초안 자동 저장됨", "Draft auto-saved") }
    var clearAnswer: String { text("답변 지우기", "Clear Answer") }
    var continueOldestPending: String { text("오래된 질문 이어하기", "Continue Oldest") }
    var copyQuestion: String { text("질문 복사", "Copy Question") }
    var copyAnswer: String { text("답변 복사", "Copy Answer") }
    var copiedToClipboard: String { text("클립보드에 복사했습니다.", "Copied to clipboard.") }
    var pendingQuestions: String { text("미제출 질문", "Pending Questions") }
    func pendingQuestionCount(_ count: Int) -> String { text("\(count)개 대기 중", "\(count) pending") }
    var pendingQuestionLimitTitle: String { text("미채점 질문이 3개입니다.", "There are 3 ungraded questions.") }
    var pendingQuestionLimitMessage: String {
        text(
            "미채점 질문을 답변하거나 넘기기/기록 삭제로 제거한 뒤 다시 새 질문 생성을 실행하세요.",
            "Answer, skip, or delete an ungraded question, then run New Question again."
        )
    }
    var current: String { text("현재", "Current") }
    var openPendingQuestion: String { text("답변하기", "Answer") }
    var question: String { text("질문", "Question") }
    var noQuestion: String { text("질문 없음", "No Question") }
    var noQuestionDescription: String { text("설정을 저장한 뒤 새 질문을 생성하세요.", "Save settings, then create a new question.") }
    var answer: String { text("답변", "Answer") }
    var gradeAnswer: String { text("채점 받기", "Grade Answer") }
    var skipQuestion: String { text("넘기기", "Skip") }
    var skipQuestionHelp: String { text("현재 미제출 질문을 넘기고 대기 중인 다음 질문으로 이동합니다.", "Skip the current ungraded question and move to the next pending one.") }
    var showHint: String { text("힌트 보기", "Show Hint") }
    var hideHint: String { text("힌트 숨기기", "Hide Hint") }
    var correct: String { text("정답", "Correct") }
    var nearlyCorrect: String { text("정답에 가까움", "Nearly Correct") }
    var partialCorrect: String { text("부분 정답", "Partially Correct") }
    var needsImprovement: String { text("보완 필요", "Needs Work") }

    var clear: String { text("삭제", "Delete") }
    var searchRecords: String { text("기록 검색", "Search records") }
    var recordFilterAll: String { text("전체", "All") }
    var recordFilterGraded: String { text("채점됨", "Graded") }
    var recordFilterUngraded: String { text("미채점", "Ungraded") }
    func filteredRecordCount(_ shown: Int, total: Int) -> String {
        text("\(shown)/\(total)개 표시", "\(shown)/\(total) shown")
    }
    var noSearchResults: String { text("검색 결과 없음", "No Results") }
    var noSearchResultsDescription: String { text("다른 검색어로 기록을 찾아보세요.", "Try another search term.") }
    var noRecords: String { text("기록 없음", "No Records") }
    var noRecordsDescription: String { text("질문을 생성하고 답변을 채점하면 기록이 쌓입니다.", "Records appear after you create questions and grade answers.") }
    var deleteRecordHelp: String { text("기록 삭제", "Delete Record") }
    var studyFallback: String { text("학습", "Study") }
    var ungraded: String { text("미채점", "Ungraded") }
    func answerPrefix(_ answer: String) -> String { text("답변: \(answer)", "Answer: \(answer)") }

    var stats: String { text("통계", "Stats") }
    var noScores: String { text("점수 없음", "No Scores") }
    var noScoresDescription: String { text("답변을 채점하면 점수 그래프가 표시됩니다.", "A score graph appears after you grade answers.") }
    var noScoresInPeriod: String { text("선택한 기간에 점수 없음", "No Scores in This Period") }
    var noScoresInPeriodDescription: String {
        text("기간을 넓히거나 새 답변을 채점하면 통계가 표시됩니다.", "Widen the period or grade a new answer to show stats.")
    }
    var responses: String { text("응답", "Responses") }
    var average: String { text("평균", "Avg") }
    var best: String { text("최고", "Best") }
    var lowest: String { text("최저", "Low") }
    var latestScore: String { text("최근", "Latest") }
    var trend: String { text("변화", "Trend") }
    var period: String { text("기간", "Period") }
    var firstRecord: String { text("처음", "First") }
    var latestRecord: String { text("최근", "Latest") }
    var startDate: String { text("시작", "Start") }
    var endDate: String { text("끝", "End") }
    var allPeriods: String { text("전체", "All") }
    var today: String { text("오늘", "Today") }
    var last7Days: String { text("최근 7일", "Last 7 Days") }
    var last30Days: String { text("최근 30일", "Last 30 Days") }
    var last90Days: String { text("최근 90일", "Last 90 Days") }
    var customPeriod: String { text("직접 설정", "Custom") }
    var scoreByQuestion: String { text("문제별 점수", "Scores by Question") }
    var scoreDistribution: String { text("점수 분포", "Score Distribution") }
    var excellentScores: String { text("90-100", "90-100") }
    var goodScores: String { text("70-89", "70-89") }
    var partialScores: String { text("40-69", "40-69") }
    var lowScores: String { text("0-39", "0-39") }
    var problem: String { text("문제", "Question") }
    var hint: String { text("힌트", "Hint") }
    var feedback: String { text("피드백", "Feedback") }
    var explanation: String { text("해설", "Explanation") }
    var statsByDifficulty: String { text("난이도별 통계", "Stats by Difficulty") }
    var statsByTopic: String { text("주제별 통계", "Stats by Topic") }
    var insight: String { text("인사이트", "Insight") }
    var strongestTopic: String { text("강점 주제", "Strong Topic") }
    var weakestTopic: String { text("보완 주제", "Focus Topic") }
    var notEnoughStats: String { text("통계를 만들려면 채점 기록이 더 필요합니다.", "Grade more answers to build insights.") }
    func itemCount(_ count: Int) -> String { text("\(count)개", "\(count)") }
    var correctRate: String { text("정답", "Correct") }
}
