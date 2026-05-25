import SwiftUI

struct StudyView: View {
    @EnvironmentObject private var appState: AppState
    @State private var showsHint = false
    @State private var draftAnswer = ""

    var body: some View {
        let strings = appState.strings
        let canSubmitAnswer = appState.currentQuestion != nil &&
            !draftAnswer.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty &&
            !appState.isGradingAnswer

        ScrollView {
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
                            Label(strings.newQuestion, systemImage: "plus.circle")
                        }
                    }
                    .disabled(appState.isGeneratingQuestion)
                    .disabled(appState.hasReachedPendingQuestionLimit)
                }

                StudyOverviewSection(
                    pendingCount: appState.pendingStudyRecords.count,
                    latestScore: latestScore,
                    averageScore: averageScore,
                    strings: strings,
                    onContinue: {
                        appState.openOldestPendingQuestion()
                    }
                )

                if appState.hasReachedPendingQuestionLimit {
                    PendingLimitValidationView(strings: strings) {
                        appState.openOldestPendingQuestion()
                    }
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
                            HStack(alignment: .firstTextBaseline) {
                                Text(strings.question)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)

                                Spacer()

                                Button {
                                    appState.copyToClipboard(question.question)
                                } label: {
                                    Label(strings.copyQuestion, systemImage: "doc.on.doc")
                                }
                                .buttonStyle(.borderless)
                                .font(.caption)

                                if appState.canSkipCurrentQuestion {
                                    Button {
                                        appState.skipCurrentQuestion()
                                    } label: {
                                        Label(strings.skipQuestion, systemImage: "forward.end.fill")
                                    }
                                    .buttonStyle(.borderless)
                                    .font(.caption)
                                    .help(strings.skipQuestionHelp)
                                }
                            }

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
                                            .lineLimit(nil)
                                            .fixedSize(horizontal: false, vertical: true)
                                            .frame(maxWidth: .infinity, alignment: .leading)
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
                    HStack(alignment: .firstTextBaseline) {
                        Text(strings.answer)
                            .font(.caption)
                            .foregroundStyle(.secondary)

                        Text(strings.draftSaved)
                            .font(.caption2)
                            .foregroundStyle(.tertiary)

                        Spacer()

                        if !draftAnswer.isEmpty {
                            Button(strings.copyAnswer) {
                                appState.copyToClipboard(draftAnswer)
                            }
                            .buttonStyle(.borderless)
                            .font(.caption)

                            Button(strings.clearAnswer) {
                                draftAnswer = ""
                            }
                            .buttonStyle(.borderless)
                            .font(.caption)
                        }
                    }

                    AnswerEditor(
                        text: $draftAnswer,
                        minHeight: 96
                    )
                }

                HStack {
                    Spacer()

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
                    .buttonStyle(.borderedProminent)
                    .disabled(!canSubmitAnswer)
                }

                if let result = appState.gradingResult {
                    VStack(alignment: .leading, spacing: 8) {
                        HStack {
                            Label(result.gradeTitle(strings: strings), systemImage: result.gradeIconName)
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
                    .background(Color.secondary.opacity(0.045))
                    .overlay {
                        RoundedRectangle(cornerRadius: 8)
                            .stroke(Color.secondary.opacity(0.1), lineWidth: 1)
                    }
                    .clipShape(RoundedRectangle(cornerRadius: 8))
                }
            }
            .padding(.top, 10)
            .padding(.trailing, 8)
            .padding(.bottom, 22)
            .frame(maxWidth: .infinity, alignment: .topLeading)
        }
        .onAppear {
            draftAnswer = appState.lastAnswer
        }
        .onChange(of: draftAnswer) {
            if draftAnswer != appState.lastAnswer {
                appState.updateAnswer(draftAnswer)
            }
        }
        .onChange(of: appState.lastAnswer) {
            if draftAnswer != appState.lastAnswer {
                draftAnswer = appState.lastAnswer
            }
        }
        .onChange(of: appState.currentQuestion?.createdAt) {
            showsHint = false
            draftAnswer = appState.lastAnswer
        }
    }

    private var gradedRecords: [StudyRecord] {
        appState.studyRecords.filter { $0.gradingResult != nil }
    }

    private var latestScore: Int? {
        gradedRecords.last?.gradingResult?.score
    }

    private var averageScore: Int? {
        let scores = gradedRecords.compactMap { $0.gradingResult?.score }
        guard !scores.isEmpty else {
            return nil
        }

        return Int((Double(scores.reduce(0, +)) / Double(scores.count)).rounded())
    }
}

private struct StudyOverviewSection: View {
    var pendingCount: Int
    var latestScore: Int?
    var averageScore: Int?
    var strings: AppStrings
    var onContinue: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .firstTextBaseline) {
                Text(strings.studyOverview)
                    .font(.caption)
                    .fontWeight(.semibold)
                    .foregroundStyle(.secondary)

                Spacer()

                if pendingCount > 0 {
                    Button(strings.continueOldestPending, action: onContinue)
                        .buttonStyle(.borderless)
                        .font(.caption)
                }
            }

            HStack(spacing: 8) {
                StudyOverviewMetric(title: strings.pendingShort, value: "\(pendingCount)")
                StudyOverviewMetric(title: strings.latestScoreShort, value: scoreText(latestScore))
                StudyOverviewMetric(title: strings.averageScoreShort, value: scoreText(averageScore))
            }
        }
    }

    private func scoreText(_ score: Int?) -> String {
        guard let score else {
            return strings.noScoreShort
        }

        return "\(score)"
    }
}

private struct PendingLimitValidationView: View {
    var strings: AppStrings
    var onContinue: () -> Void

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(.orange)
                .frame(width: 18, height: 18)

            VStack(alignment: .leading, spacing: 3) {
                Text(strings.pendingQuestionLimitTitle)
                    .font(.caption)
                    .fontWeight(.semibold)

                Text(strings.pendingQuestionLimitMessage)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Spacer(minLength: 8)

            Button(strings.continueOldestPending, action: onContinue)
                .buttonStyle(.borderless)
                .font(.caption)
        }
        .padding(10)
        .background(Color.orange.opacity(0.08))
        .overlay {
            RoundedRectangle(cornerRadius: 8)
                .stroke(Color.orange.opacity(0.18), lineWidth: 1)
        }
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }
}

private struct StudyOverviewMetric: View {
    var title: String
    var value: String

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title)
                .font(.caption2)
                .foregroundStyle(.secondary)
            Text(value)
                .font(.headline)
                .monospacedDigit()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.vertical, 8)
        .padding(.horizontal, 10)
        .background(Color.secondary.opacity(0.045))
        .overlay {
            RoundedRectangle(cornerRadius: 8)
                .stroke(Color.secondary.opacity(0.1), lineWidth: 1)
        }
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }
}

private struct AnswerEditor: View {
    @Binding var text: String
    var minHeight: CGFloat

    private let editorInset = EdgeInsets(top: 8, leading: 8, bottom: 8, trailing: 8)

    var body: some View {
        TextEditor(text: $text)
            .font(.body)
            .scrollContentBackground(.hidden)
            .padding(editorInset)
            .frame(minHeight: minHeight)
            .overlay {
                RoundedRectangle(cornerRadius: 8)
                    .stroke(Color.secondary.opacity(0.24))
            }
    }
}

private struct PendingQuestionsSection: View {
    var records: [StudyRecord]
    var currentQuestion: QuestionItem?
    var strings: AppStrings
    var onSelect: (StudyRecord) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .firstTextBaseline) {
                Text(strings.pendingQuestions)
                    .font(.caption)
                    .fontWeight(.semibold)

                Text(strings.pendingQuestionCount(records.count))
                    .font(.caption)
                    .foregroundStyle(.secondary)

                Spacer()
            }

            VStack(spacing: 4) {
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
        HStack(alignment: .center, spacing: 8) {
            VStack(alignment: .leading, spacing: 2) {
                Text(record.question.question)
                    .font(.callout)
                    .fontWeight(isSelected ? .semibold : .regular)
                    .lineLimit(1)

                HStack(spacing: 5) {
                    Text(record.topic.isEmpty ? strings.studyFallback : record.topic)
                    Text("·")
                    Text(record.difficulty.displayName(language: strings.language))
                }
                .font(.caption2)
                .foregroundStyle(.secondary)
                .lineLimit(1)
            }

            Spacer(minLength: 8)

            Text(isSelected ? strings.current : strings.openPendingQuestion)
                .font(.caption2)
                .fontWeight(.semibold)
                .foregroundStyle(.secondary)
        }
        .padding(.vertical, 7)
        .padding(.horizontal, 10)
        .background(isSelected ? Color.secondary.opacity(0.1) : Color.secondary.opacity(0.04))
        .overlay {
            RoundedRectangle(cornerRadius: 8)
                .stroke(isSelected ? Color.secondary.opacity(0.2) : Color.secondary.opacity(0.1), lineWidth: 1)
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
}
