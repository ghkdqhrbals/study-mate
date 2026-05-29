import SwiftUI

struct SettingsView: View {
    @EnvironmentObject private var appState: AppState
    @State private var selection: SettingsCategory = .study

    private var visibleCategories: [SettingsCategory] {
        SettingsCategory.visible(isDebuggingEnabled: appState.isDebuggingEnabled)
    }

    var body: some View {
        let strings = appState.settingsEditorStrings

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
                    .padding(.leading, 20)
                    .padding(.trailing, 28)
                    .padding(.top, 20)
                    .padding(.bottom, 28)
                    .frame(maxWidth: .infinity, alignment: .topLeading)
                }

                Divider()

                HStack(spacing: 12) {
                    CompactCloudSyncFooter()

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
                selection = .study
            }
        }
        .onAppear {
            appState.beginSettingsEditing()
        }
        .onDisappear {
            appState.cancelSettingsEditing()
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
        [.study, .general, .secrets, .records, .developer].filter { category in
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

private struct CompactCloudSyncFooter: View {
    @EnvironmentObject private var appState: AppState

    var body: some View {
        let strings = appState.settingsEditorStrings

        HStack(spacing: 8) {
            Toggle(
                strings.iCloudSync,
                isOn: Binding(
                    get: { appState.isCloudSyncEnabled },
                    set: { appState.setCloudSyncEnabled($0) }
                )
            )
            .toggleStyle(.switch)
            .fixedSize()

            Text(statusText(strings: strings))
                .font(.caption)
                .foregroundStyle(appState.hasCloudSyncError ? .orange : .secondary)
                .lineLimit(1)
                .truncationMode(.tail)

            Button {
                Task {
                    await appState.syncCloudNow()
                }
            } label: {
                if appState.isCloudSyncing {
                    ProgressView()
                        .controlSize(.small)
                } else {
                    Image(systemName: "arrow.triangle.2.circlepath")
                }
            }
            .buttonStyle(.borderless)
            .disabled(!appState.isCloudSyncEnabled || appState.isCloudSyncing)
            .help(strings.syncNow)
        }
        .frame(minWidth: 260, maxWidth: 430, alignment: .leading)
    }

    private func statusText(strings: AppStrings) -> String {
        if let message = appState.cloudSyncMessage,
           !message.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return message
        }

        if let cloudLastSyncedAt = appState.cloudLastSyncedAt {
            return strings.lastSyncedAt(cloudLastSyncedAt)
        }

        return appState.isCloudSyncEnabled ? strings.iCloudSyncOn : strings.iCloudSyncOff
    }
}

private struct GeneralSettingsSection: View {
    @EnvironmentObject private var appState: AppState
    @ObservedObject private var updateService = UpdateService.shared
    @State private var showsUninstallConfirmation = false

    var body: some View {
        let strings = appState.settingsEditorStrings

        SettingsPanel(title: strings.generalSettings) {
            Picker(
                strings.appLanguage,
                selection: Binding(
                    get: { appState.draftSettings.appLanguage },
                    set: { appState.updateDraftAppLanguage($0) }
                )
            ) {
                ForEach(AppLanguage.allCases) { language in
                    Text(appState.draftSettings.appLanguage == language ? "✓ \(language.displayName)" : language.displayName)
                        .tag(language)
                }
            }
            .pickerStyle(.menu)

            Text(strings.appLanguageHelp)
                .font(.caption)
                .foregroundStyle(.secondary)

            Text(strings.notifications)
                .font(.subheadline)
                .fontWeight(.semibold)

            Button {
                appState.openSystemNotificationSettings()
            } label: {
                Label(strings.openNotificationSettings, systemImage: "bell.badge")
            }

            Text(strings.notificationPermissionHelp)
                .font(.caption)
                .foregroundStyle(.secondary)

            Picker(
                strings.notificationSound,
                selection: Binding(
                    get: { appState.draftSettings.notificationSound },
                    set: { appState.setDraftNotificationSound($0) }
                )
            ) {
                ForEach(NotificationSoundOption.allCases) { sound in
                    Text(sound.displayName(language: appState.draftSettings.appLanguage)).tag(sound)
                }
            }
            .pickerStyle(.menu)

            Text(strings.notificationSoundHelp)
                .font(.caption)
                .foregroundStyle(.secondary)

            Divider()

            Text(strings.updates)
                .font(.subheadline)
                .fontWeight(.semibold)

            if !updateService.canUseUpdates {
                Text(strings.updateInstallHelp)
                    .font(.caption)
                    .foregroundStyle(.orange)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Toggle(
                strings.automaticallyCheckForUpdates,
                isOn: Binding(
                    get: { updateService.automaticallyChecksForUpdates },
                    set: { updateService.setAutomaticallyChecksForUpdates($0) }
                )
            )
            .disabled(!updateService.canUseUpdates)

            Toggle(
                strings.automaticallyDownloadUpdates,
                isOn: Binding(
                    get: { updateService.automaticallyDownloadsUpdates },
                    set: { updateService.setAutomaticallyDownloadsUpdates($0) }
                )
            )
            .disabled(!updateService.canUseUpdates || !updateService.automaticallyChecksForUpdates)

            Button {
                updateService.checkForUpdates()
            } label: {
                Label(strings.checkForUpdates, systemImage: "arrow.triangle.2.circlepath")
            }
            .disabled(!updateService.canUseUpdates || !updateService.canCheckForUpdates)

            Text(strings.updateHelp)
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

            Divider()

            Button(role: .destructive) {
                showsUninstallConfirmation = true
            } label: {
                Label(strings.uninstall, systemImage: "trash")
            }

            Text(strings.uninstallHelp)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .confirmationDialog(
            strings.uninstallConfirmationTitle,
            isPresented: $showsUninstallConfirmation,
            titleVisibility: .visible
        ) {
            Button(strings.uninstall, role: .destructive) {
                appState.uninstallApplication()
            }
        } message: {
            Text(strings.uninstallConfirmationMessage)
        }
    }
}

private struct SecretsSettingsSection: View {
    @EnvironmentObject private var appState: AppState
    @State private var showsAPIKey = false

    var body: some View {
        let strings = appState.settingsEditorStrings

        SettingsPanel(title: "OpenAI") {
            VStack(alignment: .leading, spacing: 8) {
                Text(strings.openAIAPIKey)
                    .font(.caption)
                    .foregroundStyle(.secondary)

                HStack(spacing: 8) {
                    Group {
                        if showsAPIKey {
                            TextField(strings.openAIAPIKey, text: $appState.draftAPIKey)
                        } else {
                            SecureField(strings.openAIAPIKey, text: $appState.draftAPIKey)
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

                Text(strings.openAIAPIKeyHelp)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Text(appState.hasUnsavedSettingsChanges ? strings.unsavedAPIKeyHelp : strings.apiKeyStorageHelp)
                .font(.caption)
                .foregroundStyle(.secondary)

            Divider()

            VStack(alignment: .leading, spacing: 8) {
                Text(strings.openAIModel)
                    .font(.caption)
                    .foregroundStyle(.secondary)

                Picker(strings.openAIModel, selection: $appState.draftSettings.openAIModel) {
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

            Divider()

            VStack(alignment: .leading, spacing: 10) {
                Text(strings.openAIBilling)
                    .font(.subheadline)
                    .fontWeight(.semibold)

                Text(strings.openAIBillingHelp)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)

                HStack(spacing: 12) {
                    Button {
                        appState.openOpenAIUsageDashboardPage()
                    } label: {
                        Text(strings.openAIUsageAndCostsPage)
                            .foregroundStyle(.blue)
                    }
                    .buttonStyle(.plain)
                    .help(strings.openAIUsageAndCostsPage)

                    Button {
                        appState.openOpenAIBillingPage()
                    } label: {
                        Text(strings.openAIBillingPage)
                            .foregroundStyle(.blue)
                    }
                    .buttonStyle(.plain)
                    .help(strings.openAIBillingPage)
                }
            }
        }
    }
}

private struct StudySettingsSection: View {
    @EnvironmentObject private var appState: AppState

    var body: some View {
        let strings = appState.settingsEditorStrings

        SettingsPanel(title: strings.studySettings) {
            TextField(strings.studyTopic, text: $appState.draftSettings.topic)
                .textFieldStyle(.roundedBorder)

            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Text(strings.difficulty)
                    Spacer()
                    Stepper(
                        value: Binding(
                            get: { appState.draftSettings.difficulty.level },
                            set: { appState.draftSettings.difficulty = Difficulty(level: $0) }
                        ),
                        in: 1...10
                    ) {
                        Text(appState.draftSettings.difficulty.displayName(language: appState.draftSettings.appLanguage))
                            .fontWeight(.semibold)
                            .monospacedDigit()
                    }
                }

                Slider(
                    value: Binding(
                        get: { Double(appState.draftSettings.difficulty.level) },
                        set: { appState.draftSettings.difficulty = Difficulty(level: Int($0.rounded())) }
                    ),
                    in: 1...10,
                    step: 1
                )

                HStack {
                    Text("1")
                    Spacer()
                    Text("10")
                }
                .font(.caption2)
                .foregroundStyle(.secondary)

                Text(strings.difficultyScaleHint)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Stepper(
                value: $appState.draftSettings.intervalMinutes,
                in: 1...240,
                step: 1
            ) {
                Text(strings.questionInterval(minutes: appState.draftSettings.sanitizedIntervalMinutes))
            }

            Menu {
                ForEach(RecommendedPrompt.allCases) { prompt in
                    Button(prompt.title(language: appState.draftSettings.appLanguage)) {
                        appState.draftSettings.customPrompt = prompt.text(language: appState.draftSettings.appLanguage)
                    }
                }
            } label: {
                Label(strings.recommendedPrompt, systemImage: "sparkles")
            }

            VStack(alignment: .leading, spacing: 8) {
                Text(strings.relatedPrompt)
                    .font(.caption)
                    .foregroundStyle(.secondary)

                TextEditor(text: $appState.draftSettings.customPrompt)
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
    @State private var showsDeleteConfirmation = false

    var body: some View {
        let strings = appState.settingsEditorStrings

        SettingsPanel(title: strings.records) {
            HStack(spacing: 10) {
                Text(strings.maxRecordCount)

                TextField(
                    "100",
                    value: $appState.draftSettings.maxHistoryCount,
                    format: .number
                )
                .textFieldStyle(.roundedBorder)
                .frame(width: 80)

                Stepper(
                    "",
                    value: $appState.draftSettings.maxHistoryCount,
                    in: 10...10_000,
                    step: 100
                )
                .labelsHidden()

                Text(strings.countUnit)
                    .foregroundStyle(.secondary)
            }

            Text(strings.recordLimitHelp(limit: appState.draftSettings.sanitizedMaxHistoryCount, count: appState.studyRecords.count))
                .font(.caption)
                .foregroundStyle(.secondary)

            Divider()

            Button(role: .destructive) {
                showsDeleteConfirmation = true
            } label: {
                Label(strings.deleteRecords, systemImage: "trash")
            }
            .disabled(appState.studyRecords.isEmpty)

            Text(strings.deleteRecordsHelp)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .confirmationDialog(strings.deleteRecords, isPresented: $showsDeleteConfirmation) {
            Button(strings.deleteRecords, role: .destructive) {
                appState.clearStudyRecords()
            }
        }
    }
}

private struct DeveloperSettingsSection: View {
    @EnvironmentObject private var appState: AppState
    @State private var didLoadInitialLogPage = false

    var body: some View {
        let strings = appState.settingsEditorStrings
        let visibleLogs = appState.appLogs

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
                Text("\(strings.logs) · \(pageStatus(strings: strings))")
                    .font(.subheadline)
                    .fontWeight(.semibold)

                Spacer()

                if appState.appLogPageCount > 1 {
                    HStack(spacing: 6) {
                        Button(action: appState.loadPreviousAppLogPage) {
                            Image(systemName: "chevron.left")
                        }
                        .buttonStyle(.borderless)
                        .disabled(appState.appLogPage == 0)
                        .help(strings.previousPage)

                        Text("\(appState.appLogPage + 1)/\(appState.appLogPageCount)")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                            .monospacedDigit()
                            .lineLimit(1)

                        Button(action: appState.loadNextAppLogPage) {
                            Image(systemName: "chevron.right")
                        }
                        .buttonStyle(.borderless)
                        .disabled(appState.appLogPage >= appState.appLogPageCount - 1)
                        .help(strings.nextPage)
                    }
                }

                Button(role: .destructive) {
                    appState.clearAppLogs()
                } label: {
                    Label(strings.deleteLogs, systemImage: "trash")
                }
                .disabled(appState.appLogTotalCount == 0)
            }

            Text(strings.logLimitHelp)
                .font(.caption)
                .foregroundStyle(.secondary)

            if visibleLogs.isEmpty {
                ContentUnavailableView(
                    strings.noLogs,
                    systemImage: "doc.text.magnifyingglass",
                    description: Text(strings.noLogsDescription)
                )
                .frame(height: 180)
            } else {
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 0) {
                        ForEach(visibleLogs) { entry in
                            LogRow(entry: entry)
                        }
                    }
                    .padding(.vertical, 5)
                    .padding(.horizontal, 7)
                }
                .background(Color.secondary.opacity(0.045))
                .clipShape(RoundedRectangle(cornerRadius: 6))
                .frame(height: 320)
            }
        }
        .onAppear {
            guard !didLoadInitialLogPage else {
                return
            }

            didLoadInitialLogPage = true
            appState.loadAppLogPage(appState.appLogPage)
        }
    }

    private func pageStatus(strings: AppStrings) -> String {
        guard appState.appLogTotalCount > 0 else {
            return strings.itemCount(0)
        }

        return strings.topicPageStatus(
            start: appState.appLogPageStart,
            end: appState.appLogPageEnd,
            total: appState.appLogTotalCount
        )
    }
}

private struct LogRow: View {
    var entry: AppLogEntry

    var body: some View {
        Text(lineText)
            .font(.system(size: 10.5, weight: .regular, design: .monospaced))
            .foregroundStyle(color)
            .lineSpacing(0)
            .lineLimit(1)
            .truncationMode(.middle)
            .textSelection(.enabled)
            .help(entry.message)
            .padding(.vertical, 1)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var lineText: String {
        "\(Self.dateFormatter.string(from: entry.createdAt)) \(entry.level.displayName.uppercased()) \(entry.message)"
    }

    private var color: Color {
        switch entry.level {
        case .info:
            .primary
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
