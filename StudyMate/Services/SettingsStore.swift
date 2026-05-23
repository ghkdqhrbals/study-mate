import Foundation

final class SettingsStore {
    private enum Keys {
        static let settings = "studySettings"
        static let currentQuestion = "currentQuestion"
        static let questionHistory = "questionHistory"
        static let studyRecords = "studyRecords"
        static let gradingResult = "gradingResult"
        static let lastAnswer = "lastAnswer"
        static let isRunning = "isRunning"
        static let apiKey = "openAIAPIKey"
        static let questionResponseID = "questionResponseID"
        static let appLogs = "appLogs"
        static let isDebuggingEnabled = "isDebuggingEnabled"
    }

    private let defaults: UserDefaults
    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        encoder.dateEncodingStrategy = .iso8601
        decoder.dateDecodingStrategy = .iso8601
    }

    func loadSettings() -> StudySettings {
        guard let data = defaults.data(forKey: Keys.settings),
              let settings = try? decoder.decode(StudySettings.self, from: data) else {
            return .default
        }

        return StudySettings(
            topic: settings.topic,
            difficulty: settings.difficulty,
            language: settings.language,
            customPrompt: settings.customPrompt,
            intervalMinutes: settings.sanitizedIntervalMinutes,
            maxHistoryCount: settings.sanitizedMaxHistoryCount
        )
    }

    func saveSettings(_ settings: StudySettings) {
        let sanitizedSettings = StudySettings(
            topic: settings.topic,
            difficulty: settings.difficulty,
            language: settings.language,
            customPrompt: settings.customPrompt,
            intervalMinutes: settings.sanitizedIntervalMinutes,
            maxHistoryCount: settings.sanitizedMaxHistoryCount
        )

        if let data = try? encoder.encode(sanitizedSettings) {
            defaults.set(data, forKey: Keys.settings)
        }
        trimStudyRecords(to: sanitizedSettings.sanitizedMaxHistoryCount)
    }

    func loadQuestion() -> QuestionItem? {
        guard let data = defaults.data(forKey: Keys.currentQuestion) else {
            return nil
        }

        return try? decoder.decode(QuestionItem.self, from: data)
    }

    func saveQuestion(_ question: QuestionItem?) {
        saveOptional(question, forKey: Keys.currentQuestion)
    }

    func loadQuestionHistory() -> [QuestionItem] {
        guard let data = defaults.data(forKey: Keys.questionHistory),
              let questions = try? decoder.decode([QuestionItem].self, from: data) else {
            return []
        }

        return Array(questions.suffix(20))
    }

    func appendQuestionToHistory(_ question: QuestionItem) {
        var questions = loadQuestionHistory()
        let normalizedQuestion = Self.normalizedQuestionText(question.question)

        questions.removeAll {
            Self.normalizedQuestionText($0.question) == normalizedQuestion
        }
        questions.append(question)

        if let data = try? encoder.encode(Array(questions.suffix(20))) {
            defaults.set(data, forKey: Keys.questionHistory)
        }
    }

    func loadStudyRecords() -> [StudyRecord] {
        guard let data = defaults.data(forKey: Keys.studyRecords),
              let records = try? decoder.decode([StudyRecord].self, from: data) else {
            return []
        }

        return Array(records.suffix(loadSettings().sanitizedMaxHistoryCount))
    }

    func appendStudyRecord(question: QuestionItem, settings: StudySettings) {
        var records = loadStudyRecords()
        let normalizedQuestion = Self.normalizedQuestionText(question.question)

        records.removeAll {
            Self.normalizedQuestionText($0.question.question) == normalizedQuestion
        }
        records.append(StudyRecord(
            question: question,
            topic: settings.topic,
            difficulty: settings.difficulty
        ))

        saveStudyRecords(records)
    }

    func updateStudyRecord(question: QuestionItem, answer: String, gradingResult: GradingResult) {
        var records = loadStudyRecords()
        let normalizedQuestion = Self.normalizedQuestionText(question.question)

        if let index = records.lastIndex(where: {
            $0.question.createdAt == question.createdAt ||
                Self.normalizedQuestionText($0.question.question) == normalizedQuestion
        }) {
            records[index].answer = answer
            records[index].gradingResult = gradingResult
            records[index].answeredAt = Date()
        } else {
            records.append(StudyRecord(
                question: question,
                answer: answer,
                gradingResult: gradingResult,
                topic: "",
                difficulty: .beginner,
                answeredAt: Date()
            ))
        }

        saveStudyRecords(records)
    }

    func deleteStudyRecord(_ record: StudyRecord) {
        var records = loadStudyRecords()
        let normalizedQuestion = Self.normalizedQuestionText(record.question.question)

        records.removeAll {
            $0.id == record.id ||
                Self.normalizedQuestionText($0.question.question) == normalizedQuestion
        }

        saveStudyRecords(records)
    }

    func clearStudyRecords() {
        defaults.removeObject(forKey: Keys.studyRecords)
    }

    func loadQuestionResponseID() -> String? {
        guard let id = defaults.string(forKey: Keys.questionResponseID),
              !id.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return nil
        }

        return id
    }

    func saveQuestionResponseID(_ responseID: String?) {
        guard let responseID,
              !responseID.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            defaults.removeObject(forKey: Keys.questionResponseID)
            return
        }

        defaults.set(responseID, forKey: Keys.questionResponseID)
    }

    nonisolated static func normalizedQuestionText(_ question: String) -> String {
        question
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
            .components(separatedBy: .whitespacesAndNewlines)
            .filter { !$0.isEmpty }
            .joined(separator: " ")
    }

    private func saveStudyRecords(_ records: [StudyRecord]) {
        if let data = try? encoder.encode(Array(records.suffix(loadSettings().sanitizedMaxHistoryCount))) {
            defaults.set(data, forKey: Keys.studyRecords)
        }
    }

    private func trimStudyRecords(to limit: Int) {
        guard let data = defaults.data(forKey: Keys.studyRecords),
              let records = try? decoder.decode([StudyRecord].self, from: data),
              records.count > limit else {
            return
        }

        if let trimmedData = try? encoder.encode(Array(records.suffix(limit))) {
            defaults.set(trimmedData, forKey: Keys.studyRecords)
        }
    }

    func loadGradingResult() -> GradingResult? {
        guard let data = defaults.data(forKey: Keys.gradingResult) else {
            return nil
        }

        return try? decoder.decode(GradingResult.self, from: data)
    }

    func saveGradingResult(_ result: GradingResult?) {
        saveOptional(result, forKey: Keys.gradingResult)
    }

    func loadLastAnswer() -> String {
        defaults.string(forKey: Keys.lastAnswer) ?? ""
    }

    func saveLastAnswer(_ answer: String) {
        defaults.set(answer, forKey: Keys.lastAnswer)
    }

    func loadIsRunning() -> Bool {
        guard defaults.object(forKey: Keys.isRunning) != nil else {
            return true
        }

        return defaults.bool(forKey: Keys.isRunning)
    }

    func saveIsRunning(_ isRunning: Bool) {
        defaults.set(isRunning, forKey: Keys.isRunning)
    }

    func loadAPIKey() -> String {
        defaults.string(forKey: Keys.apiKey) ?? ""
    }

    func saveAPIKey(_ apiKey: String) {
        let trimmedKey = apiKey.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmedKey.isEmpty {
            defaults.removeObject(forKey: Keys.apiKey)
        } else {
            defaults.set(trimmedKey, forKey: Keys.apiKey)
        }
    }

    func loadIsDebuggingEnabled() -> Bool {
        defaults.bool(forKey: Keys.isDebuggingEnabled)
    }

    func saveIsDebuggingEnabled(_ isEnabled: Bool) {
        defaults.set(isEnabled, forKey: Keys.isDebuggingEnabled)
    }

    func loadAppLogs() -> [AppLogEntry] {
        guard let data = defaults.data(forKey: Keys.appLogs),
              let logs = try? decoder.decode([AppLogEntry].self, from: data) else {
            return []
        }

        return Array(logs.suffix(Self.maxLogCount))
    }

    func appendAppLog(_ entry: AppLogEntry) {
        var logs = loadAppLogs()
        logs.append(entry)
        saveAppLogs(logs)
    }

    func clearAppLogs() {
        defaults.removeObject(forKey: Keys.appLogs)
    }

    private func saveAppLogs(_ logs: [AppLogEntry]) {
        if let data = try? encoder.encode(Array(logs.suffix(Self.maxLogCount))) {
            defaults.set(data, forKey: Keys.appLogs)
        }
    }

    private static let maxLogCount = 1000

    private func saveOptional<T: Encodable>(_ value: T?, forKey key: String) {
        guard let value else {
            defaults.removeObject(forKey: key)
            return
        }

        if let data = try? encoder.encode(value) {
            defaults.set(data, forKey: key)
        }
    }
}
