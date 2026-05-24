import SwiftUI

struct SettingsView: View {
    @EnvironmentObject private var appState: AppState
    @State private var selection: SettingsCategory = .general

    private var visibleCategories: [SettingsCategory] {
        SettingsCategory.visible(isDebuggingEnabled: appState.isDebuggingEnabled)
    }

    var body: some View {
        let strings = appState.strings

        HStack(spacing: 0) {
            VStack(spacing: 0) {
                VStack(alignment: .leading, spacing: 2) {
                    ForEach(visibleCategories) { category in
                        Button {
                            selection = category
                        } label: {
                            HStack(spacing: 8) {
                                Text(category.title(strings: strings))
                                Spacer(minLength: 0)
                            }
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundStyle(Color.primary)
                            .padding(.horizontal, 12)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .frame(height: 32)
                            .background(selection == category ? Color.secondary.opacity(0.14) : Color.clear)
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.top, 12)

                Spacer()
            }
            .frame(width: 136)
            .background(Color(nsColor: .controlBackgroundColor))

            Divider()

            VStack(spacing: 0) {
                ScrollView {
                    VStack(alignment: .leading, spacing: 18) {
                        switch selection {
                        case .general:
                            GeneralSettingsSection()

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
                                Text(strings.checking)
                            }
                        } else if appState.hasUnsavedSettingsChanges {
                            Text(strings.save)
                        } else {
                            Text(strings.saved)
                        }
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(appState.hasUnsavedSettingsChanges ? Color.accentColor : Color.gray.opacity(0.6))
                    .keyboardShortcut(.defaultAction)
                    .disabled(appState.isValidatingAPIKey)
                }
                .padding(.horizontal, 20)
                .padding(.top, 12)
                .padding(.bottom, 20)
            }
        }
        .onChange(of: appState.isDebuggingEnabled) {
            if !appState.isDebuggingEnabled && selection == .developer {
                selection = .general
            }
        }
    }
}

private enum SettingsCategory: String, CaseIterable, Identifiable {
    case general
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

    func title(strings: AppStrings) -> String {
        switch self {
        case .general:
            strings.general
        case .secrets:
            strings.secrets
        case .study:
            strings.study
        case .records:
            strings.records
        case .developer:
            strings.developer
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

private struct GeneralSettingsSection: View {
    @EnvironmentObject private var appState: AppState

    var body: some View {
        let strings = appState.strings

        SettingsPanel(title: strings.generalSettings) {
            Picker(
                strings.appLanguage,
                selection: Binding(
                    get: { appState.settings.appLanguage },
                    set: { appState.updateAppLanguage($0) }
                )
            ) {
                ForEach(AppLanguage.allCases) { language in
                    Text(language.displayName).tag(language)
                }
            }
            .pickerStyle(.menu)

            Text(strings.appLanguageHelp)
                .font(.caption)
                .foregroundStyle(.secondary)

            Divider()

            Text(strings.notifications)
                .font(.subheadline)
                .fontWeight(.semibold)

            HStack(alignment: .firstTextBaseline) {
                Text(strings.notificationPermission)
                    .foregroundStyle(.secondary)

                Spacer()

                Text(appState.notificationPermissionState.displayName(language: appState.settings.appLanguage))
                    .fontWeight(.semibold)
            }

            HStack(spacing: 8) {
                Button {
                    Task {
                        await appState.requestNotificationPermission()
                    }
                } label: {
                    if appState.isRequestingNotificationPermission {
                        ProgressView()
                            .controlSize(.small)
                    } else {
                        Text(strings.requestNotificationPermission)
                    }
                }
                .disabled(!appState.notificationPermissionState.canRequestPermission || appState.isRequestingNotificationPermission)

                if appState.notificationPermissionState.needsSystemSettings {
                    Button {
                        appState.openSystemNotificationSettings()
                    } label: {
                        Text(strings.openNotificationSettings)
                    }
                }
            }

            Text(strings.notificationPermissionHelp)
                .font(.caption)
                .foregroundStyle(.secondary)

            Picker(
                strings.notificationSound,
                selection: Binding(
                    get: { appState.settings.notificationSound },
                    set: { appState.setNotificationSound($0) }
                )
            ) {
                ForEach(NotificationSoundOption.allCases) { sound in
                    Text(sound.displayName(language: appState.settings.appLanguage)).tag(sound)
                }
            }
            .pickerStyle(.menu)

            Text(strings.notificationSoundHelp)
                .font(.caption)
                .foregroundStyle(.secondary)

            Divider()

            Toggle(
                strings.debuggingMode,
                isOn: Binding(
                    get: { appState.isDebuggingEnabled },
                    set: { appState.setDebuggingEnabled($0) }
                )
            )

            Text(strings.debuggingHelp)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .task {
            await appState.refreshNotificationPermissionState()
        }
    }
}

private struct SecretsSettingsSection: View {
    @EnvironmentObject private var appState: AppState
    @State private var showsAPIKey = false

    var body: some View {
        let strings = appState.strings

        SettingsPanel(title: "OpenAI") {
            HStack(spacing: 8) {
                Group {
                    if showsAPIKey {
                        TextField(strings.apiKey, text: $appState.apiKey)
                    } else {
                        SecureField(strings.apiKey, text: $appState.apiKey)
                    }
                }
                .textFieldStyle(.roundedBorder)

                Button {
                    showsAPIKey.toggle()
                } label: {
                    Label(showsAPIKey ? strings.hide : strings.show, systemImage: showsAPIKey ? "eye.slash" : "eye")
                }
            }

            if let validationMessage = appState.apiKeyValidationMessage {
                Text(validationMessage)
                    .font(.caption2)
                    .foregroundStyle(.red)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Text(appState.hasUnsavedSettingsChanges ? strings.unsavedAPIKeyHelp : strings.apiKeyStorageHelp)
                .font(.caption)
                .foregroundStyle(.secondary)

            Divider()

            VStack(alignment: .leading, spacing: 8) {
                Text(strings.openAIModel)
                    .font(.caption)
                    .foregroundStyle(.secondary)

                Picker(strings.openAIModel, selection: $appState.settings.openAIModel) {
                    ForEach(OpenAIModelOption.all) { option in
                        Text(option.displayName).tag(option.id)
                    }
                }
                .labelsHidden()
                .pickerStyle(.menu)

                Text(strings.openAIModelHelp)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }
}

private struct StudySettingsSection: View {
    @EnvironmentObject private var appState: AppState

    var body: some View {
        let strings = appState.strings

        SettingsPanel(title: strings.studySettings) {
            TextField(strings.studyTopic, text: $appState.settings.topic)
                .textFieldStyle(.roundedBorder)

            Picker(strings.difficulty, selection: $appState.settings.difficulty) {
                ForEach(Difficulty.allCases) { difficulty in
                    Text(difficulty.displayName(language: appState.settings.appLanguage)).tag(difficulty)
                }
            }
            .pickerStyle(.menu)

            Stepper(
                value: $appState.settings.intervalMinutes,
                in: 1...240,
                step: 1
            ) {
                Text(strings.questionInterval(minutes: appState.settings.sanitizedIntervalMinutes))
            }

            Menu {
                ForEach(RecommendedPrompt.allCases) { prompt in
                    Button(prompt.title(language: appState.settings.appLanguage)) {
                        appState.settings.customPrompt = prompt.text(language: appState.settings.appLanguage)
                    }
                }
            } label: {
                Label(strings.recommendedPrompt, systemImage: "sparkles")
            }

            VStack(alignment: .leading, spacing: 8) {
                Text(strings.relatedPrompt)
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
        let strings = appState.strings

        SettingsPanel(title: strings.records) {
            HStack(spacing: 10) {
                Text(strings.maxRecordCount)

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

                Text(strings.countUnit)
                    .foregroundStyle(.secondary)
            }

            Text(strings.recordLimitHelp(limit: appState.settings.sanitizedMaxHistoryCount, count: appState.studyRecords.count))
                .font(.caption)
                .foregroundStyle(.secondary)

            Button(role: .destructive) {
                appState.clearStudyRecords()
            } label: {
                Label(strings.deleteRecords, systemImage: "trash")
            }
            .disabled(appState.studyRecords.isEmpty)
        }
    }
}

private struct DeveloperSettingsSection: View {
    @EnvironmentObject private var appState: AppState

    var body: some View {
        let strings = appState.strings

        SettingsPanel(title: strings.developerOptions) {
            VStack(alignment: .leading, spacing: 8) {
                Label(strings.apiStatus, systemImage: appState.hasAPIKeyError ? "exclamationmark.circle.fill" : "checkmark.circle.fill")
                    .foregroundStyle(appState.hasAPIKeyError ? .orange : .green)

                Text(appState.hasAPIKeyError ? strings.apiKeyErrorDetected : strings.apiKeyNoError)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Divider()

            HStack {
                Text(strings.logs)
                    .font(.subheadline)
                    .fontWeight(.semibold)

                Spacer()

                Button(role: .destructive) {
                    appState.clearAppLogs()
                } label: {
                    Label(strings.deleteLogs, systemImage: "trash")
                }
                .disabled(appState.appLogs.isEmpty)
            }

            Text(strings.logLimitHelp)
                .font(.caption)
                .foregroundStyle(.secondary)

            if appState.appLogs.isEmpty {
                ContentUnavailableView(
                    strings.noLogs,
                    systemImage: "doc.text.magnifyingglass",
                    description: Text(strings.noLogsDescription)
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

    func title(language: AppLanguage) -> String {
        switch language {
        case .korean:
            switch self {
            case .concept:
                return "개념 확인형"
            case .interview:
                return "면접 질문형"
            case .practical:
                return "실전 예제형"
            case .review:
                return "복습 강화형"
            }
        case .english:
            switch self {
            case .concept:
                return "Concept Check"
            case .interview:
                return "Interview Style"
            case .practical:
                return "Practical Example"
            case .review:
                return "Review Focus"
            }
        }
    }

    func text(language: AppLanguage) -> String {
        switch language {
        case .korean:
            switch self {
            case .concept:
                return "핵심 개념을 정확히 이해했는지 확인하는 짧은 질문을 내세요. 한 번에 하나의 개념만 다루세요."
            case .interview:
                return "기술 면접처럼 질문하세요. 단순 정의보다 이유, trade-off, 실제 적용 상황을 설명하게 만드세요."
            case .practical:
                return "실무 상황이나 작은 예제를 기반으로 질문하세요. 사용자가 개념을 적용해서 답하도록 만드세요."
            case .review:
                return "이전 질문과 겹치지 않게 복습 질문을 내세요. 자주 틀릴 만한 부분과 헷갈리는 차이를 확인하세요."
            }
        case .english:
            switch self {
            case .concept:
                return "Ask a short question that checks whether the core concept is understood. Cover only one concept at a time."
            case .interview:
                return "Ask like a technical interview. Make the user explain reasons, trade-offs, and practical usage, not just definitions."
            case .practical:
                return "Ask from a real work scenario or a small example. Make the user apply the concept in the answer."
            case .review:
                return "Ask a review question that does not overlap with previous questions. Check common mistakes and confusing differences."
            }
        }
    }
}
