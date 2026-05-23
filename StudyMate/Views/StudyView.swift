import SwiftUI

struct StudyView: View {
    @EnvironmentObject private var appState: AppState

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text(appState.settings.topic)
                        .font(.headline)
                    Text("\(appState.settings.difficulty.displayName) · \(appState.settings.language.displayName) · \(appState.settings.sanitizedIntervalMinutes)분 간격")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Spacer()

                Button {
                    Task {
                        await appState.generateQuestion()
                    }
                } label: {
                    if appState.isGeneratingQuestion {
                        ProgressView()
                            .controlSize(.small)
                    } else {
                        Label("새 질문", systemImage: "sparkles")
                    }
                }
                .disabled(appState.isGeneratingQuestion)
            }

            Divider()

            Group {
                if let question = appState.currentQuestion {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("질문")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Text(question.question)
                            .font(.body)
                            .textSelection(.enabled)

                        if let hint = question.expectedAnswerHint, !hint.isEmpty {
                            Label(hint, systemImage: "lightbulb")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .padding(.top, 4)
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(12)
                    .background(Color.secondary.opacity(0.08))
                    .clipShape(RoundedRectangle(cornerRadius: 8))
                } else {
                    ContentUnavailableView(
                        "질문 없음",
                        systemImage: "questionmark.bubble",
                        description: Text("설정을 저장한 뒤 새 질문을 생성하세요.")
                    )
                    .frame(maxWidth: .infinity, minHeight: 140)
                }
            }

            VStack(alignment: .leading, spacing: 8) {
                Text("답변")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                TextEditor(text: Binding(
                    get: { appState.lastAnswer },
                    set: { appState.updateAnswer($0) }
                ))
                .font(.body)
                .frame(minHeight: 96)
                .padding(6)
                .overlay {
                    RoundedRectangle(cornerRadius: 8)
                        .stroke(Color.secondary.opacity(0.24))
                }
            }

            Button {
                Task {
                    await appState.gradeCurrentAnswer()
                }
            } label: {
                if appState.isGradingAnswer {
                    ProgressView()
                        .controlSize(.small)
                } else {
                    Label("채점 받기", systemImage: "checkmark.seal")
                }
            }
            .disabled(appState.currentQuestion == nil || appState.isGradingAnswer)

            if let result = appState.gradingResult {
                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        Label(result.gradeTitle, systemImage: result.gradeIconName)
                            .foregroundStyle(result.gradeColor)
                        Spacer()
                        Text("\(result.score)/100")
                            .font(.headline)
                    }

                    Text(result.feedback)
                        .font(.body)
                    Text(result.explanation)
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
                .padding(12)
                .background(Color.accentColor.opacity(0.1))
                .clipShape(RoundedRectangle(cornerRadius: 8))
            }

            Spacer(minLength: 0)
        }
        .padding(.top, 10)
    }
}

private extension GradingResult {
    var gradeTitle: String {
        switch score {
        case 90...100:
            "정답"
        case 70..<90:
            "정답에 가까움"
        case 40..<70:
            "부분 정답"
        default:
            "보완 필요"
        }
    }

    var gradeIconName: String {
        switch score {
        case 70...100:
            "checkmark.circle.fill"
        case 40..<70:
            "exclamationmark.circle.fill"
        default:
            "xmark.circle.fill"
        }
    }

    var gradeColor: Color {
        switch score {
        case 70...100:
            .green
        case 40..<70:
            .orange
        default:
            .red
        }
    }
}
