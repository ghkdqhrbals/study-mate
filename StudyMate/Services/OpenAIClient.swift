import Foundation

enum OpenAIClientError: LocalizedError, Equatable {
    case missingAPIKey
    case invalidURL
    case invalidResponse
    case httpError(Int, String)
    case missingOutputText
    case decodingOutputFailed

    var errorDescription: String? {
        switch self {
        case .missingAPIKey:
            "OpenAI API 키를 설정하세요."
        case .invalidURL:
            "OpenAI API URL이 올바르지 않습니다."
        case .invalidResponse:
            "OpenAI API 응답을 읽을 수 없습니다."
        case .httpError(let status, let body):
            "OpenAI API 오류 \(status): \(body)"
        case .missingOutputText:
            "OpenAI 응답에 텍스트 출력이 없습니다."
        case .decodingOutputFailed:
            "OpenAI JSON 응답 파싱에 실패했습니다."
        }
    }
}

@MainActor
final class OpenAIClient {
    private let model = "gpt-5.4"
    private let endpoint = URL(string: "https://api.openai.com/v1/responses")
    private let modelsEndpoint = URL(string: "https://api.openai.com/v1/models")
    private let session: URLSession

    init(session: URLSession = .shared) {
        self.session = session
    }

    func validateAPIKey(_ apiKey: String) async throws {
        let trimmedAPIKey = apiKey.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedAPIKey.isEmpty else {
            throw OpenAIClientError.missingAPIKey
        }

        guard let modelsEndpoint else {
            throw OpenAIClientError.invalidURL
        }

        var request = URLRequest(url: modelsEndpoint)
        request.httpMethod = "GET"
        request.setValue("Bearer \(trimmedAPIKey)", forHTTPHeaderField: "Authorization")

        let (data, response) = try await session.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse else {
            throw OpenAIClientError.invalidResponse
        }

        guard (200..<300).contains(httpResponse.statusCode) else {
            let body = String(data: data, encoding: .utf8) ?? "No response body"
            throw OpenAIClientError.httpError(httpResponse.statusCode, body)
        }
    }

    func generateQuestion(
        settings: StudySettings,
        recentQuestions: [QuestionItem] = [],
        previousResponseID: String? = nil,
        apiKey: String
    ) async throws -> GeneratedQuestionResult {
        let prompt = Self.questionPrompt(settings: settings, recentQuestions: recentQuestions)

        let schema: [String: Any] = [
            "type": "object",
            "additionalProperties": false,
            "properties": [
                "question": ["type": "string"],
                "expectedAnswerHint": [
                    "type": ["string", "null"]
                ]
            ],
            "required": ["question", "expectedAnswerHint"]
        ]

        let output = try await sendStructuredRequest(
            apiKey: apiKey,
            instructions: "You are an AI teacher that creates varied study questions in \(settings.language.promptLabel). Never repeat recent questions.",
            input: prompt,
            previousResponseID: previousResponseID,
            schemaName: "study_question",
            schema: schema
        )

        let generated = try decodeOutput(GeneratedQuestion.self, from: output.text)
        return GeneratedQuestionResult(
            question: QuestionItem(
                question: generated.question,
                expectedAnswerHint: generated.expectedAnswerHint,
                createdAt: Date()
            ),
            responseID: output.responseID
        )
    }

    nonisolated static func questionPrompt(settings: StudySettings, recentQuestions: [QuestionItem]) -> String {
        let recentQuestionText = recentQuestions
            .suffix(20)
            .enumerated()
            .map { index, item in "\(index + 1). \(item.question)" }
            .joined(separator: "\n")

        return """
        Create one study question.

        Topic: \(settings.topic)
        Difficulty: \(settings.difficulty.promptLabel)
        Language: \(settings.language.promptLabel)
        Teacher instruction: \(settings.customPrompt)
        Recent questions to avoid:
        \(recentQuestionText.isEmpty ? "None" : recentQuestionText)

        Requirements:
        - Return JSON only.
        - Write the question and expectedAnswerHint in \(settings.language.promptLabel).
        - If Teacher instruction conflicts with Language, Language wins.
        - The question should be concise and practical.
        - Do not repeat or closely paraphrase any recent question.
        - Vary the concept, angle, example, or required reasoning from recent questions.
        - If the topic is broad, rotate through different subtopics.
        """
    }

    func gradeAnswer(question: QuestionItem, answer: String, settings: StudySettings, apiKey: String) async throws -> GradingResult {
        let prompt = """
        Grade the user's answer.

        Topic: \(settings.topic)
        Difficulty: \(settings.difficulty.promptLabel)
        Feedback language: \(settings.language.promptLabel)
        Question: \(question.question)
        Expected hint: \(question.expectedAnswerHint ?? "None")
        User answer: \(answer)

        Scoring rubric:
        - 90-100: correct and complete
        - 70-89: mostly correct, minor gaps
        - 40-69: partially correct, important gaps
        - 10-39: mostly incorrect, only small relevant pieces
        - 0-9: irrelevant, blank, or fundamentally wrong

        Set isCorrect to true only when score is 70 or higher.
        Set isCorrect to false when score is below 70.
        The feedback tone must match the numeric score. Do not praise a very low score as correct or close.

        Return fair, concise feedback and explanation in \(settings.language.promptLabel).
        """

        let schema: [String: Any] = [
            "type": "object",
            "additionalProperties": false,
            "properties": [
                "score": [
                    "type": "integer",
                    "minimum": 0,
                    "maximum": 100
                ],
                "isCorrect": ["type": "boolean"],
                "feedback": ["type": "string"],
                "explanation": ["type": "string"]
            ],
            "required": ["score", "isCorrect", "feedback", "explanation"]
        ]

        let output = try await sendStructuredRequest(
            apiKey: apiKey,
            instructions: "You are a strict but helpful AI teacher. Write feedback in \(settings.language.promptLabel).",
            input: prompt,
            previousResponseID: nil,
            schemaName: "grading_result",
            schema: schema
        )

        let decoded = try decodeOutput(GradingResult.self, from: output.text)
        return Self.normalizedGradingResult(decoded)
    }

    nonisolated static func normalizedGradingResult(_ result: GradingResult) -> GradingResult {
        let score = min(max(result.score, 0), 100)
        return GradingResult(
            score: score,
            isCorrect: score >= 70,
            feedback: result.feedback,
            explanation: result.explanation
        )
    }

    nonisolated static func extractOutputText(from data: Data) -> String? {
        guard let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return nil
        }

        if let outputText = object["output_text"] as? String {
            return outputText
        }

        guard let output = object["output"] as? [[String: Any]] else {
            return nil
        }

        for item in output {
            guard let content = item["content"] as? [[String: Any]] else {
                continue
            }

            for contentItem in content {
                if let text = contentItem["text"] as? String {
                    return text
                }
            }
        }

        return nil
    }

    nonisolated static func extractResponseID(from data: Data) -> String? {
        guard let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return nil
        }

        return object["id"] as? String
    }

    private func sendStructuredRequest(
        apiKey: String,
        instructions: String,
        input: String,
        previousResponseID: String?,
        schemaName: String,
        schema: [String: Any]
    ) async throws -> StructuredResponseOutput {
        let trimmedAPIKey = apiKey.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedAPIKey.isEmpty else {
            throw OpenAIClientError.missingAPIKey
        }

        guard let endpoint else {
            throw OpenAIClientError.invalidURL
        }

        var body: [String: Any] = [
            "model": model,
            "instructions": instructions,
            "input": input,
            "text": [
                "format": [
                    "type": "json_schema",
                    "name": schemaName,
                    "schema": schema,
                    "strict": true
                ],
                "verbosity": "low"
            ]
        ]

        if let previousResponseID,
           !previousResponseID.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            body["previous_response_id"] = previousResponseID
        }

        var request = URLRequest(url: endpoint)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("Bearer \(trimmedAPIKey)", forHTTPHeaderField: "Authorization")
        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (data, response) = try await session.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse else {
            throw OpenAIClientError.invalidResponse
        }

        guard (200..<300).contains(httpResponse.statusCode) else {
            let body = String(data: data, encoding: .utf8) ?? "No response body"
            throw OpenAIClientError.httpError(httpResponse.statusCode, body)
        }

        guard let text = Self.extractOutputText(from: data) else {
            throw OpenAIClientError.missingOutputText
        }

        return StructuredResponseOutput(
            text: text,
            responseID: Self.extractResponseID(from: data)
        )
    }

    private func decodeOutput<T: Decodable>(_ type: T.Type, from output: String) throws -> T {
        guard let data = output.data(using: .utf8),
              let decoded = try? JSONDecoder().decode(T.self, from: data) else {
            throw OpenAIClientError.decodingOutputFailed
        }

        return decoded
    }
}

struct GeneratedQuestionResult: Equatable {
    var question: QuestionItem
    var responseID: String?
}

private struct StructuredResponseOutput {
    var text: String
    var responseID: String?
}

private struct GeneratedQuestion: Decodable {
    var question: String
    var expectedAnswerHint: String?
}
