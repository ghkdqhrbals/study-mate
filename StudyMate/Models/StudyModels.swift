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

struct StudySettings: Codable, Equatable {
    var topic: String
    var difficulty: Difficulty
    var customPrompt: String
    var intervalMinutes: Int
    var maxHistoryCount: Int

    init(
        topic: String,
        difficulty: Difficulty,
        customPrompt: String,
        intervalMinutes: Int,
        maxHistoryCount: Int = 100
    ) {
        self.topic = topic
        self.difficulty = difficulty
        self.customPrompt = customPrompt
        self.intervalMinutes = intervalMinutes
        self.maxHistoryCount = maxHistoryCount
    }

    private enum CodingKeys: String, CodingKey {
        case topic
        case difficulty
        case customPrompt
        case intervalMinutes
        case maxHistoryCount
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        topic = try container.decode(String.self, forKey: .topic)
        difficulty = try container.decode(Difficulty.self, forKey: .difficulty)
        customPrompt = try container.decode(String.self, forKey: .customPrompt)
        intervalMinutes = try container.decode(Int.self, forKey: .intervalMinutes)
        maxHistoryCount = try container.decodeIfPresent(Int.self, forKey: .maxHistoryCount) ?? 100
    }

    static let `default` = StudySettings(
        topic: "Swift",
        difficulty: .beginner,
        customPrompt: "짧고 명확한 한국어로 질문하세요. 사용자가 답하기 좋은 한 문제만 내세요.",
        intervalMinutes: 15
    )

    var sanitizedIntervalMinutes: Int {
        min(max(intervalMinutes, 1), 240)
    }

    var sanitizedMaxHistoryCount: Int {
        min(max(maxHistoryCount, 10), 500)
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
