import SwiftUI

struct StudyView: View {
    @EnvironmentObject private var appState: AppState
    @State private var showsHint = false
    @State private var draftAnswer = ""
    @State private var showsPendingLimitHelp = false
    #if os(iOS)
    @FocusState private var isAnswerEditorFocused: Bool
    #endif

    var body: some View {
        let strings = appState.strings

        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                HStack {
                    Spacer()

                    newQuestionButton(strings: strings)
                }

                StudySettingsSummarySection(
                    topic: studyTopicLabel(strings: strings),
                    level: appState.settings.difficulty.displayName(language: appState.settings.appLanguage),
                    interval: strings.minuteLabel(appState.settings.sanitizedIntervalMinutes),
                    strings: strings
                )

                Divider()

                if appState.currentQuestion != nil,
                   let notificationLandingMessage = appState.notificationLandingMessage {
                    notificationLandingInlineView(message: notificationLandingMessage, strings: strings)
                }

                if !appState.pendingStudyRecords.isEmpty {
                    PendingQuestionsSection(
                        records: appState.pendingStudyRecords,
                        currentQuestion: appState.currentQuestion,
                        strings: strings
                    ) { record in
                        appState.selectStudyRecord(record)
                    } onSkip: { record in
                        withAnimation(.easeOut(duration: 0.22)) {
                            appState.skipPendingQuestion(record)
                        }
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
                        noQuestionView(strings: strings)
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

                    answerEditor()
                }

                HStack {
                    Spacer()

                    Button {
                        submitCurrentAnswer()
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
        #if os(iOS)
        .scrollDismissesKeyboard(.interactively)
        .safeAreaInset(edge: .bottom, spacing: 0) {
            if isAnswerEditorFocused {
                keyboardAnswerActionBar(strings: strings)
            }
        }
        #endif
        .refreshable {
            await appState.refreshVisibleData()
        }
        .alert(strings.pendingQuestionLimitTitle, isPresented: $showsPendingLimitHelp) {
            Button(strings.done, role: .cancel) {}
        } message: {
            Text(strings.pendingQuestionLimitMessage)
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

    private var canSubmitAnswer: Bool {
        appState.currentQuestion != nil &&
            !draftAnswer.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty &&
            !appState.isGradingAnswer
    }

    private func studyTopicLabel(strings: AppStrings) -> String {
        let topic = appState.settings.topic.trimmingCharacters(in: .whitespacesAndNewlines)
        return topic.isEmpty ? strings.studyFallback : topic
    }

    @ViewBuilder
    private func noQuestionView(strings: AppStrings) -> some View {
        if let notificationLandingMessage = appState.notificationLandingMessage {
            VStack(spacing: 12) {
                ContentUnavailableView(
                    strings.notificationQuestionMissingTitle,
                    systemImage: "bell.slash",
                    description: Text(notificationLandingMessage)
                )

                Text(strings.notificationQuestionUnavailableHelp)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)

                HStack(spacing: 10) {
                    newQuestionButton(strings: strings, prominent: true)
                }
                .font(.caption)
            }
            .frame(maxWidth: .infinity)
        } else {
            ContentUnavailableView(
                strings.noQuestion,
                systemImage: "questionmark.bubble",
                description: Text(strings.noQuestionDescription)
            )
        }
    }

    @ViewBuilder
    private func newQuestionButton(strings: AppStrings, prominent: Bool = false) -> some View {
        if prominent {
            Button {
                requestNewQuestion()
            } label: {
                newQuestionButtonLabel(strings: strings)
            }
            .buttonStyle(.borderedProminent)
            .disabled(appState.isGeneratingQuestion)
            .opacity(appState.hasReachedPendingQuestionLimit ? 0.55 : 1)
            .accessibilityHint(appState.hasReachedPendingQuestionLimit ? strings.pendingQuestionLimitMessage : "")
        } else {
            Button {
                requestNewQuestion()
            } label: {
                newQuestionButtonLabel(strings: strings)
            }
            .buttonStyle(.bordered)
            .disabled(appState.isGeneratingQuestion)
            .opacity(appState.hasReachedPendingQuestionLimit ? 0.55 : 1)
            .accessibilityHint(appState.hasReachedPendingQuestionLimit ? strings.pendingQuestionLimitMessage : "")
        }
    }

    @ViewBuilder
    private func newQuestionButtonLabel(strings: AppStrings) -> some View {
        if appState.isGeneratingQuestion {
            ProgressView()
                .controlSize(.small)
        } else {
            Label(strings.newQuestion, systemImage: "plus.circle")
        }
    }

    private func requestNewQuestion() {
        guard !appState.isGeneratingQuestion else {
            return
        }

        if appState.hasReachedPendingQuestionLimit {
            showsPendingLimitHelp = true
            return
        }

        Task {
            await appState.generateQuestion()
        }
    }

    private func notificationLandingInlineView(message: String, strings: AppStrings) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: "bell.slash")
                .foregroundStyle(.secondary)

            VStack(alignment: .leading, spacing: 3) {
                Text(strings.notificationQuestionMissingTitle)
                    .font(.subheadline.weight(.semibold))
                Text(message)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }

            Spacer(minLength: 8)

            Button(strings.done) {
                appState.clearStatus()
            }
            .buttonStyle(.borderless)
            .font(.caption)
        }
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.secondary.opacity(0.07))
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }

    @ViewBuilder
    private func answerEditor() -> some View {
        #if os(iOS)
        AnswerEditor(
            text: $draftAnswer,
            minHeight: 96,
            isFocused: $isAnswerEditorFocused
        )
        #else
        AnswerEditor(
            text: $draftAnswer,
            minHeight: 96
        )
        #endif
    }

    private func submitCurrentAnswer() {
        #if os(iOS)
        isAnswerEditorFocused = false
        #endif

        Task {
            await appState.gradeCurrentAnswer(answer: draftAnswer)
        }
    }

    #if os(iOS)
    private func keyboardAnswerActionBar(strings: AppStrings) -> some View {
        HStack(spacing: 12) {
            Button(strings.done) {
                isAnswerEditorFocused = false
            }
            .buttonStyle(.bordered)

            Spacer(minLength: 8)

            Button {
                submitCurrentAnswer()
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
        .font(.callout)
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .frame(maxWidth: .infinity)
        .background(.bar)
        .overlay(alignment: .top) {
            Divider()
        }
        .transition(.move(edge: .bottom).combined(with: .opacity))
    }
    #endif
}

private struct StudySettingsSummarySection: View {
    var topic: String
    var level: String
    var interval: String
    var strings: AppStrings

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .firstTextBaseline) {
                Text(strings.studySettings)
                    .font(.caption)
                    .fontWeight(.semibold)
                    .foregroundStyle(.secondary)
            }

            HStack(spacing: 8) {
                StudySummaryMetric(title: strings.studyTopicShort, value: topic)
                StudySummaryMetric(title: strings.studyLevelShort, value: level)
                StudySummaryMetric(title: strings.studyIntervalShort, value: interval)
            }
        }
    }
}

private struct StudySummaryMetric: View {
    var title: String
    var value: String

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title)
                .font(.caption2)
                .foregroundStyle(.secondary)
            Text(value)
                .font(.headline)
                .lineLimit(1)
                .minimumScaleFactor(0.75)
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
    #if os(iOS)
    var isFocused: FocusState<Bool>.Binding
    #endif

    private let editorInset = EdgeInsets(top: 8, leading: 8, bottom: 8, trailing: 8)

    var body: some View {
        let editor = TextEditor(text: $text)
            .font(.body)
            .scrollContentBackground(.hidden)
            .padding(editorInset)
            .frame(minHeight: minHeight)
            .overlay {
                RoundedRectangle(cornerRadius: 8)
                    .stroke(Color.secondary.opacity(0.24))
            }

        #if os(iOS)
        editor
            .focused(isFocused)
        #else
        editor
        #endif
    }
}

private struct PendingQuestionsSection: View {
    var records: [StudyRecord]
    var currentQuestion: QuestionItem?
    var strings: AppStrings
    var onSelect: (StudyRecord) -> Void
    var onSkip: (StudyRecord) -> Void

    @State private var openSwipeRecordID: String?

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
                #if os(iOS)
                ForEach(records) { record in
                    let isSelected = isCurrent(record)
                    let skipAction: () -> Void = {
                        openSwipeRecordID = nil
                        onSkip(record)
                    }

                    SwipeRevealRow(
                        isOpen: Binding(
                            get: { openSwipeRecordID == record.id },
                            set: { openSwipeRecordID = $0 ? record.id : nil }
                        ),
                        actionWidth: 82,
                        onTap: {
                            if let openSwipeRecordID, openSwipeRecordID != record.id {
                                closeOpenSwipe(animated: true)
                                return
                            }

                            onSelect(record)
                        },
                        onFullSwipe: skipAction
                    ) {
                        PendingQuestionRow(record: record, strings: strings, isSelected: isSelected)
                    } action: {
                        SwipeActionButton(title: strings.skipQuestion, systemImage: "forward.end.fill", tint: .orange)
                    }
                    .transition(
                        .asymmetric(
                            insertion: .opacity,
                            removal: .opacity.combined(with: .move(edge: .leading))
                        )
                    )
                }
                #else
                ForEach(records) { record in
                    let isSelected = isCurrent(record)

                    Button {
                        onSelect(record)
                    } label: {
                        PendingQuestionRow(record: record, strings: strings, isSelected: isSelected)
                    }
                    .buttonStyle(.plain)
                }
                #endif
            }
        }
        .onChange(of: records.map(\.id)) {
            if let openSwipeRecordID,
               !records.contains(where: { $0.id == openSwipeRecordID }) {
                self.openSwipeRecordID = nil
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

    private func closeOpenSwipe(animated: Bool) {
        guard openSwipeRecordID != nil else {
            return
        }

        if animated {
            withAnimation(.interactiveSpring(response: 0.24, dampingFraction: 0.9)) {
                openSwipeRecordID = nil
            }
        } else {
            var transaction = Transaction()
            transaction.disablesAnimations = true
            withTransaction(transaction) {
                openSwipeRecordID = nil
            }
        }
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
        .frame(maxWidth: .infinity, alignment: .leading)
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
