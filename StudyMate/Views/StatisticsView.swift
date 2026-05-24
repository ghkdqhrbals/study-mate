import SwiftUI

struct StatisticsView: View {
    @EnvironmentObject private var appState: AppState
    @State private var selectedRecord: StudyRecord?
    @State private var selectedPeriod: StatisticsPeriod = .all
    @State private var customStartDate = Calendar.current.date(byAdding: .day, value: -30, to: Date()) ?? Date()
    @State private var customEndDate = Date()

    private var allGradedRecords: [StudyRecord] {
        appState.studyRecords
            .filter { $0.gradingResult != nil }
            .sorted { statsDate(for: $0) < statsDate(for: $1) }
    }

    private var gradedRecords: [StudyRecord] {
        allGradedRecords.filter {
            selectedPeriod.contains(
                statsDate(for: $0),
                customStartDate: customStartDate,
                customEndDate: customEndDate
            )
        }
    }

    private var listedGradedRecords: [StudyRecord] {
        Array(gradedRecords.reversed())
    }

    private var allScores: [Int] {
        allGradedRecords.compactMap { $0.gradingResult?.score }
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

        ScrollView {
            LazyVStack(alignment: .leading, spacing: 10) {
                HStack(alignment: .firstTextBaseline) {
                    Text(strings.stats)
                        .font(.headline)

                    Spacer()

                    if !scores.isEmpty {
                        Text(strings.itemCount(scores.count))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }

                StatisticsPeriodControls(
                    selectedPeriod: $selectedPeriod,
                    customStartDate: $customStartDate,
                    customEndDate: $customEndDate,
                    filteredRecords: gradedRecords,
                    strings: strings
                )

                if allScores.isEmpty {
                    ContentUnavailableView(
                        strings.noScores,
                        systemImage: "chart.xyaxis.line",
                        description: Text(strings.noScoresDescription)
                    )
                    .frame(maxWidth: .infinity, minHeight: 280)
                } else if scores.isEmpty {
                    ContentUnavailableView(
                        strings.noScoresInPeriod,
                        systemImage: "calendar.badge.exclamationmark",
                        description: Text(strings.noScoresInPeriodDescription)
                    )
                    .frame(maxWidth: .infinity, minHeight: 280)
                } else {
                    KeyMetricsStrip(metrics: [
                        MetricItem(title: strings.responses, value: "\(scores.count)"),
                        MetricItem(title: strings.average, value: "\(averageScore)"),
                        MetricItem(title: strings.latestScore, value: "\(scores.last ?? 0)"),
                        MetricItem(title: strings.best, value: "\(scores.max() ?? 0)"),
                        MetricItem(title: strings.lowest, value: "\(scores.min() ?? 0)"),
                        MetricItem(title: strings.trend, value: trendText)
                    ])

                    StatisticsInsightSection(stats: difficultyStats, strings: strings)

                    ScoreLineChart(records: gradedRecords)
                        .frame(height: 150)
                        .padding(.vertical, 4)

                    ScoreDistributionSection(records: gradedRecords, strings: strings)
                        .padding(.top, 4)

                    DifficultyStatsSection(stats: difficultyStats, strings: strings)
                        .padding(.top, 4)

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
            }
            .padding(.trailing, 8)
            .padding(.bottom, 24)
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

    private var trendValue: Int? {
        guard scores.count >= 2,
              let latest = scores.last,
              let previous = scores.dropLast().last else {
            return nil
        }

        return latest - previous
    }

    private var trendText: String {
        guard let trendValue else {
            return "-"
        }

        if trendValue > 0 {
            return "+\(trendValue)"
        }

        return "\(trendValue)"
    }

    private func statsDate(for record: StudyRecord) -> Date {
        record.answeredAt ?? record.question.createdAt
    }
}

private struct StatisticsInsightSection: View {
    var stats: [DifficultyStat]
    var strings: AppStrings

    private var strongest: DifficultyStat? {
        stats.max { lhs, rhs in
            if lhs.average == rhs.average {
                return lhs.count < rhs.count
            }
            return lhs.average < rhs.average
        }
    }

    private var weakest: DifficultyStat? {
        stats.min { lhs, rhs in
            if lhs.average == rhs.average {
                return lhs.count < rhs.count
            }
            return lhs.average < rhs.average
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(strings.insight)
                .font(.subheadline)
                .fontWeight(.semibold)

            if let strongest, let weakest {
                HStack(spacing: 8) {
                    insightCard(
                        title: strings.strongestDifficulty,
                        stat: strongest,
                        systemImage: "arrow.up.circle"
                    )
                    insightCard(
                        title: strings.weakestDifficulty,
                        stat: weakest,
                        systemImage: "target"
                    )
                }
            } else {
                Text(strings.notEnoughStats)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(10)
                    .background(Color.secondary.opacity(0.045))
                    .clipShape(RoundedRectangle(cornerRadius: 8))
            }
        }
    }

    private func insightCard(title: String, stat: DifficultyStat, systemImage: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Label(title, systemImage: systemImage)
                .font(.caption)
                .foregroundStyle(.secondary)
            Text(stat.difficulty.displayName(language: strings.language))
                .font(.callout)
                .fontWeight(.semibold)
                .lineLimit(1)
            Text("\(stat.average)/100 · \(stat.count)")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(10)
        .background(Color.secondary.opacity(0.045))
        .overlay {
            RoundedRectangle(cornerRadius: 8)
                .stroke(Color.secondary.opacity(0.1), lineWidth: 1)
        }
        .clipShape(RoundedRectangle(cornerRadius: 8))
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

private enum StatisticsPeriod: String, CaseIterable, Identifiable {
    case all
    case today
    case last7Days
    case last30Days
    case last90Days
    case custom

    var id: String { rawValue }

    func title(strings: AppStrings) -> String {
        switch self {
        case .all:
            return strings.allPeriods
        case .today:
            return strings.today
        case .last7Days:
            return strings.last7Days
        case .last30Days:
            return strings.last30Days
        case .last90Days:
            return strings.last90Days
        case .custom:
            return strings.customPeriod
        }
    }

    func shortTitle(strings: AppStrings) -> String {
        switch self {
        case .all:
            return strings.allPeriods
        case .today:
            return strings.today
        case .last7Days:
            return strings.language == .korean ? "7일" : "7d"
        case .last30Days:
            return strings.language == .korean ? "30일" : "30d"
        case .last90Days:
            return strings.language == .korean ? "90일" : "90d"
        case .custom:
            return strings.language == .korean ? "직접" : "Custom"
        }
    }

    func contains(
        _ date: Date,
        customStartDate: Date,
        customEndDate: Date,
        now: Date = Date(),
        calendar: Calendar = .current
    ) -> Bool {
        switch self {
        case .all:
            return true
        case .today:
            let start = calendar.startOfDay(for: now)
            let end = calendar.date(byAdding: .day, value: 1, to: start) ?? now
            return date >= start && date < end
        case .last7Days:
            return date >= (calendar.date(byAdding: .day, value: -7, to: now) ?? now)
        case .last30Days:
            return date >= (calendar.date(byAdding: .day, value: -30, to: now) ?? now)
        case .last90Days:
            return date >= (calendar.date(byAdding: .day, value: -90, to: now) ?? now)
        case .custom:
            let lowerDate = min(customStartDate, customEndDate)
            let upperDate = max(customStartDate, customEndDate)
            let start = calendar.startOfDay(for: lowerDate)
            let upperStart = calendar.startOfDay(for: upperDate)
            let end = calendar.date(byAdding: .day, value: 1, to: upperStart) ?? upperDate
            return date >= start && date < end
        }
    }
}

private struct StatisticsPeriodControls: View {
    @Binding var selectedPeriod: StatisticsPeriod
    @Binding var customStartDate: Date
    @Binding var customEndDate: Date
    var filteredRecords: [StudyRecord]
    var strings: AppStrings

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text(strings.period)
                    .font(.caption)
                    .foregroundStyle(.secondary)

                Text(rangeText)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)

                Spacer(minLength: 8)
            }

            Picker(strings.period, selection: $selectedPeriod) {
                ForEach(StatisticsPeriod.allCases) { period in
                    Text(period.shortTitle(strings: strings)).tag(period)
                }
            }
            .labelsHidden()
            .pickerStyle(.segmented)

            if selectedPeriod == .custom {
                HStack(spacing: 10) {
                    DatePicker(
                        strings.startDate,
                        selection: $customStartDate,
                        displayedComponents: .date
                    )

                    DatePicker(
                        strings.endDate,
                        selection: $customEndDate,
                        displayedComponents: .date
                    )
                }
                .font(.caption)
            }
        }
        .padding(.vertical, 8)
        .padding(.horizontal, 10)
        .background(Color.secondary.opacity(0.04))
        .overlay {
            RoundedRectangle(cornerRadius: 8)
                .stroke(Color.secondary.opacity(0.1), lineWidth: 1)
        }
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }

    private var rangeText: String {
        if selectedPeriod == .custom {
            return "\(Self.dateFormatter.string(from: customStartDate)) - \(Self.dateFormatter.string(from: customEndDate))"
        }

        guard let firstRecord = filteredRecords.first,
              let latestRecord = filteredRecords.last else {
            return selectedPeriod.title(strings: strings)
        }

        let first = Self.statsDate(for: firstRecord)
        let latest = Self.statsDate(for: latestRecord)
        return "\(selectedPeriod.title(strings: strings)) · \(Self.dateTimeFormatter.string(from: first)) - \(Self.dateTimeFormatter.string(from: latest))"
    }

    private static let dateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "M/d"
        return formatter
    }()

    private static let dateTimeFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "M/d HH:mm"
        return formatter
    }()

    private static func statsDate(for record: StudyRecord) -> Date {
        record.answeredAt ?? record.question.createdAt
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
                    .background(Color.secondary.opacity(0.045))
                    .overlay {
                        RoundedRectangle(cornerRadius: 8)
                            .stroke(Color.secondary.opacity(0.1), lineWidth: 1)
                    }
                    .clipShape(RoundedRectangle(cornerRadius: 8))
                }
            }
        }
    }
}

private struct ScoreDistributionSection: View {
    var records: [StudyRecord]
    var strings: AppStrings

    private var buckets: [ScoreBucket] {
        [
            ScoreBucket(title: strings.excellentScores, count: count(in: 90...100)),
            ScoreBucket(title: strings.goodScores, count: count(in: 70...89)),
            ScoreBucket(title: strings.partialScores, count: count(in: 40...69)),
            ScoreBucket(title: strings.lowScores, count: count(in: 0...39))
        ]
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(strings.scoreDistribution)
                .font(.subheadline)
                .fontWeight(.semibold)

            VStack(spacing: 7) {
                ForEach(buckets) { bucket in
                    HStack(spacing: 8) {
                        Text(bucket.title)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .frame(width: 54, alignment: .leading)

                        ProgressView(value: Double(bucket.count), total: Double(max(records.count, 1)))
                            .tint(Color.secondary.opacity(0.65))

                        Text("\(bucket.count)")
                            .font(.caption)
                            .fontWeight(.semibold)
                            .frame(width: 24, alignment: .trailing)
                    }
                }
            }
            .padding(10)
            .background(Color.secondary.opacity(0.045))
            .overlay {
                RoundedRectangle(cornerRadius: 8)
                    .stroke(Color.secondary.opacity(0.1), lineWidth: 1)
            }
            .clipShape(RoundedRectangle(cornerRadius: 8))
        }
    }

    private func count(in range: ClosedRange<Int>) -> Int {
        records.filter { record in
            guard let score = record.gradingResult?.score else {
                return false
            }

            return range.contains(score)
        }.count
    }
}

private struct ScoreBucket: Identifiable {
    var title: String
    var count: Int

    var id: String { title }
}

private struct MetricItem: Identifiable {
    var title: String
    var value: String

    var id: String { title }
}

private struct KeyMetricsStrip: View {
    var metrics: [MetricItem]

    var body: some View {
        LazyVGrid(
            columns: [
                GridItem(.flexible(), spacing: 10),
                GridItem(.flexible(), spacing: 10),
                GridItem(.flexible(), spacing: 10)
            ],
            spacing: 10
        ) {
            ForEach(metrics) { metric in
                MiniMetric(title: metric.title, value: metric.value)
            }
        }
        .padding(10)
        .background(Color.secondary.opacity(0.045))
        .overlay {
            RoundedRectangle(cornerRadius: 8)
                .stroke(Color.secondary.opacity(0.1), lineWidth: 1)
        }
        .clipShape(RoundedRectangle(cornerRadius: 8))
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
                    Text(Self.statsDate(for: record), formatter: Self.dateFormatter)
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
        .background(Color.secondary.opacity(0.04))
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

    private static func statsDate(for record: StudyRecord) -> Date {
        record.answeredAt ?? record.question.createdAt
    }

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
                    .fill(Color.secondary.opacity(0.04))
                    .overlay {
                        RoundedRectangle(cornerRadius: 8)
                            .stroke(Color.secondary.opacity(0.1), lineWidth: 1)
                    }

                Path { path in
                    guard let first = points.first else {
                        return
                    }

                    path.move(to: first)
                    for point in points.dropFirst() {
                        path.addLine(to: point)
                    }
                }
                .stroke(Color.secondary.opacity(0.85), style: StrokeStyle(lineWidth: 2, lineCap: .round, lineJoin: .round))

                ForEach(Array(points.enumerated()), id: \.offset) { _, point in
                    Circle()
                        .fill(Color.secondary)
                        .frame(width: 5, height: 5)
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
                        if let firstRecord = records.first {
                            let first = Self.statsDate(for: firstRecord)
                            Text(first, formatter: Self.axisDateFormatter)
                        }

                        Spacer()

                        if records.count > 1,
                           let latestRecord = records.last {
                            let latest = Self.statsDate(for: latestRecord)
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

    private static func statsDate(for record: StudyRecord) -> Date {
        record.answeredAt ?? record.question.createdAt
    }
}
