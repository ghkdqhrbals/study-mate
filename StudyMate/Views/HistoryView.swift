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

                Button {
                    appState.clearStudyRecords()
                    page = 0
                } label: {
                    Label(strings.clear, systemImage: "trash")
                }
                .disabled(appState.studyRecords.isEmpty)
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
                                HStack(alignment: .top, spacing: 8) {
                                    Button {
                                        selectedRecordID = selectedRecordID == record.id ? nil : record.id
                                    } label: {
                                        HistoryRow(record: record, strings: strings, isSelected: selectedRecordID == record.id)
                                            .frame(maxWidth: .infinity, alignment: .leading)
                                    }
                                    .buttonStyle(.plain)
                                    .frame(maxWidth: .infinity, alignment: .leading)

                                    Button(role: .destructive) {
                                        appState.deleteStudyRecord(record)
                                        clampPage()
                                        if selectedRecordID == record.id {
                                            selectedRecordID = nil
                                        }
                                    } label: {
                                        Image(systemName: "trash")
                                    }
                                    .buttonStyle(.borderless)
                                    .help(strings.deleteRecordHelp)
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
                .textSelection(.enabled)

            if let answer = record.answer, !answer.isEmpty {
                Text(strings.answerPrefix(answer))
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .textSelection(.enabled)
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
