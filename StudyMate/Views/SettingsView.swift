import SwiftUI

struct SettingsView: View {
    @EnvironmentObject private var appState: AppState
    @State private var selection: SettingsCategory = .secrets

    private var visibleCategories: [SettingsCategory] {
        SettingsCategory.visible(isDebuggingEnabled: appState.isDebuggingEnabled)
    }

    var body: some View {
        HStack(spacing: 0) {
            VStack(alignment: .leading, spacing: 6) {
                ForEach(visibleCategories) { category in
                    Button {
                        selection = category
                    } label: {
                        HStack(spacing: 8) {
                            Image(systemName: category.systemImage)
                                .frame(width: 16)
                            Text(category.title)
                            Spacer(minLength: 0)
                        }
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(selection == category ? Color.primary : Color.primary)
                        .padding(.horizontal, 10)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .frame(height: 30)
                        .background(selection == category ? Color.secondary.opacity(0.14) : Color.clear)
                        .clipShape(RoundedRectangle(cornerRadius: 6))
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                }

                Spacer()
            }
            .frame(width: 136)
            .padding(.top, 16)
            .padding(.horizontal, 10)
            .background(Color.secondary.opacity(0.06))

            Divider()

            VStack(spacing: 0) {
                ScrollView {
                    VStack(alignment: .leading, spacing: 18) {
                        switch selection {
                        case .secrets:
                            SecretsSettingsSection()

                        case .study:
                            StudySettingsSection()

                        case .records:
                            RecordsSettingsSection()

                        case .developer:
                            DeveloperSettingsSection()
                        }
                    }
                    .padding(20)
                    .frame(maxWidth: .infinity, alignment: .topLeading)
                }

                Divider()

                HStack {
                    Spacer()

                    Button {
                        Task {
                            await appState.saveSettingsAndValidateAPIKey()
                        }
                    } label: {
                        if appState.isValidatingAPIKey {
                            HStack(spacing: 6) {
                                ProgressView()
                                    .controlSize(.small)
                                Text("확인 중")
                            }
                        } else if appState.hasUnsavedSettingsChanges {
                            Text("저장")
                        } else {
                            Text("저장됨")
                        }
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(appState.hasUnsavedSettingsChanges ? Color.accentColor : Color.gray.opacity(0.6))
                    .keyboardShortcut(.defaultAction)
                    .disabled(appState.isValidatingAPIKey)
                }
                .padding(.horizontal, 20)
                .padding(.vertical, 12)
            }
        }
        .onChange(of: appState.isDebuggingEnabled) {
            if !appState.isDebuggingEnabled && selection == .developer {
                selection = .secrets
            }
        }
    }
}

private enum SettingsCategory: String, CaseIterable, Identifiable {
    case secrets
    case study
    case records
    case developer

    var id: String { rawValue }

    static func visible(isDebuggingEnabled: Bool) -> [SettingsCategory] {
        allCases.filter { category in
            category != .developer || isDebuggingEnabled
        }
    }

    var title: String {
        switch self {
        case .secrets:
            "Secrets"
        case .study:
            "Study"
        case .records:
            "Records"
        case .developer:
            "Developer"
        }
    }

    var systemImage: String {
        switch self {
        case .secrets:
            "key.fill"
        case .study:
            "book.fill"
        case .records:
            "archivebox.fill"
        case .developer:
            "ladybug.fill"
        }
    }
}

private struct SettingsPanel<Content: View>: View {
    var title: String
    @ViewBuilder var content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(title)
                .font(.headline)

            content
        }
        .frame(maxWidth: 440, alignment: .leading)
    }
}

private struct SecretsSettingsSection: View {
    @EnvironmentObject private var appState: AppState
    @State private var showsAPIKey = false

    var body: some View {
        SettingsPanel(title: "OpenAI") {
            HStack(spacing: 8) {
                Group {
                    if showsAPIKey {
                        TextField("API 키", text: $appState.apiKey)
                    } else {
                        SecureField("API 키", text: $appState.apiKey)
                    }
                }
                .textFieldStyle(.roundedBorder)

                Button {
                    showsAPIKey.toggle()
                } label: {
                    Label(showsAPIKey ? "숨기기" : "보기", systemImage: showsAPIKey ? "eye.slash" : "eye")
                }
            }

            if let validationMessage = appState.apiKeyValidationMessage {
                Text(validationMessage)
                    .font(.caption2)
                    .foregroundStyle(.red)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Text(appState.hasUnsavedSettingsChanges ? "변경사항이 있습니다. 저장해도 API 키 검증 실패 시 값은 유지됩니다." : "API 키는 앱 설정에 저장됩니다.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }
}

private struct StudySettingsSection: View {
    @EnvironmentObject private var appState: AppState

    var body: some View {
        SettingsPanel(title: "학습 설정") {
            TextField("공부할 주제", text: $appState.settings.topic)
                .textFieldStyle(.roundedBorder)

            Picker("난이도", selection: $appState.settings.difficulty) {
                ForEach(Difficulty.allCases) { difficulty in
                    Text(difficulty.displayName).tag(difficulty)
                }
            }
            .pickerStyle(.menu)

            Stepper(
                value: $appState.settings.intervalMinutes,
                in: 1...240,
                step: 1
            ) {
                Text("질문 간격: \(appState.settings.sanitizedIntervalMinutes)분")
            }

            Menu {
                ForEach(RecommendedPrompt.allCases) { prompt in
                    Button(prompt.title) {
                        appState.settings.customPrompt = prompt.text
                    }
                }
            } label: {
                Label("추천 프롬프트", systemImage: "sparkles")
            }

            VStack(alignment: .leading, spacing: 8) {
                Text("관련 프롬프트")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                TextEditor(text: $appState.settings.customPrompt)
                    .frame(minHeight: 150)
                    .padding(6)
                    .overlay {
                        RoundedRectangle(cornerRadius: 8)
                            .stroke(Color.secondary.opacity(0.24))
                    }
            }
        }
    }
}

private struct RecordsSettingsSection: View {
    @EnvironmentObject private var appState: AppState

    var body: some View {
        SettingsPanel(title: "기록") {
            HStack(spacing: 10) {
                Text("기록 최대 개수")

                TextField(
                    "100",
                    value: $appState.settings.maxHistoryCount,
                    format: .number
                )
                .textFieldStyle(.roundedBorder)
                .frame(width: 80)

                Stepper(
                    "",
                    value: $appState.settings.maxHistoryCount,
                    in: 10...500,
                    step: 10
                )
                .labelsHidden()

                Text("개")
                    .foregroundStyle(.secondary)
            }

            Text("저장 시 \(appState.settings.sanitizedMaxHistoryCount)개 범위로 정리됩니다. 현재 저장된 기록: \(appState.studyRecords.count)개")
                .font(.caption)
                .foregroundStyle(.secondary)

            Button(role: .destructive) {
                appState.clearStudyRecords()
            } label: {
                Label("기록 삭제", systemImage: "trash")
            }
            .disabled(appState.studyRecords.isEmpty)

            Divider()

            Toggle(
                "디버깅 모드",
                isOn: Binding(
                    get: { appState.isDebuggingEnabled },
                    set: { appState.setDebuggingEnabled($0) }
                )
            )

            Text("켜면 왼쪽 메뉴에 Developer 탭이 표시되고 앱 로그를 확인할 수 있습니다.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }
}

private struct DeveloperSettingsSection: View {
    @EnvironmentObject private var appState: AppState

    var body: some View {
        SettingsPanel(title: "개발자 옵션") {
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Label("API 상태", systemImage: appState.hasAPIKeyError ? "exclamationmark.circle.fill" : "checkmark.circle.fill")
                        .foregroundStyle(appState.hasAPIKeyError ? .orange : .green)

                    Spacer()

                    Button {
                        Task {
                            await appState.saveSettingsAndValidateAPIKey()
                        }
                    } label: {
                        if appState.isValidatingAPIKey {
                            ProgressView()
                                .controlSize(.small)
                        } else {
                            Label("다시 테스트", systemImage: "arrow.clockwise")
                        }
                    }
                    .disabled(appState.isValidatingAPIKey)
                }

                Text(appState.hasAPIKeyError ? "API 키 오류가 감지됐습니다." : "API 키 오류가 없습니다.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Divider()

            HStack {
                Text("로그")
                    .font(.subheadline)
                    .fontWeight(.semibold)

                Spacer()

                Button(role: .destructive) {
                    appState.clearAppLogs()
                } label: {
                    Label("로그 삭제", systemImage: "trash")
                }
                .disabled(appState.appLogs.isEmpty)
            }

            Text("최근 로그는 최대 1000개까지만 보관됩니다. 초과하면 오래된 로그부터 자동 삭제됩니다.")
                .font(.caption)
                .foregroundStyle(.secondary)

            if appState.appLogs.isEmpty {
                ContentUnavailableView(
                    "로그 없음",
                    systemImage: "doc.text.magnifyingglass",
                    description: Text("앱 이벤트와 오류가 여기에 표시됩니다.")
                )
                .frame(height: 180)
            } else {
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 8) {
                        ForEach(appState.appLogs.reversed()) { entry in
                            LogRow(entry: entry)
                        }
                    }
                }
                .frame(minHeight: 260)
            }
        }
    }
}

private struct LogRow: View {
    var entry: AppLogEntry

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 6) {
                Circle()
                    .fill(color)
                    .frame(width: 7, height: 7)

                Text(entry.level.displayName)
                    .font(.caption)
                    .fontWeight(.semibold)

                Text(entry.createdAt, formatter: Self.dateFormatter)
                    .font(.caption2)
                    .foregroundStyle(.secondary)

                Spacer()
            }

            Text(entry.message)
                .font(.caption)
                .textSelection(.enabled)
        }
        .padding(8)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.secondary.opacity(0.07))
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }

    private var color: Color {
        switch entry.level {
        case .info:
            .blue
        case .warning:
            .orange
        case .error:
            .red
        }
    }

    private static let dateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateStyle = .none
        formatter.timeStyle = .medium
        return formatter
    }()
}

private enum RecommendedPrompt: String, CaseIterable, Identifiable {
    case concept
    case interview
    case practical
    case review

    var id: String { rawValue }

    var title: String {
        switch self {
        case .concept:
            "개념 확인형"
        case .interview:
            "면접 질문형"
        case .practical:
            "실전 예제형"
        case .review:
            "복습 강화형"
        }
    }

    var text: String {
        switch self {
        case .concept:
            "핵심 개념을 정확히 이해했는지 확인하는 짧은 한국어 질문을 내세요. 한 번에 하나의 개념만 다루세요."
        case .interview:
            "기술 면접처럼 질문하세요. 단순 정의보다 이유, trade-off, 실제 적용 상황을 설명하게 만드세요."
        case .practical:
            "실무 상황이나 작은 예제를 기반으로 질문하세요. 사용자가 개념을 적용해서 답하도록 만드세요."
        case .review:
            "이전 질문과 겹치지 않게 복습 질문을 내세요. 자주 틀릴 만한 부분과 헷갈리는 차이를 확인하세요."
        }
    }
}
