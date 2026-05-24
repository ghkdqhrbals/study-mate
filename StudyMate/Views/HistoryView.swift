import SwiftUI

struct HistoryView: View {
    @EnvironmentObject private var appState: AppState
    @State private var selectedRecordID: String?
    @State private var page = 0

    private let pageSize = 10

    private var orderedRecords: [StudyRecord] {
        Array(appState.studyRecords.reversed())
    }

    private var pageCount: Int {
        max(Int(ceil(Double(orderedRecords.count) / Double(pageSize))), 1)
    }

    private var visibleRecords: [StudyRecord] {
        let clampedPage = min(max(page, 0), pageCount - 1)
        let start = clampedPage * pageSize
        let end = min(start + pageSize, orderedRecords.count)

        guard start < end else {
            return []
        }

        return Array(orderedRecords[start..<end])
    }

    var body: some View {
        let strings = appState.strings

        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text(strings.records)
                    .font(.headline)

                Spacer()

                if !appState.studyRecords.isEmpty {
                    Text(strings.itemCount(appState.studyRecords.count))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            if appState.studyRecords.isEmpty {
                ContentUnavailableView(
                    strings.noRecords,
                    systemImage: "clock.arrow.circlepath",
                    description: Text(strings.noRecordsDescription)
                )
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 10) {
                        ForEach(visibleRecords) { record in
                            VStack(alignment: .leading, spacing: 8) {
                                SwipeToDeleteHistoryRow(
                                    strings: strings,
                                    onDelete: {
                                        delete(record)
                                    },
                                    onSelect: {
                                        selectedRecordID = selectedRecordID == record.id ? nil : record.id
                                    }
                                ) {
                                    HistoryRow(record: record, strings: strings, isSelected: selectedRecordID == record.id)
                                }

                                if selectedRecordID == record.id {
                                    InlineStudyRecordDetail(record: record) {
                                        selectedRecordID = nil
                                    }
                                    .transition(.opacity.combined(with: .move(edge: .top)))
                                }
                            }
                        }
                    }
                    .padding(.bottom, 12)
                }
                .frame(maxHeight: .infinity)

                Divider()

                HStack {
                    Button {
                        page = 0
                    } label: {
                        Image(systemName: "backward.end.fill")
                    }
                    .disabled(page == 0)

                    Button {
                        page = max(page - 1, 0)
                    } label: {
                        Image(systemName: "chevron.left")
                    }
                    .disabled(page == 0)

                    Spacer()

                    Text("\(min(page + 1, pageCount)) / \(pageCount)")
                        .font(.caption)
                        .foregroundStyle(.secondary)

                    Spacer()

                    Button {
                        page = min(page + 1, pageCount - 1)
                    } label: {
                        Image(systemName: "chevron.right")
                    }
                    .disabled(page >= pageCount - 1)

                    Button {
                        page = pageCount - 1
                    } label: {
                        Image(systemName: "forward.end.fill")
                    }
                    .disabled(page >= pageCount - 1)
                }
                .buttonStyle(.borderless)
                .padding(.bottom, 6)
            }
        }
        .padding(.top, 10)
        .frame(maxHeight: .infinity, alignment: .top)
        .onChange(of: appState.studyRecords.count) {
            clampPage()
        }
        .onChange(of: appState.focusedRecordRequest) {
            showFocusedRecord()
        }
        .onAppear {
            showFocusedRecord()
        }
    }

    private func clampPage() {
        page = min(max(page, 0), pageCount - 1)
    }

    private func showFocusedRecord() {
        guard let request = appState.focusedRecordRequest,
              let index = orderedRecords.firstIndex(where: { $0.id == request.recordID }) else {
            return
        }

        page = index / pageSize
        selectedRecordID = request.recordID
    }

    private func delete(_ record: StudyRecord) {
        appState.deleteStudyRecord(record)
        clampPage()
        if selectedRecordID == record.id {
            selectedRecordID = nil
        }
    }
}

private struct SwipeToDeleteHistoryRow<Content: View>: View {
    var strings: AppStrings
    var onDelete: () -> Void
    var onSelect: () -> Void
    var content: () -> Content

    @GestureState private var dragTranslation: CGFloat = 0
    @State private var restingOffset: CGFloat = 0

    init(
        strings: AppStrings,
        onDelete: @escaping () -> Void,
        onSelect: @escaping () -> Void,
        @ViewBuilder content: @escaping () -> Content
    ) {
        self.strings = strings
        self.onDelete = onDelete
        self.onSelect = onSelect
        self.content = content
    }

    private let actionWidth: CGFloat = 88

    private var effectiveOffset: CGFloat {
        min(0, max(-actionWidth, restingOffset + dragTranslation))
    }

    private var revealProgress: Double {
        min(1, max(0, Double(-effectiveOffset / actionWidth)))
    }

    var body: some View {
        ZStack(alignment: .trailing) {
            Button(role: .destructive) {
                withAnimation(.snappy) {
                    restingOffset = 0
                }
                onDelete()
            } label: {
                VStack(spacing: 4) {
                    Image(systemName: "trash")
                    Text(strings.clear)
                        .font(.caption2)
                }
                .frame(width: actionWidth)
                .frame(maxHeight: .infinity)
                .foregroundStyle(.white)
                .background(Color.red)
                .clipShape(TrailingRoundedRectangle(radius: 8))
            }
            .buttonStyle(.plain)
            .opacity(revealProgress)
            .allowsHitTesting(revealProgress > 0.95)
            .zIndex(3)

            content()
                .frame(maxWidth: .infinity, alignment: .leading)
                .offset(x: effectiveOffset)
                .contentShape(Rectangle())
                .allowsHitTesting(restingOffset == 0)
                .onTapGesture {
                    if restingOffset < 0 {
                        withAnimation(.snappy) {
                            restingOffset = 0
                        }
                    } else {
                        onSelect()
                    }
                }
                .simultaneousGesture(
                    DragGesture(minimumDistance: 12)
                        .updating($dragTranslation) { value, state, _ in
                            guard abs(value.translation.width) > abs(value.translation.height) else {
                                return
                            }
                            state = value.translation.width
                        }
                        .onEnded { value in
                            guard abs(value.translation.width) > abs(value.translation.height) else {
                                return
                            }

                            let proposedOffset = restingOffset + value.translation.width
                            withAnimation(.snappy) {
                                restingOffset = proposedOffset < -actionWidth * 0.45 ? -actionWidth : 0
                            }
                        }
                )
                .zIndex(1)

            if restingOffset < 0 {
                HStack(spacing: 0) {
                    Color.clear
                        .contentShape(Rectangle())
                        .onTapGesture {
                            withAnimation(.snappy) {
                                restingOffset = 0
                            }
                        }

                    Color.clear
                        .frame(width: actionWidth)
                        .allowsHitTesting(false)
                }
                .zIndex(2)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .clipped()
    }
}

private struct TrailingRoundedRectangle: Shape {
    var radius: CGFloat

    func path(in rect: CGRect) -> Path {
        let radius = min(radius, rect.width / 2, rect.height / 2)

        var path = Path()
        path.move(to: CGPoint(x: rect.minX, y: rect.minY))
        path.addLine(to: CGPoint(x: rect.maxX - radius, y: rect.minY))
        path.addQuadCurve(
            to: CGPoint(x: rect.maxX, y: rect.minY + radius),
            control: CGPoint(x: rect.maxX, y: rect.minY)
        )
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY - radius))
        path.addQuadCurve(
            to: CGPoint(x: rect.maxX - radius, y: rect.maxY),
            control: CGPoint(x: rect.maxX, y: rect.maxY)
        )
        path.addLine(to: CGPoint(x: rect.minX, y: rect.maxY))
        path.closeSubpath()
        return path
    }
}

private struct HistoryRow: View {
    var record: StudyRecord
    var strings: AppStrings
    var isSelected: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .firstTextBaseline) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(record.topic.isEmpty ? strings.studyFallback : record.topic)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Text(record.question.createdAt, formatter: Self.dateFormatter)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }

                Spacer()

                if let result = record.gradingResult {
                    Text("\(result.score)/100")
                        .font(.headline)
                        .foregroundStyle(scoreColor(result.score))
                } else {
                    Text(strings.ungraded)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            Text(record.question.question)
                .font(.body)

            if let answer = record.answer, !answer.isEmpty {
                Text(strings.answerPrefix(answer))
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }

            if let result = record.gradingResult {
                Text(result.feedback)
                    .font(.footnote)
                Text(result.explanation)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
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
                .fill(Color(nsColor: .controlBackgroundColor))
        }
        .overlay(alignment: .topLeading) {
            Triangle()
                .fill(Color(nsColor: .controlBackgroundColor))
                .frame(width: 14, height: 8)
                .offset(x: 22, y: -7)
        }
        .overlay {
            RoundedRectangle(cornerRadius: 8)
                .stroke(Color.secondary.opacity(0.18), lineWidth: 1)
        }
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
