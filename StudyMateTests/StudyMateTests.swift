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
