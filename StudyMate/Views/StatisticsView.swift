import SwiftUI

struct StatisticsView: View {
    @EnvironmentObject private var appState: AppState
    @State private var selectedRecord: StudyRecord?
    @State private var selectedPeriod: StatisticsPeriod = .all
    @State private var customStartDate = Calendar.current.date(byAdding: .day, value: -30, to: Date()) ?? Date()
    @State private var customEndDate = Date()
    @State private var topicSearch = ""
    @State private var selectedTopicID: String?
    @State private var topicSort: TopicSort = .level
    @State private var topicPage = 0

    private static let topicPageSize = 8

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

    private var allScores: [Int] {
        allGradedRecords.compactMap { $0.gradingResult?.score }
    }

    private var scores: [Int] {
        gradedRecords.compactMap { $0.gradingResult?.score }
    }

    private var topicStats: [TopicStat] {
        Dictionary(grouping: gradedRecords, by: topicGroupKey)
            .compactMap(makeTopicStat(topicKey:records:))
            .sorted(by: defaultTopicSort)
    }

    private var filteredTopicStats: [TopicStat] {
        let query = topicSearch.trimmingCharacters(in: .whitespacesAndNewlines)
        let queryText = query.lowercased()
        let queryKey = TopicGrouping.normalizedKey(for: query, fallback: "")
        let filtered = query.isEmpty ? topicStats : topicStats.filter { stat in
            stat.topic.lowercased().contains(queryText) ||
                stat.topicAliases.contains { $0.lowercased().contains(queryText) } ||
                stat.topicKey.contains(queryKey)
        }
        return filtered.sorted { topicSort.areInIncreasingOrder($0, $1) }
    }

    private var selectedTopicStat: TopicStat? {
        if let selectedTopicID,
           let selected = pagedTopicStats.first(where: { $0.id == selectedTopicID }) {
            return selected
        }

        return pagedTopicStats.first
    }

    private var topicPageCount: Int {
        max(1, (filteredTopicStats.count + Self.topicPageSize - 1) / Self.topicPageSize)
    }

    private var boundedTopicPage: Int {
        min(max(topicPage, 0), topicPageCount - 1)
    }

    private var topicPageStartIndex: Int {
        boundedTopicPage * Self.topicPageSize
    }

    private var pagedTopicStats: [TopicStat] {
        Array(filteredTopicStats.dropFirst(topicPageStartIndex).prefix(Self.topicPageSize))
    }

    private var selectedTopicRecords: [StudyRecord] {
        selectedTopicStat?.records ?? []
    }

    private var listedSelectedTopicRecords: [StudyRecord] {
        Array(selectedTopicRecords.reversed())
    }

    var body: some View {
        let strings = appState.strings

        ScrollView {
            LazyVStack(alignment: .leading, spacing: 10) {
                if !scores.isEmpty {
                    Text(strings.itemCount(scores.count))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, alignment: .trailing)
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
                    TopicPortfolioSummary(stats: topicStats, responseCount: scores.count, strings: strings)

                    TopicBrowserSection(
                        stats: pagedTopicStats,
                        totalCount: filteredTopicStats.count,
                        pageStartIndex: topicPageStartIndex,
                        currentPage: boundedTopicPage,
                        pageCount: topicPageCount,
                        selectedTopicID: selectedTopicStat?.id,
                        topicSearch: $topicSearch,
                        topicSort: $topicSort,
                        strings: strings,
                        onPreviousPage: {
                            topicPage = max(boundedTopicPage - 1, 0)
                            selectedTopicID = nil
                        },
                        onNextPage: {
                            topicPage = min(boundedTopicPage + 1, topicPageCount - 1)
                            selectedTopicID = nil
                        },
                        onSelect: { stat in
                            selectedTopicID = stat.id
                        }
                    )

                    if let selectedTopicStat {
                        SelectedTopicSection(stat: selectedTopicStat, records: selectedTopicRecords, strings: strings)
                            .padding(.top, 4)

                        Text(strings.scoreByQuestion)
                            .font(.subheadline)
                            .fontWeight(.semibold)
                            .lineLimit(1)
                            .padding(.top, 4)

                        ForEach(Array(listedSelectedTopicRecords.enumerated()), id: \.element.id) { index, record in
                            Button {
                                selectedRecord = record
                            } label: {
                                ScoreRecordRow(index: listedSelectedTopicRecords.count - index, record: record, strings: strings)
                            }
                            .buttonStyle(.plain)
                        }
                    } else {
                        ContentUnavailableView(
                            strings.noMatchingTopics,
                            systemImage: "line.3.horizontal.decrease.circle",
                            description: Text(strings.noMatchingTopicsDescription)
                        )
                        .frame(maxWidth: .infinity, minHeight: 220)
                    }
                }
            }
            .padding(.trailing, 8)
            .padding(.bottom, 24)
        }
        .padding(.top, 10)
        .frame(maxHeight: .infinity, alignment: .top)
        .refreshable {
            await appState.refreshVisibleData()
        }
        .recordDetailPresentation(selectedRecord: $selectedRecord, strings: strings)
        .onChange(of: topicSearch) {
            resetTopicPaging()
        }
        .onChange(of: topicSort) {
            resetTopicPaging()
        }
        .onChange(of: selectedPeriod) {
            resetTopicPaging()
        }
        .onChange(of: customStartDate) {
            resetTopicPaging()
        }
        .onChange(of: customEndDate) {
            resetTopicPaging()
        }
    }

    private func statsDate(for record: StudyRecord) -> Date {
        record.answeredAt ?? record.question.createdAt
    }

    private func topicGroupKey(for record: StudyRecord) -> String {
        TopicGrouping.normalizedKey(for: record, fallback: appState.strings.studyFallback)
    }

    private func makeTopicStat(topicKey: String, records: [StudyRecord]) -> TopicStat? {
        let sortedRecords = records.sorted { statsDate(for: $0) < statsDate(for: $1) }
        let recordScores = sortedRecords.compactMap { $0.gradingResult?.score }
        guard !recordScores.isEmpty,
              let levelRange = TopicLevelRange.calculate(records: sortedRecords) else {
            return nil
        }

        let correctCount = sortedRecords.filter { $0.gradingResult?.isCorrect == true }.count
        let averageScore = Int((Double(recordScores.reduce(0, +)) / Double(recordScores.count)).rounded())
        let correctRate = Int((Double(correctCount) / Double(sortedRecords.count) * 100).rounded())

        return TopicStat(
            topicKey: topicKey,
            topic: TopicGrouping.preferredDisplayTopic(for: sortedRecords, fallback: appState.strings.studyFallback),
            topicAliases: TopicGrouping.displayAliases(for: sortedRecords, fallback: appState.strings.studyFallback),
            count: recordScores.count,
            average: averageScore,
            best: recordScores.max() ?? 0,
            correctRate: correctRate,
            levelRange: levelRange,
            records: sortedRecords,
            latestDate: sortedRecords.last.map(statsDate(for:)) ?? .distantPast
        )
    }

    private func defaultTopicSort(_ lhs: TopicStat, _ rhs: TopicStat) -> Bool {
        TopicSort.level.areInIncreasingOrder(lhs, rhs)
    }

    private func resetTopicPaging() {
        topicPage = 0
        selectedTopicID = nil
    }
}

private extension View {
    @ViewBuilder
    func recordDetailPresentation(selectedRecord: Binding<StudyRecord?>, strings: AppStrings) -> some View {
        #if os(iOS)
        sheet(item: selectedRecord) { record in
            NavigationStack {
                StudyRecordDetailView(record: record)
                    .padding()
                    .navigationTitle(strings.records)
                    .navigationBarTitleDisplayMode(.inline)
                    .toolbar {
                        ToolbarItem(placement: .topBarTrailing) {
                            Button(strings.done) {
                                selectedRecord.wrappedValue = nil
                            }
                        }
                    }
            }
        }
        #else
        popover(item: selectedRecord, arrowEdge: .trailing) { record in
            StudyRecordDetailView(record: record)
                .frame(width: 420)
                .frame(minHeight: 360)
                .padding()
        }
        #endif
    }
}

struct StudyRecordDetailView: View {
    @EnvironmentObject private var appState: AppState
    var record: StudyRecord
    @State private var draftAnswer: String
    @State private var showsHint = false
    #if os(iOS)
    @FocusState private var isAnswerEditorFocused: Bool
    #endif

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
                        .lineLimit(2)
                        .multilineTextAlignment(.leading)
                    Text(displayedRecord.difficulty.displayName(language: appState.settings.appLanguage))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, alignment: .leading)

                if let score = displayedRecord.gradingResult?.score {
                    Text("\(score)/100")
                        .font(.title3)
                        .fontWeight(.semibold)
                        .lineLimit(1)
                        .layoutPriority(1)
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
                                #if os(iOS)
                                .focused($isAnswerEditorFocused)
                                .toolbar {
                                    ToolbarItemGroup(placement: .keyboard) {
                                        Spacer()
                                        Button(appState.strings.done) {
                                            isAnswerEditorFocused = false
                                        }
                                    }
                                }
                                #endif

                            Button {
                                #if os(iOS)
                                isAnswerEditorFocused = false
                                #endif
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
            #if os(iOS)
            .scrollDismissesKeyboard(.interactively)
            #endif
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
            Text(breakableText)
                .textSelection(.enabled)
                .lineLimit(nil)
                .fixedSize(horizontal: false, vertical: true)
                .multilineTextAlignment(.leading)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var breakableText: String {
        text.breakingLongTokens()
    }
}

private extension String {
    func breakingLongTokens(every limit: Int = 28) -> String {
        var result = ""
        var token = ""

        func appendToken() {
            guard !token.isEmpty else {
                return
            }

            for (index, character) in token.enumerated() {
                if index > 0 && index % limit == 0 {
                    result.append("\u{200B}")
                }
                result.append(character)
            }
            token = ""
        }

        for character in self {
            if character.isWhitespace {
                appendToken()
                result.append(character)
            } else {
                token.append(character)
            }
        }

        appendToken()
        return result
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

private struct TopicStat: Identifiable {
    var topicKey: String
    var topic: String
    var topicAliases: [String]
    var count: Int
    var average: Int
    var best: Int
    var correctRate: Int
    var levelRange: TopicLevelRange
    var records: [StudyRecord]
    var latestDate: Date

    var id: String { topicKey }
}

private enum TopicSort: String, CaseIterable, Identifiable {
    case level
    case recent
    case name
    case count

    var id: String { rawValue }

    func title(strings: AppStrings) -> String {
        switch self {
        case .level:
            return strings.sortByLevel
        case .recent:
            return strings.sortByRecent
        case .name:
            return strings.sortByName
        case .count:
            return strings.sortByCount
        }
    }

    func areInIncreasingOrder(_ lhs: TopicStat, _ rhs: TopicStat) -> Bool {
        switch self {
        case .level:
            if lhs.levelRange.centerLevel != rhs.levelRange.centerLevel {
                return lhs.levelRange.centerLevel > rhs.levelRange.centerLevel
            }
            if lhs.count != rhs.count {
                return lhs.count > rhs.count
            }
            return lhs.topic.localizedCaseInsensitiveCompare(rhs.topic) == .orderedAscending
        case .recent:
            if lhs.latestDate != rhs.latestDate {
                return lhs.latestDate > rhs.latestDate
            }
            return lhs.topic.localizedCaseInsensitiveCompare(rhs.topic) == .orderedAscending
        case .name:
            return lhs.topic.localizedCaseInsensitiveCompare(rhs.topic) == .orderedAscending
        case .count:
            if lhs.count != rhs.count {
                return lhs.count > rhs.count
            }
            return lhs.topic.localizedCaseInsensitiveCompare(rhs.topic) == .orderedAscending
        }
    }
}

struct TopicLevelRange: Equatable {
    var level: Difficulty
    var average: Int
    var sampleCount: Int
    var centerLevel: Double
    var lowerBound: Double
    var upperBound: Double

    var startDifficulty: Difficulty {
        difficulty(at: lowerBound)
    }

    var endDifficulty: Difficulty {
        difficulty(at: min(upperBound, 0.999_999))
    }

    var compactRangeText: String {
        "\(startDifficulty.level)-\(endDifficulty.level)"
    }

    var width: Double {
        upperBound - lowerBound
    }

    static func calculate(records: [StudyRecord]) -> TopicLevelRange? {
        let scoredRecords = records.compactMap { record -> (difficulty: Difficulty, score: Int)? in
            guard let score = record.gradingResult?.score else {
                return nil
            }

            return (record.difficulty, min(max(score, 0), 100))
        }
        guard !scoredRecords.isEmpty else {
            return nil
        }

        let estimates = scoredRecords.map { estimatedLevel(difficulty: $0.difficulty, score: $0.score) }
        let centerLevel = estimates.reduce(0, +) / Double(estimates.count)
        let variance: Double
        if estimates.count > 1 {
            let sumOfSquares = estimates.reduce(0) { partialResult, estimate in
                partialResult + pow(estimate - centerLevel, 2)
            }
            variance = sumOfSquares / Double(estimates.count - 1)
        } else {
            variance = 0
        }

        let averageScore = Int((Double(scoredRecords.map(\.score).reduce(0, +)) / Double(scoredRecords.count)).rounded())
        let evidenceSpread = sqrt(variance)
        let sampleUncertainty = 0.9 / sqrt(Double(scoredRecords.count))
        let conflictUncertainty = evidenceSpread * 0.55
        let minimumHalfWidth = minimumHalfWidth(sampleCount: scoredRecords.count)
        let halfWidth = min(4.0, max(minimumHalfWidth, sampleUncertainty + conflictUncertainty))

        return make(
            centerLevel: centerLevel,
            average: averageScore,
            sampleCount: scoredRecords.count,
            halfWidth: halfWidth
        )
    }

    static func calculate(level: Difficulty, average: Int, sampleCount: Int) -> TopicLevelRange {
        let clampedAverage = min(max(average, 0), 100)
        let centerLevel = estimatedLevel(difficulty: level, score: clampedAverage)
        let halfWidth = max(minimumHalfWidth(sampleCount: sampleCount), 0.9 / sqrt(Double(max(sampleCount, 1))))

        return make(
            centerLevel: centerLevel,
            average: clampedAverage,
            sampleCount: sampleCount,
            halfWidth: halfWidth
        )
    }

    private static func make(
        centerLevel: Double,
        average: Int,
        sampleCount: Int,
        halfWidth: Double
    ) -> TopicLevelRange {
        let clampedCenter = min(max(centerLevel, 1), 10)
        let lowerLevel = max(1, clampedCenter - halfWidth)
        let upperLevel = min(10, clampedCenter + halfWidth)
        let lowerBound = progress(forLevelValue: lowerLevel)
        let upperBound = max(lowerBound + 0.025, progress(forLevelValue: upperLevel))

        return TopicLevelRange(
            level: Difficulty(level: Int(clampedCenter.rounded())),
            average: average,
            sampleCount: sampleCount,
            centerLevel: clampedCenter,
            lowerBound: lowerBound,
            upperBound: min(1, upperBound)
        )
    }

    private static func estimatedLevel(difficulty: Difficulty, score: Int) -> Double {
        let clampedScore = min(max(score, 0), 100)
        let levelValue = Double(difficulty.level) + (Double(clampedScore) - 70) / 35
        return min(max(levelValue, 1), 10)
    }

    private static func minimumHalfWidth(sampleCount: Int) -> Double {
        switch sampleCount {
        case 8...:
            0.3
        case 4...:
            0.45
        default:
            0.65
        }
    }

    private static func progress(forLevelValue levelValue: Double) -> Double {
        min(max((levelValue - 0.5) / Double(Difficulty.allCases.count), 0), 1)
    }

    private func difficulty(at progress: Double) -> Difficulty {
        let clampedProgress = min(max(progress, 0), 0.999_999)
        let index = Int((clampedProgress * Double(Difficulty.allCases.count)).rounded(.down))
        return Difficulty.allCases[min(max(index, 0), Difficulty.allCases.count - 1)]
    }
}

private struct TopicPortfolioSummary: View {
    var stats: [TopicStat]
    var responseCount: Int
    var strings: AppStrings

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(strings.topicSummary)
                .font(.subheadline)
                .fontWeight(.semibold)
                .lineLimit(1)

            KeyMetricsStrip(metrics: [
                MetricItem(title: strings.topicCount, value: "\(stats.count)"),
                MetricItem(title: strings.responses, value: "\(responseCount)")
            ])
        }
    }
}

private struct TopicBrowserSection: View {
    @State private var showsRangeHelp = false

    var stats: [TopicStat]
    var totalCount: Int
    var pageStartIndex: Int
    var currentPage: Int
    var pageCount: Int
    var selectedTopicID: String?
    @Binding var topicSearch: String
    @Binding var topicSort: TopicSort
    var strings: AppStrings
    var onPreviousPage: () -> Void
    var onNextPage: () -> Void
    var onSelect: (TopicStat) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .firstTextBaseline) {
                Text(strings.topicBrowser)
                    .font(.subheadline)
                    .fontWeight(.semibold)
                    .lineLimit(1)

                Button {
                    showsRangeHelp.toggle()
                } label: {
                    Image(systemName: "questionmark.circle")
                }
                .buttonStyle(.borderless)
                .help(strings.topicRangeHelpTitle)
                .popover(isPresented: $showsRangeHelp, arrowEdge: .bottom) {
                    VStack(alignment: .leading, spacing: 5) {
                        Label(strings.topicRangeHelpTitle, systemImage: "scope")
                            .font(.caption.weight(.semibold))

                        Text(strings.topicRangeHelpBody)
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    .frame(width: 230, alignment: .leading)
                    .padding(10)
                    #if os(iOS)
                    .presentationCompactAdaptation(.popover)
                    #endif
                }

                Spacer()

                HStack(spacing: 6) {
                    Text(pageStatus)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)

                    if pageCount > 1 {
                        Button(action: onPreviousPage) {
                            Image(systemName: "chevron.left")
                        }
                        .buttonStyle(.borderless)
                        .disabled(currentPage == 0)
                        .help(strings.previousPage)

                        Text("\(currentPage + 1)/\(pageCount)")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                            .monospacedDigit()
                            .lineLimit(1)

                        Button(action: onNextPage) {
                            Image(systemName: "chevron.right")
                        }
                        .buttonStyle(.borderless)
                        .disabled(currentPage >= pageCount - 1)
                        .help(strings.nextPage)
                    }
                }
            }

            HStack(spacing: 8) {
                TextField(strings.topicSearch, text: $topicSearch)
                    .textFieldStyle(.roundedBorder)

                Picker(strings.sortTopics, selection: $topicSort) {
                    ForEach(TopicSort.allCases) { sort in
                        Text(sort.title(strings: strings)).tag(sort)
                    }
                }
                .labelsHidden()
                .frame(width: 112)
            }

            HStack(spacing: 8) {
                Text(strings.statsByTopic)
                    .frame(maxWidth: .infinity, alignment: .leading)
                Text(strings.level)
                    .frame(width: 58, alignment: .leading)
                Text(strings.range)
                    .frame(width: 50, alignment: .trailing)
                Text(strings.responsesShort)
                    .frame(width: 44, alignment: .trailing)
            }
            .font(.caption2)
            .foregroundStyle(.secondary)
            .padding(.horizontal, 10)

            VStack(spacing: 6) {
                ForEach(stats) { stat in
                    Button {
                        onSelect(stat)
                    } label: {
                        TopicStatRow(stat: stat, strings: strings, isSelected: stat.id == selectedTopicID)
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    private var pageStatus: String {
        guard totalCount > 0 else {
            return strings.itemCount(0)
        }

        return strings.topicPageStatus(
            start: pageStartIndex + 1,
            end: pageStartIndex + stats.count,
            total: totalCount
        )
    }
}

private struct TopicStatRow: View {
    var stat: TopicStat
    var strings: AppStrings
    var isSelected: Bool = false

    var body: some View {
        VStack(alignment: .leading, spacing: 7) {
            HStack(spacing: 8) {
                Text(stat.topic)
                    .font(.callout)
                    .fontWeight(.semibold)
                    .lineLimit(1)
                    .truncationMode(.tail)
                    .frame(maxWidth: .infinity, alignment: .leading)

                Text("\(stat.levelRange.level.level)/10")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.tail)
                    .frame(width: 58, alignment: .leading)

                Text(stat.levelRange.compactRangeText)
                    .font(.callout)
                    .fontWeight(.semibold)
                    .lineLimit(1)
                    .frame(width: 50, alignment: .trailing)

                Text("\(stat.count)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .frame(width: 44, alignment: .trailing)
            }

            CompactLevelRangeBar(range: stat.levelRange)
        }
        .padding(10)
        .background(isSelected ? Color.accentColor.opacity(0.08) : Color.secondary.opacity(0.045))
        .overlay {
            RoundedRectangle(cornerRadius: 8)
                .stroke(isSelected ? Color.accentColor.opacity(0.35) : Color.secondary.opacity(0.1), lineWidth: 1)
        }
        .clipShape(RoundedRectangle(cornerRadius: 8))
        .contentShape(Rectangle())
    }
}

private struct CompactLevelRangeBar: View {
    var range: TopicLevelRange

    var body: some View {
        GeometryReader { proxy in
            ZStack(alignment: .leading) {
                HStack(spacing: 2) {
                    ForEach(Difficulty.allCases) { difficulty in
                        RoundedRectangle(cornerRadius: 3)
                            .fill(difficulty == range.level ? Color.accentColor.opacity(0.16) : Color.secondary.opacity(0.12))
                    }
                }

                RoundedRectangle(cornerRadius: 4)
                    .fill(Color.accentColor.opacity(0.72))
                    .frame(width: max(4, proxy.size.width * (range.upperBound - range.lowerBound)))
                    .offset(x: proxy.size.width * range.lowerBound)
            }
        }
        .frame(height: 8)
    }
}

private struct SelectedTopicSection: View {
    var stat: TopicStat
    var records: [StudyRecord]
    var strings: AppStrings

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .firstTextBaseline) {
                Text(stat.topic)
                    .font(.subheadline)
                    .fontWeight(.semibold)
                    .lineLimit(1)
                    .truncationMode(.tail)

                Spacer()

                Text(strings.topicTrend)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }

            LevelRangeSummary(stat: stat, strings: strings)

            if stat.topicAliases.count > 1 {
                Text(strings.groupedTopics(stat.topicAliases.joined(separator: " · ")))
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.tail)
            }

            LevelRangeBar(range: stat.levelRange, strings: strings)

            TopicLevelTrendChart(records: records, strings: strings)
                .frame(height: 150)
        }
    }
}

private struct TopicLevelTrendChart: View {
    var records: [StudyRecord]
    var strings: AppStrings

    private var points: [LevelTrendPoint] {
        var accumulated: [StudyRecord] = []
        return records
            .sorted { Self.statsDate(for: $0) < Self.statsDate(for: $1) }
            .compactMap { record in
                accumulated.append(record)
                guard let range = TopicLevelRange.calculate(records: accumulated) else {
                    return nil
                }

                return LevelTrendPoint(
                    date: Self.statsDate(for: record),
                    progress: (range.lowerBound + range.upperBound) / 2
                )
            }
    }

    var body: some View {
        GeometryReader { proxy in
            let chartPoints = chartPoints(in: proxy.size)
            let axisWidth: CGFloat = 28

            ZStack(alignment: .topLeading) {
                RoundedRectangle(cornerRadius: 8)
                    .fill(Color.secondary.opacity(0.04))
                    .overlay {
                        RoundedRectangle(cornerRadius: 8)
                            .stroke(Color.secondary.opacity(0.1), lineWidth: 1)
                    }

                Path { path in
                    guard let first = chartPoints.first else {
                        return
                    }

                    path.move(to: first)
                    for point in chartPoints.dropFirst() {
                        path.addLine(to: point)
                    }
                }
                .stroke(Color.accentColor.opacity(0.78), style: StrokeStyle(lineWidth: 2, lineCap: .round, lineJoin: .round))

                ForEach(Array(chartPoints.enumerated()), id: \.offset) { _, point in
                    Circle()
                        .fill(Color.accentColor)
                        .frame(width: 5, height: 5)
                        .position(point)
                }

                VStack {
                    HStack {
                        Text("10")
                            .frame(width: axisWidth, alignment: .leading)
                        Spacer()
                    }
                    Spacer()
                    HStack {
                        Text("1")
                            .frame(width: axisWidth, alignment: .leading)
                        Spacer()
                    }
                }
                .font(.caption2)
                .foregroundStyle(.secondary)
                .padding(8)

                VStack {
                    Spacer()

                    HStack {
                        if let firstPoint = points.first {
                            Text(firstPoint.date, formatter: Self.axisDateFormatter)
                        }

                        Spacer()

                        if points.count > 1,
                           let latestPoint = points.last {
                            Text(latestPoint.date, formatter: Self.axisDateFormatter)
                        }
                    }
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .padding(.leading, axisWidth + 12)
                    .padding(.trailing, 8)
                    .padding(.bottom, 6)
                }
            }
        }
        .accessibilityLabel(strings.topicTrend)
    }

    private func chartPoints(in size: CGSize) -> [CGPoint] {
        guard !points.isEmpty else {
            return []
        }

        let leadingPadding: CGFloat = 42
        let trailingPadding: CGFloat = 14
        let topPadding: CGFloat = 18
        let bottomPadding: CGFloat = 34
        let width = max(size.width - leadingPadding - trailingPadding, 1)
        let height = max(size.height - topPadding - bottomPadding, 1)
        let denominator = max(points.count - 1, 1)

        return points.enumerated().map { index, point in
            let x = leadingPadding + width * CGFloat(index) / CGFloat(denominator)
            let y = topPadding + height * (1 - CGFloat(min(max(point.progress, 0), 1)))
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

private struct LevelTrendPoint {
    var date: Date
    var progress: Double
}

private struct LevelRangeSummary: View {
    var stat: TopicStat
    var strings: AppStrings

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(strings.currentTopicLevel(stat.levelRange.level.displayName(language: strings.language)))
                .font(.caption2)
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .truncationMode(.tail)

            Text(
                strings.topicLevelRange(
                    stat.levelRange.startDifficulty.displayName(language: strings.language),
                    stat.levelRange.endDifficulty.displayName(language: strings.language),
                    average: stat.levelRange.average,
                    count: stat.levelRange.sampleCount
                )
            )
            .font(.caption2)
            .foregroundStyle(.secondary)
            .lineLimit(1)
            .truncationMode(.tail)
        }
    }
}

private struct LevelRangeBar: View {
    var range: TopicLevelRange
    var strings: AppStrings

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            GeometryReader { proxy in
                ZStack(alignment: .leading) {
                    HStack(spacing: 2) {
                        ForEach(Difficulty.allCases) { difficulty in
                            RoundedRectangle(cornerRadius: 3)
                                .fill(difficulty == range.level ? Color.accentColor.opacity(0.16) : Color.secondary.opacity(0.12))
                        }
                    }

                    RoundedRectangle(cornerRadius: 4)
                        .fill(Color.accentColor.opacity(0.72))
                        .frame(width: max(4, proxy.size.width * (range.upperBound - range.lowerBound)))
                        .offset(x: proxy.size.width * range.lowerBound)
                }
            }
            .frame(height: 10)

            HStack(spacing: 2) {
                ForEach(Difficulty.allCases) { difficulty in
                    Text(difficulty.shortDisplayName(language: strings.language))
                        .font(.system(size: 8, weight: difficulty == range.level ? .semibold : .regular))
                        .foregroundStyle(difficulty == range.level ? .primary : .secondary)
                        .lineLimit(1)
                        .minimumScaleFactor(0.6)
                        .frame(maxWidth: .infinity)
                }
            }
        }
        .accessibilityLabel(
            strings.topicLevelRange(
                range.startDifficulty.displayName(language: strings.language),
                range.endDifficulty.displayName(language: strings.language),
                average: range.average,
                count: range.sampleCount
            )
        )
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

private extension Difficulty {
    var levelIndex: Int {
        level - 1
    }

    func shortDisplayName(language: AppLanguage) -> String {
        "\(level)"
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

    private var columns: [GridItem] {
        let count = max(1, min(metrics.count, 3))
        return Array(
            repeating: GridItem(.flexible(), spacing: 10, alignment: .leading),
            count: count
        )
    }

    var body: some View {
        LazyVGrid(
            columns: columns,
            alignment: .leading,
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
                .lineLimit(1)
                .truncationMode(.tail)
            Text(value)
                .font(.callout)
                .fontWeight(.semibold)
                .lineLimit(1)
                .truncationMode(.tail)
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
            let axisWidth: CGFloat = 28

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
                            .frame(width: axisWidth, alignment: .leading)
                        Spacer()
                    }
                    Spacer()
                    HStack {
                        Text("0")
                            .frame(width: axisWidth, alignment: .leading)
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
                    .padding(.leading, axisWidth + 12)
                    .padding(.trailing, 8)
                    .padding(.bottom, 6)
                }
            }
        }
    }

    private func chartPoints(in size: CGSize) -> [CGPoint] {
        guard !scores.isEmpty else {
            return []
        }

        let leadingPadding: CGFloat = 42
        let trailingPadding: CGFloat = 14
        let topPadding: CGFloat = 18
        let bottomPadding: CGFloat = 34
        let width = max(size.width - leadingPadding - trailingPadding, 1)
        let height = max(size.height - topPadding - bottomPadding, 1)
        let denominator = max(scores.count - 1, 1)

        return scores.enumerated().map { index, score in
            let x = leadingPadding + width * CGFloat(index) / CGFloat(denominator)
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
