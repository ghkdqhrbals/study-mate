import SwiftUI

struct HistoryView: View {
    @EnvironmentObject private var appState: AppState
    @State private var selectedRecord: StudyRecord?
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
                            HStack(alignment: .top, spacing: 8) {
                                Button {
                                    selectedRecord = record
                                } label: {
                                    HistoryRow(record: record, strings: strings)
                                        .frame(maxWidth: .infinity, alignment: .leading)
                                }
                                .buttonStyle(.plain)
                                .frame(maxWidth: .infinity, alignment: .leading)

                                Button(role: .destructive) {
                                    appState.deleteStudyRecord(record)
                                    clampPage()
                                    if selectedRecord?.id == record.id {
                                        selectedRecord = nil
                                    }
                                } label: {
                                    Image(systemName: "trash")
                                }
                                .buttonStyle(.borderless)
                                .help(strings.deleteRecordHelp)
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
        .popover(item: $selectedRecord, arrowEdge: .trailing) { record in
            StudyRecordDetailView(record: record)
                .frame(width: 420)
                .frame(minHeight: 360)
                .padding()
        }
    }

    private func clampPage() {
        page = min(max(page, 0), pageCount - 1)
    }
}

private struct HistoryRow: View {
    var record: StudyRecord
    var strings: AppStrings

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
        .background(Color.secondary.opacity(0.08))
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
