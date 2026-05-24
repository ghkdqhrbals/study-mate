import SwiftUI

struct StatisticsView: View {
    @EnvironmentObject private var appState: AppState
    @State private var selectedRecord: StudyRecord?

    private var gradedRecords: [StudyRecord] {
        appState.studyRecords
            .filter { $0.gradingResult != nil }
            .sorted { $0.question.createdAt < $1.question.createdAt }
    }

    private var listedGradedRecords: [StudyRecord] {
        Array(gradedRecords.reversed())
    }

    private var scores: [Int] {
        gradedRecords.compactMap { $0.gradingResult?.score }
    }

    private var difficultyStats: [DifficultyStat] {
        Difficulty.allCases.compactMap { difficulty in
            let records = gradedRecords.filter { $0.difficulty == difficulty }
            let scores = records.compactMap { $0.gradingResult?.score }
            guard !scores.isEmpty else {
                return nil
            }

            let correctCount = records.filter { $0.gradingResult?.isCorrect == true }.count
            return DifficultyStat(
                difficulty: difficulty,
                count: scores.count,
                average: Int((Double(scores.reduce(0, +)) / Double(scores.count)).rounded()),
                best: scores.max() ?? 0,
                correctRate: Int((Double(correctCount) / Double(records.count) * 100).rounded())
            )
        }
    }

    var body: some View {
        let strings = appState.strings

        Group {
            if scores.isEmpty {
                VStack(alignment: .leading, spacing: 14) {
                    Text(strings.stats)
                        .font(.headline)

                    ContentUnavailableView(
                        strings.noScores,
                        systemImage: "chart.xyaxis.line",
                        description: Text(strings.noScoresDescription)
                    )
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
            } else {
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 8) {
                        Text(strings.stats)
                            .font(.headline)
                            .padding(.bottom, 6)

                        HStack(spacing: 10) {
                            StatBox(title: strings.responses, value: "\(scores.count)")
                            StatBox(title: strings.average, value: "\(averageScore)")
                            StatBox(title: strings.best, value: "\(scores.max() ?? 0)")
                        }

                        DateRangeSummary(records: gradedRecords, strings: strings)
                            .padding(.bottom, 4)

                        DifficultyStatsSection(stats: difficultyStats, strings: strings)
                            .padding(.top, 4)

                        ScoreLineChart(records: gradedRecords)
                            .frame(height: 160)
                            .padding(.vertical, 8)

                        Text(strings.scoreByQuestion)
                            .font(.subheadline)
                            .fontWeight(.semibold)
                            .padding(.top, 4)

                        ForEach(Array(listedGradedRecords.enumerated()), id: \.element.id) { index, record in
                            Button {
                                selectedRecord = record
                            } label: {
                                ScoreRecordRow(index: listedGradedRecords.count - index, record: record, strings: strings)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding(.bottom, 16)
                }
            }
        }
        .padding(.top, 10)
        .frame(maxHeight: .infinity, alignment: .top)
        .popover(item: $selectedRecord, arrowEdge: .trailing) { record in
            StudyRecordDetailView(record: record)
                .frame(width: 420)
                .frame(minHeight: 360)
                .padding()
        }
    }

    private var averageScore: Int {
        guard !scores.isEmpty else {
            return 0
        }

        return Int((Double(scores.reduce(0, +)) / Double(scores.count)).rounded())
    }
}

struct StudyRecordDetailView: View {
    @EnvironmentObject private var appState: AppState
    var record: StudyRecord
    @State private var draftAnswer: String
    @State private var showsHint = false

    init(record: StudyRecord) {
        self.record = record
        _draftAnswer = State(initialValue: record.answer ?? "")
    }

    var body: some View {
        let displayedRecord = latestRecord

        VStack(alignment: .leading, spacing: 12) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text(displayedRecord.topic.isEmpty ? appState.strings.problem : displayedRecord.topic)
                        .font(.headline)
                    Text(displayedRecord.difficulty.displayName(language: appState.settings.appLanguage))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Spacer()

                if let score = displayedRecord.gradingResult?.score {
                    Text("\(score)/100")
                        .font(.title3)
                        .fontWeight(.semibold)
                }
            }

            Divider()

            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    DetailSection(title: appState.strings.question, text: displayedRecord.question.question)

                    if let hint = displayedRecord.question.expectedAnswerHint,
                       !hint.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                        VStack(alignment: .leading, spacing: 6) {
                            Button {
                                showsHint.toggle()
                            } label: {
                                Label(showsHint ? appState.strings.hideHint : appState.strings.showHint, systemImage: "lightbulb")
                            }
                            .buttonStyle(.borderless)
                            .font(.caption)

                            if showsHint {
                                DetailSection(title: appState.strings.hint, text: hint)
                            }
                        }
                    }

                    if let answer = displayedRecord.answer, !answer.isEmpty {
                        DetailSection(title: appState.strings.answer, text: answer)
                    }

                    if let result = displayedRecord.gradingResult {
                        DetailSection(title: appState.strings.feedback, text: result.feedback)
                        DetailSection(title: appState.strings.explanation, text: result.explanation)
                    } else {
                        VStack(alignment: .leading, spacing: 8) {
                            Text(appState.strings.answer)
                                .font(.caption)
                                .foregroundStyle(.secondary)

                            TextEditor(text: $draftAnswer)
                                .frame(minHeight: 110)
                                .padding(6)
                                .overlay {
                                    RoundedRectangle(cornerRadius: 8)
                                        .stroke(Color.secondary.opacity(0.24))
                                }

                            Button {
                                Task {
                                    await appState.gradeRecord(displayedRecord, answer: draftAnswer)
                                }
                            } label: {
                                if appState.isGradingAnswer {
                                    ProgressView()
                                        .controlSize(.small)
                                } else {
                                    Label(appState.strings.gradeAnswer, systemImage: "checkmark.seal")
                                }
                            }
                            .disabled(appState.isGradingAnswer || draftAnswer.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                        }
                    }
                }
            }
        }
    }

    private var latestRecord: StudyRecord {
        appState.studyRecords.first {
            $0.id == record.id ||
                SettingsStore.normalizedQuestionText($0.question.question) == SettingsStore.normalizedQuestionText(record.question.question)
        } ?? record
    }
}

private struct DetailSection: View {
    var title: String
    var text: String

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(title)
                .font(.caption)
                .foregroundStyle(.secondary)
            Text(text)
                .textSelection(.enabled)
                .lineLimit(nil)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

private struct DifficultyStat: Identifiable {
    var difficulty: Difficulty
    var count: Int
    var average: Int
    var best: Int
    var correctRate: Int

    var id: Difficulty { difficulty }
}

private struct DifficultyStatsSection: View {
    var stats: [DifficultyStat]
    var strings: AppStrings

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(strings.statsByDifficulty)
                .font(.subheadline)
                .fontWeight(.semibold)

            LazyVGrid(
                columns: [
                    GridItem(.flexible(minimum: 120), spacing: 8),
                    GridItem(.flexible(minimum: 120), spacing: 8)
                ],
                spacing: 8
            ) {
                ForEach(stats) { stat in
                    VStack(alignment: .leading, spacing: 8) {
                        HStack {
                            Text(stat.difficulty.displayName(language: strings.language))
                                .font(.subheadline)
                                .fontWeight(.semibold)
                            Spacer()
                            Text(strings.itemCount(stat.count))
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }

                        HStack(spacing: 10) {
                            MiniMetric(title: strings.average, value: "\(stat.average)")
                            MiniMetric(title: strings.best, value: "\(stat.best)")
                            MiniMetric(title: strings.correctRate, value: "\(stat.correctRate)%")
                        }
                    }
                    .padding(10)
                    .background(Color.secondary.opacity(0.07))
                    .clipShape(RoundedRectangle(cornerRadius: 8))
                }
            }
        }
    }
}

private struct MiniMetric: View {
    var title: String
    var value: String

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title)
                .font(.caption2)
                .foregroundStyle(.secondary)
            Text(value)
                .font(.callout)
                .fontWeight(.semibold)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

private struct StatBox: View {
    var title: String
    var value: String

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(.caption)
                .foregroundStyle(.secondary)
            Text(value)
                .font(.title3)
                .fontWeight(.semibold)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(10)
        .background(Color.secondary.opacity(0.08))
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }
}

private struct DateRangeSummary: View {
    var records: [StudyRecord]
    var strings: AppStrings

    var body: some View {
        HStack(spacing: 12) {
            Label(strings.period, systemImage: "calendar")
                .font(.caption)
                .fontWeight(.semibold)
                .foregroundStyle(.secondary)

            if let first = records.first?.question.createdAt,
               let latest = records.last?.question.createdAt {
                Text("\(strings.firstRecord) \(first, formatter: Self.dateFormatter)")
                Text("·")
                    .foregroundStyle(.secondary)
                Text("\(strings.latestRecord) \(latest, formatter: Self.dateFormatter)")
            }
        }
        .font(.caption)
        .lineLimit(1)
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(10)
        .background(Color.secondary.opacity(0.06))
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }

    private static let dateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateStyle = .short
        formatter.timeStyle = .short
        return formatter
    }()
}

private struct ScoreRecordRow: View {
    var index: Int
    var record: StudyRecord
    var strings: AppStrings

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Text("\(index)")
                .font(.caption)
                .foregroundStyle(.secondary)
                .frame(width: 24, alignment: .leading)
                .padding(.top, 2)

            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 6) {
                    Text(record.question.createdAt, formatter: Self.dateFormatter)
                    Text("·")
                    Text(record.topic.isEmpty ? strings.studyFallback : record.topic)
                    Text("·")
                    Text(record.difficulty.displayName(language: strings.language))
                }
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(1)

                Text(record.question.question)
                    .lineLimit(1)
            }

            Spacer(minLength: 8)

            Text("\(record.gradingResult?.score ?? 0)")
                .font(.headline)
        }
        .contentShape(Rectangle())
        .padding(9)
        .background(Color.secondary.opacity(0.07))
        .overlay {
            RoundedRectangle(cornerRadius: 8)
                .stroke(Color.secondary.opacity(0.1), lineWidth: 1)
        }
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }

    private static let dateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateStyle = .short
        formatter.timeStyle = .short
        return formatter
    }()
}

private struct ScoreLineChart: View {
    var records: [StudyRecord]

    private var scores: [Int] {
        records.compactMap { $0.gradingResult?.score }
    }

    var body: some View {
        GeometryReader { proxy in
            let points = chartPoints(in: proxy.size)

            ZStack(alignment: .topLeading) {
                RoundedRectangle(cornerRadius: 8)
                    .fill(Color.secondary.opacity(0.08))

                Path { path in
                    guard let first = points.first else {
                        return
                    }

                    path.move(to: first)
                    for point in points.dropFirst() {
                        path.addLine(to: point)
                    }
                }
                .stroke(Color.accentColor, style: StrokeStyle(lineWidth: 2.5, lineCap: .round, lineJoin: .round))

                ForEach(Array(points.enumerated()), id: \.offset) { _, point in
                    Circle()
                        .fill(Color.accentColor)
                        .frame(width: 7, height: 7)
                        .position(point)
                }

                VStack {
                    HStack {
                        Text("100")
                        Spacer()
                    }
                    Spacer()
                    HStack {
                        Text("0")
                        Spacer()
                    }
                }
                .font(.caption2)
                .foregroundStyle(.secondary)
                .padding(8)

                VStack {
                    Spacer()

                    HStack {
                        if let first = records.first?.question.createdAt {
                            Text(first, formatter: Self.axisDateFormatter)
                        }

                        Spacer()

                        if records.count > 1,
                           let latest = records.last?.question.createdAt {
                            Text(latest, formatter: Self.axisDateFormatter)
                        }
                    }
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 8)
                    .padding(.bottom, 6)
                }
            }
        }
    }

    private func chartPoints(in size: CGSize) -> [CGPoint] {
        guard !scores.isEmpty else {
            return []
        }

        let horizontalPadding: CGFloat = 22
        let topPadding: CGFloat = 18
        let bottomPadding: CGFloat = 30
        let width = max(size.width - horizontalPadding * 2, 1)
        let height = max(size.height - topPadding - bottomPadding, 1)
        let denominator = max(scores.count - 1, 1)

        return scores.enumerated().map { index, score in
            let x = horizontalPadding + width * CGFloat(index) / CGFloat(denominator)
            let y = topPadding + height * (1 - CGFloat(min(max(score, 0), 100)) / 100)
            return CGPoint(x: x, y: y)
        }
    }

    private static let axisDateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "M/d HH:mm"
        return formatter
    }()
}
