import SwiftUI

struct MobileRootView: View {
    @EnvironmentObject private var appState: AppState

    var body: some View {
        let strings = appState.strings

        if !appState.hasCompletedOnboarding {
            MobileOnboardingView()
        } else {
            TabView(selection: $appState.selectedTab) {
                NavigationStack {
                    StudyView()
                        .padding(.horizontal, 16)
                        .mobileTabTitle(strings.tabStudy)
                }
                .tabItem {
                    Label(strings.tabStudy, systemImage: "book.fill")
                }
                .tag(AppTab.study)

                NavigationStack {
                    HistoryView()
                        .padding(.horizontal, 16)
                        .mobileTabTitle(strings.tabRecords)
                }
                .tabItem {
                    Label(strings.tabRecords, systemImage: "clock.arrow.circlepath")
                }
                .tag(AppTab.records)

                NavigationStack {
                    StatisticsView()
                        .padding(.horizontal, 16)
                        .mobileTabTitle(strings.tabStatistics)
                }
                .tabItem {
                    Label(strings.tabStatistics, systemImage: "chart.xyaxis.line")
                }
                .tag(AppTab.statistics)

                NavigationStack {
                    MobileSettingsView()
                        .mobileTabTitle(strings.tabSettings)
                }
                .tabItem {
                    Label(strings.tabSettings, systemImage: "gearshape.fill")
                }
                .tag(AppTab.settings)
            }
        }
    }
}

private extension View {
    @ViewBuilder
    func mobileTabTitle(_ title: String) -> some View {
        #if os(iOS)
        self
            .navigationTitle(title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbarBackground(.visible, for: .navigationBar)
        #else
        self.navigationTitle(title)
        #endif
    }
}

private struct MobileOnboardingView: View {
    @EnvironmentObject private var appState: AppState
    @State private var language: AppLanguage = .korean
    @State private var apiKey = ""
    @State private var topic = ""
    @State private var difficultyLevel = Difficulty.beginner.level
    @State private var intervalMinutes = 15
    @State private var isCompleting = false

    private var strings: AppStrings {
        AppStrings(language: language)
    }

    private var canStart: Bool {
        !topic.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && !isCompleting
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Text(strings.onboardingSubtitle)
                    Text(strings.onboardingFreeNote)
                        .fontWeight(.semibold)
                }

                Section(strings.onboardingLanguage) {
                    Picker(strings.appLanguage, selection: $language) {
                        ForEach(AppLanguage.allCases) { language in
                            Text(language.displayName).tag(language)
                        }
                    }
                    .pickerStyle(.segmented)
                }

                Section(strings.onboardingOpenAI) {
                    SecureField(strings.openAIAPIKey, text: $apiKey)
                        .textContentType(.password)
                    Text(strings.onboardingAPIKeyHelp)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Section(strings.onboardingStudySetup) {
                    TextField(strings.studyTopic, text: $topic)

                    Stepper(
                        Difficulty(level: difficultyLevel).displayName(language: language),
                        value: $difficultyLevel,
                        in: 1...10
                    )

                    Stepper(
                        strings.questionInterval(minutes: intervalMinutes),
                        value: $intervalMinutes,
                        in: 1...240
                    )
                }
            }
            .navigationTitle(strings.onboardingTitle)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button(strings.onboardingSkip) {
                        appState.skipOnboarding()
                    }
                }

                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        Task {
                            isCompleting = true
                            await appState.completeOnboarding(settings: pendingSettings, apiKey: apiKey)
                            isCompleting = false
                        }
                    } label: {
                        if isCompleting || appState.isValidatingAPIKey {
                            ProgressView()
                        } else {
                            Text(strings.onboardingStart)
                        }
                    }
                    .disabled(!canStart)
                }
            }
            .onAppear {
                language = appState.settings.appLanguage
                apiKey = appState.apiKey
                topic = appState.settings.topic
                difficultyLevel = appState.settings.difficulty.level
                intervalMinutes = appState.settings.sanitizedIntervalMinutes
            }
        }
    }

    private var pendingSettings: StudySettings {
        StudySettings(
            topic: topic.trimmingCharacters(in: .whitespacesAndNewlines),
            difficulty: Difficulty(level: difficultyLevel),
            appLanguage: language,
            language: language.studyLanguage,
            openAIModel: appState.settings.sanitizedOpenAIModel,
            notificationSound: appState.settings.notificationSound,
            customPrompt: appState.settings.customPrompt,
            intervalMinutes: intervalMinutes,
            maxHistoryCount: appState.settings.sanitizedMaxHistoryCount
        )
    }
}

private struct MobileSettingsView: View {
    @EnvironmentObject private var appState: AppState
    @State private var showsAPIKey = false

    var body: some View {
        let strings = appState.settingsEditorStrings

        Form {
            Section(strings.studySettings) {
                TextField(strings.studyTopic, text: $appState.draftSettings.topic)

                Stepper(
                    appState.draftSettings.difficulty.displayName(language: appState.draftSettings.appLanguage),
                    value: Binding(
                        get: { appState.draftSettings.difficulty.level },
                        set: { appState.draftSettings.difficulty = Difficulty(level: $0) }
                    ),
                    in: 1...10
                )

                Stepper(
                    strings.questionInterval(minutes: appState.draftSettings.sanitizedIntervalMinutes),
                    value: $appState.draftSettings.intervalMinutes,
                    in: 1...240
                )

                Menu {
                    ForEach(RecommendedPrompt.allCases) { prompt in
                        Button(prompt.title(language: appState.draftSettings.appLanguage)) {
                            appState.draftSettings.customPrompt = prompt.text(language: appState.draftSettings.appLanguage)
                        }
                    }
                } label: {
                    Label(strings.recommendedPrompt, systemImage: "sparkles")
                }

                TextEditor(text: $appState.draftSettings.customPrompt)
                    .frame(minHeight: 110)
            }

            Section("OpenAI") {
                HStack {
                    Group {
                        if showsAPIKey {
                            TextField(strings.openAIAPIKey, text: $appState.draftAPIKey)
                        } else {
                            SecureField(strings.openAIAPIKey, text: $appState.draftAPIKey)
                        }
                    }
                    .textContentType(.password)

                    Button(showsAPIKey ? strings.hide : strings.show) {
                        showsAPIKey.toggle()
                    }
                }

                Picker(strings.openAIModel, selection: $appState.draftSettings.openAIModel) {
                    ForEach(OpenAIModelOption.all) { option in
                        Text(option.displayName).tag(option.id)
                    }
                }

                if let validationMessage = appState.apiKeyValidationMessage {
                    Text(validationMessage)
                        .font(.caption)
                        .foregroundStyle(.red)
                }

                VStack(alignment: .leading, spacing: 6) {
                    Text(strings.openAIBillingHelp)
                        .font(.caption)
                        .foregroundStyle(.secondary)

                    Link(strings.openAIUsageAndCostsPage, destination: URL(string: "https://platform.openai.com/usage")!)
                    Link(strings.openAIBillingPage, destination: URL(string: "https://platform.openai.com/settings/organization/billing/overview")!)
                }
                .padding(.vertical, 2)
            }

            Section(strings.generalSettings) {
                Picker(
                    strings.appLanguage,
                    selection: Binding(
                        get: { appState.draftSettings.appLanguage },
                        set: { appState.updateDraftAppLanguage($0) }
                    )
                ) {
                    ForEach(AppLanguage.allCases) { language in
                        Text(language.displayName).tag(language)
                    }
                }

                Button {
                    appState.openSystemNotificationSettings()
                } label: {
                    Label(strings.openNotificationSettings, systemImage: "bell.badge")
                }

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

            Section(strings.records) {
                Stepper(
                    "\(strings.maxRecordCount): \(appState.draftSettings.sanitizedMaxHistoryCount)",
                    value: $appState.draftSettings.maxHistoryCount,
                    in: 10...10_000,
                    step: 100
                )

                Button(role: .destructive) {
                    appState.clearStudyRecords()
                } label: {
                    Label(strings.deleteRecords, systemImage: "trash")
                }
                .disabled(appState.studyRecords.isEmpty)
            }

            if appState.isDebuggingEnabled {
                MobileDeveloperLogsSection()
            }

            Section {
                MobileCloudSyncRow()
            }
        }
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    Task {
                        await appState.saveSettingsAndValidateAPIKey()
                    }
                } label: {
                    if appState.isValidatingAPIKey {
                        ProgressView()
                    } else {
                        Text(appState.hasUnsavedSettingsChanges ? strings.save : strings.saved)
                    }
                }
                .disabled(appState.isValidatingAPIKey)
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

private struct MobileCloudSyncRow: View {
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
            .fixedSize()

            Text(statusText(strings: strings))
                .font(.caption)
                .foregroundStyle(appState.hasCloudSyncError ? .orange : .secondary)
                .lineLimit(1)
                .minimumScaleFactor(0.75)

            Spacer(minLength: 4)

            Button {
                Task {
                    await appState.syncCloudNow()
                }
            } label: {
                Image(systemName: appState.isCloudSyncing ? "arrow.triangle.2.circlepath" : "arrow.triangle.2.circlepath")
            }
            .disabled(!appState.isCloudSyncEnabled || appState.isCloudSyncing)
            .accessibilityLabel(appState.isCloudSyncing ? strings.syncing : strings.syncNow)
        }
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

private struct MobileDeveloperLogsSection: View {
    @EnvironmentObject private var appState: AppState
    @State private var didLoadInitialLogPage = false

    var body: some View {
        let strings = appState.settingsEditorStrings

        Section(strings.developerOptions) {
            Label(
                appState.hasAPIKeyError ? strings.apiKeyErrorDetected : strings.apiKeyNoError,
                systemImage: appState.hasAPIKeyError ? "exclamationmark.circle.fill" : "checkmark.circle.fill"
            )
            .foregroundStyle(appState.hasAPIKeyError ? .orange : .green)

            HStack {
                Text(pageStatus(strings: strings))
                    .font(.caption)
                    .foregroundStyle(.secondary)

                Spacer()

                MobileLogPageButton(
                    systemImage: "chevron.left",
                    isDisabled: appState.appLogPage == 0,
                    action: appState.loadPreviousAppLogPage
                )

                Text("\(appState.appLogPage + 1)/\(appState.appLogPageCount)")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
                    .frame(minWidth: 38)

                MobileLogPageButton(
                    systemImage: "chevron.right",
                    isDisabled: appState.appLogPage >= appState.appLogPageCount - 1,
                    action: appState.loadNextAppLogPage
                )
            }

            if appState.appLogs.isEmpty {
                Text(strings.noLogsDescription)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else {
                VStack(alignment: .leading, spacing: 0) {
                    ForEach(appState.appLogs) { entry in
                        MobileLogRow(entry: entry)
                    }
                }
                .padding(.vertical, 2)
            }

            Button(role: .destructive) {
                appState.clearAppLogs()
            } label: {
                Label(strings.deleteLogs, systemImage: "trash")
            }
            .disabled(appState.appLogTotalCount == 0)

            Text(strings.logLimitHelp)
                .font(.caption)
                .foregroundStyle(.secondary)
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

private struct MobileLogPageButton: View {
    var systemImage: String
    var isDisabled: Bool
    var action: () -> Void

    var body: some View {
        Button {
            guard !isDisabled else {
                return
            }

            action()
        } label: {
            Image(systemName: systemImage)
                .font(.caption.weight(.semibold))
                .foregroundStyle(isDisabled ? .tertiary : .primary)
                .frame(width: 34, height: 30)
                .background(Color.secondary.opacity(isDisabled ? 0.04 : 0.08))
                .clipShape(RoundedRectangle(cornerRadius: 7))
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(isDisabled)
    }
}

private struct MobileLogRow: View {
    var entry: AppLogEntry

    var body: some View {
        Text(lineText)
            .font(.system(size: 10, weight: .regular, design: .monospaced))
            .foregroundStyle(color)
            .lineSpacing(0)
            .lineLimit(1)
            .truncationMode(.middle)
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
