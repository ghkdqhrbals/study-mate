import SwiftUI

struct HistoryView: View {
    @EnvironmentObject private var appState: AppState
    @State private var selectedRecordID: String?
    @State private var openSwipeRecordID: String?
    @State private var searchText = ""
    @State private var page = 0

    private let pageSize = 10

    private var orderedRecords: [StudyRecord] {
        appState.studyRecords.sorted { lhs, rhs in
            let lhsIsUngraded = lhs.gradingResult == nil
            let rhsIsUngraded = rhs.gradingResult == nil

            if lhsIsUngraded != rhsIsUngraded {
                return lhsIsUngraded
            }

            return sortDate(for: lhs) > sortDate(for: rhs)
        }
    }

    private var filteredRecords: [StudyRecord] {
        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !query.isEmpty else {
            return orderedRecords
        }

        return orderedRecords.filter { record in
            record.question.question.lowercased().contains(query) ||
                record.topic.lowercased().contains(query) ||
                (record.answer ?? "").lowercased().contains(query) ||
                record.difficulty.displayName(language: appState.settings.appLanguage).lowercased().contains(query)
        }
    }

    private func pageCount(for recordCount: Int) -> Int {
        max(Int(ceil(Double(recordCount) / Double(pageSize))), 1)
    }

    private func visibleRecords(from records: [StudyRecord], page: Int, pageCount: Int) -> [StudyRecord] {
        let clampedPage = min(max(page, 0), pageCount - 1)
        let start = clampedPage * pageSize
        let end = min(start + pageSize, records.count)

        guard start < end else {
            return []
        }

        return Array(records[start..<end])
    }

    var body: some View {
        let strings = appState.strings
        let displayedRecords = filteredRecords
        let displayedPageCount = pageCount(for: displayedRecords.count)
        let displayedPage = min(max(page, 0), displayedPageCount - 1)
        let displayedVisibleRecords = visibleRecords(
            from: displayedRecords,
            page: displayedPage,
            pageCount: displayedPageCount
        )

        VStack(alignment: .leading, spacing: 12) {
            if appState.studyRecords.isEmpty {
                ContentUnavailableView(
                    strings.noRecords,
                    systemImage: "clock.arrow.circlepath",
                    description: Text(strings.noRecordsDescription)
                )
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                HStack(spacing: 8) {
                    TextField(strings.searchRecords, text: $searchText)
                        .textFieldStyle(.roundedBorder)

                    Text(strings.filteredRecordCount(displayedRecords.count, total: appState.studyRecords.count))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }

                if displayedRecords.isEmpty {
                    ContentUnavailableView(
                        strings.noSearchResults,
                        systemImage: "magnifyingglass",
                        description: Text(strings.noSearchResultsDescription)
                    )
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else {
                    #if os(iOS)
                    ScrollView {
                        LazyVStack(spacing: 8) {
                            ForEach(displayedVisibleRecords) { record in
                                VStack(alignment: .leading, spacing: 8) {
                                    let deleteAction: () -> Void = {
                                        openSwipeRecordID = nil
                                        delete(record)
                                    }

                                    SwipeRevealRow(
                                        isOpen: Binding(
                                            get: { openSwipeRecordID == record.id },
                                            set: { openSwipeRecordID = $0 ? record.id : nil }
                                        ),
                                        onTap: {
                                            if let openSwipeRecordID, openSwipeRecordID != record.id {
                                                closeOpenSwipe(animated: true)
                                                return
                                            }

                                            selectedRecordID = selectedRecordID == record.id ? nil : record.id
                                        },
                                        onFullSwipe: deleteAction
                                    ) {
                                        HistoryRow(record: record, strings: strings, isSelected: selectedRecordID == record.id)
                                    } action: {
                                        SwipeActionButton(title: strings.clear, systemImage: "trash", tint: .red)
                                    }

                                    if selectedRecordID == record.id {
                                        InlineStudyRecordDetail(record: record) {
                                            selectedRecordID = nil
                                        }
                                        .transition(.opacity.combined(with: .move(edge: .top)))
                                    }
                                }
                                .transition(
                                    .asymmetric(
                                        insertion: .opacity,
                                        removal: .opacity.combined(with: .move(edge: .leading))
                                    )
                                )
                            }
                        }
                        .padding(.trailing, 2)
                    }
                    .frame(maxHeight: .infinity)
                    .refreshable {
                        await appState.refreshVisibleData()
                    }
                    #else
                    List {
                        ForEach(displayedVisibleRecords) { record in
                            VStack(alignment: .leading, spacing: 8) {
                                Button {
                                    selectedRecordID = selectedRecordID == record.id ? nil : record.id
                                } label: {
                                    HistoryRow(record: record, strings: strings, isSelected: selectedRecordID == record.id)
                                }
                                .buttonStyle(.plain)

                                if selectedRecordID == record.id {
                                    InlineStudyRecordDetail(record: record) {
                                        selectedRecordID = nil
                                    }
                                    .transition(.opacity.combined(with: .move(edge: .top)))
                                }
                            }
                            .listRowInsets(EdgeInsets(top: 5, leading: 0, bottom: 5, trailing: 8))
                            .listRowSeparator(.hidden)
                            .listRowBackground(Color.clear)
                            .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                                Button(role: .destructive) {
                                    delete(record)
                                } label: {
                                    Label(strings.clear, systemImage: "trash")
                                }
                            }
                        }
                    }
                    .listStyle(.plain)
                    .scrollContentBackground(.hidden)
                    .frame(maxHeight: .infinity)
                    .refreshable {
                        await appState.refreshVisibleData()
                    }
                    #endif

                    Divider()

                    HStack {
                        Button {
                            page = 0
                        } label: {
                            Image(systemName: "backward.end.fill")
                        }
                        .disabled(displayedPage == 0)

                        Button {
                            page = max(page - 1, 0)
                        } label: {
                            Image(systemName: "chevron.left")
                        }
                        .disabled(displayedPage == 0)

                        Spacer()

                        Text("\(displayedPage + 1) / \(displayedPageCount)")
                            .font(.caption)
                            .foregroundStyle(.secondary)

                        Spacer()

                        Button {
                            page = min(page + 1, displayedPageCount - 1)
                        } label: {
                            Image(systemName: "chevron.right")
                        }
                        .disabled(displayedPage >= displayedPageCount - 1)

                        Button {
                            page = displayedPageCount - 1
                        } label: {
                            Image(systemName: "forward.end.fill")
                        }
                        .disabled(displayedPage >= displayedPageCount - 1)
                    }
                    .buttonStyle(.borderless)
                    .padding(.bottom, 6)
                }
            }
        }
        .padding(.top, 10)
        .frame(maxHeight: .infinity, alignment: .top)
        .onChange(of: appState.studyRecords.count) {
            clampPage()
            if let openSwipeRecordID,
               !appState.studyRecords.contains(where: { $0.id == openSwipeRecordID }) {
                self.openSwipeRecordID = nil
            }
        }
        .onChange(of: searchText) {
            page = 0
            selectedRecordID = nil
            openSwipeRecordID = nil
        }
        .onChange(of: appState.focusedRecordRequest) {
            showFocusedRecord()
        }
        .onAppear {
            showFocusedRecord()
        }
    }

    private func clampPage() {
        page = min(max(page, 0), pageCount(for: filteredRecords.count) - 1)
    }

    private func sortDate(for record: StudyRecord) -> Date {
        record.answeredAt ?? record.question.createdAt
    }

    private func showFocusedRecord() {
        guard let request = appState.focusedRecordRequest,
              let index = orderedRecords.firstIndex(where: { $0.id == request.recordID }) else {
            return
        }

        searchText = ""
        page = index / pageSize
        selectedRecordID = request.recordID
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

    private func delete(_ record: StudyRecord) {
        withAnimation(.easeOut(duration: 0.22)) {
            appState.deleteStudyRecord(record)
            clampPage()
            openSwipeRecordID = nil
            if selectedRecordID == record.id {
                selectedRecordID = nil
            }
        }
    }
}

private struct HistoryRow: View {
    var record: StudyRecord
    var strings: AppStrings
    var isSelected: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 7) {
            HStack(alignment: .firstTextBaseline) {
                HStack(spacing: 6) {
                    Text(record.topic.isEmpty ? strings.studyFallback : record.topic)
                        .lineLimit(1)

                    Text("·")

                    Text(record.difficulty.displayName(language: strings.language))
                        .lineLimit(1)

                    Text("·")

                    Text(record.question.createdAt, formatter: Self.dateFormatter)
                        .lineLimit(1)
                }
                .font(.caption)
                .foregroundStyle(.secondary)

                Spacer()

                if let result = record.gradingResult {
                    Text("\(result.score)/100")
                        .font(.subheadline)
                        .fontWeight(.semibold)
                        .foregroundStyle(scoreColor(result.score))
                } else {
                    Text(strings.ungraded)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            Text(record.question.question)
                .font(.body)
                .lineLimit(2)
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(isSelected ? Color.accentColor.opacity(0.12) : Color.secondary.opacity(0.08))
        .overlay {
            RoundedRectangle(cornerRadius: 8)
                .stroke(isSelected ? Color.accentColor.opacity(0.45) : Color.clear, lineWidth: 1)
        }
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }

    private func scoreColor(_ score: Int) -> Color {
        switch score {
        case 70...100:
            .green
        case 40..<70:
            .orange
        default:
            .red
        }
    }

    private static let dateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateStyle = .short
        formatter.timeStyle = .short
        return formatter
    }()
}

private struct InlineStudyRecordDetail: View {
    var record: StudyRecord
    var onClose: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Spacer()

                Button(action: onClose) {
                    Image(systemName: "xmark")
                        .font(.caption)
                }
                .buttonStyle(.borderless)
            }

            StudyRecordDetailView(record: record)
                .frame(minHeight: 320)
        }
        .padding(12)
        .background {
            RoundedRectangle(cornerRadius: 8)
                .fill(Color.platformControlBackground)
        }
        .overlay(alignment: .topLeading) {
            Triangle()
                .fill(Color.platformControlBackground)
                .frame(width: 14, height: 8)
                .offset(x: 22, y: -7)
        }
        .overlay {
            RoundedRectangle(cornerRadius: 8)
                .stroke(Color.secondary.opacity(0.18), lineWidth: 1)
        }
    }
}

private extension Color {
    static var platformControlBackground: Color {
        #if os(macOS)
        Color(nsColor: .controlBackgroundColor)
        #else
        Color(uiColor: .secondarySystemBackground)
        #endif
    }
}

private struct Triangle: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        path.move(to: CGPoint(x: rect.midX, y: rect.minY))
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY))
        path.addLine(to: CGPoint(x: rect.minX, y: rect.maxY))
        path.closeSubpath()
        return path
    }
}
