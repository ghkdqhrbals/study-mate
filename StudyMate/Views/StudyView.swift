import SwiftUI

struct StudyView: View {
    @EnvironmentObject private var appState: AppState
    @State private var showsHint = false

    var body: some View {
        let strings = appState.strings

        VStack(alignment: .leading, spacing: 14) {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text(appState.settings.topic)
                        .font(.headline)
                    Text("\(appState.settings.difficulty.displayName(language: appState.settings.appLanguage)) · \(appState.settings.language.displayName) · \(strings.minuteLabel(appState.settings.sanitizedIntervalMinutes))")
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
                        Label(strings.newQuestion, systemImage: "sparkles")
                    }
                }
                .disabled(appState.isGeneratingQuestion)
            }

            Divider()

            if !appState.pendingStudyRecords.isEmpty {
                PendingQuestionsSection(
                    records: appState.pendingStudyRecords,
                    currentQuestion: appState.currentQuestion,
                    strings: strings
                ) { record in
                    appState.selectStudyRecord(record)
                }

                Divider()
            }

            Group {
                if let question = appState.currentQuestion {
                    VStack(alignment: .leading, spacing: 8) {
                        Text(strings.question)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Text(question.question)
                            .font(.body)
                            .textSelection(.enabled)

                        if let hint = question.expectedAnswerHint,
                           !hint.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                            VStack(alignment: .leading, spacing: 6) {
                                Button {
                                    showsHint.toggle()
                                } label: {
                                    Label(showsHint ? strings.hideHint : strings.showHint, systemImage: "lightbulb")
                                }
                                .buttonStyle(.borderless)
                                .font(.caption)

                                if showsHint {
                                    Text(hint)
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                        .textSelection(.enabled)
                                }
                            }
                            .padding(.top, 4)
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(12)
                    .background(Color.secondary.opacity(0.08))
                    .clipShape(RoundedRectangle(cornerRadius: 8))
                } else {
                    ContentUnavailableView(
                        strings.noQuestion,
                        systemImage: "questionmark.bubble",
                        description: Text(strings.noQuestionDescription)
                    )
                    .frame(maxWidth: .infinity, minHeight: 140)
                }
            }

            VStack(alignment: .leading, spacing: 8) {
                Text(strings.answer)
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
                    Label(strings.gradeAnswer, systemImage: "checkmark.seal")
                }
            }
            .disabled(appState.currentQuestion == nil || appState.isGradingAnswer)

            if let result = appState.gradingResult {
                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        Label(result.gradeTitle(strings: strings), systemImage: result.gradeIconName)
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
        .onChange(of: appState.currentQuestion?.createdAt) {
            showsHint = false
        }
    }
}

private struct PendingQuestionsSection: View {
    var records: [StudyRecord]
    var currentQuestion: QuestionItem?
    var strings: AppStrings
    var onSelect: (StudyRecord) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .firstTextBaseline) {
                Text(strings.pendingQuestions)
                    .font(.subheadline)
                    .fontWeight(.semibold)

                Text(strings.pendingQuestionCount(records.count))
                    .font(.caption)
                    .foregroundStyle(.secondary)

                Spacer()
            }

            VStack(spacing: 8) {
                ForEach(records) { record in
                    let isSelected = isCurrent(record)

                    Button {
                        onSelect(record)
                    } label: {
                        PendingQuestionRow(record: record, strings: strings, isSelected: isSelected)
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    private func isCurrent(_ record: StudyRecord) -> Bool {
        guard let currentQuestion else {
            return false
        }

        return record.question.createdAt == currentQuestion.createdAt ||
            SettingsStore.normalizedQuestionText(record.question.question) ==
            SettingsStore.normalizedQuestionText(currentQuestion.question)
    }
}

private struct PendingQuestionRow: View {
    var record: StudyRecord
    var strings: AppStrings
    var isSelected: Bool

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: isSelected ? "arrow.turn.down.right.circle.fill" : "circle")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(isSelected ? Color.accentColor : Color.secondary)
                .padding(.top, 3)

            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 6) {
                    Text(record.topic.isEmpty ? strings.studyFallback : record.topic)
                        .font(.caption)
                        .foregroundStyle(.secondary)

                    Text("·")
                        .font(.caption)
                        .foregroundStyle(.secondary)

                    Text(record.difficulty.displayName(language: strings.language))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Text(record.question.question)
                    .font(.callout)
                    .lineLimit(2)
                    .frame(maxWidth: .infinity, alignment: .leading)

                if let answer = record.answer, !answer.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    Text(strings.answerPrefix(answer))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }

            Spacer(minLength: 8)

            Text(isSelected ? strings.current : strings.openPendingQuestion)
                .font(.caption)
                .fontWeight(.semibold)
                .foregroundStyle(isSelected ? Color.accentColor : Color.secondary)
        }
        .padding(10)
        .background(isSelected ? Color.accentColor.opacity(0.12) : Color.secondary.opacity(0.07))
        .overlay {
            RoundedRectangle(cornerRadius: 8)
                .stroke(isSelected ? Color.accentColor.opacity(0.45) : Color.clear, lineWidth: 1)
        }
        .clipShape(RoundedRectangle(cornerRadius: 8))
        .contentShape(Rectangle())
    }
}

private extension GradingResult {
    func gradeTitle(strings: AppStrings) -> String {
        switch score {
        case 90...100:
            strings.correct
        case 70..<90:
            strings.nearlyCorrect
        case 40..<70:
            strings.partialCorrect
        default:
            strings.needsImprovement
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
