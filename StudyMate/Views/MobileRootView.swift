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
                        .navigationTitle(strings.tabStudy)
                }
                .tabItem {
                    Label(strings.tabStudy, systemImage: "book.fill")
                }
                .tag(AppTab.study)

                NavigationStack {
                    HistoryView()
                        .padding(.horizontal, 16)
                        .navigationTitle(strings.tabRecords)
                }
                .tabItem {
                    Label(strings.tabRecords, systemImage: "clock.arrow.circlepath")
                }
                .tag(AppTab.records)

                NavigationStack {
                    StatisticsView()
                        .padding(.horizontal, 16)
                        .navigationTitle(strings.tabStatistics)
                }
                .tabItem {
                    Label(strings.tabStatistics, systemImage: "chart.xyaxis.line")
                }
                .tag(AppTab.statistics)

                NavigationStack {
                    MobileSettingsView()
                        .navigationTitle(strings.tabSettings)
                }
                .tabItem {
                    Label(strings.tabSettings, systemImage: "gearshape.fill")
                }
                .tag(AppTab.settings)
            }
        }
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
            Section(strings.iCloudSync) {
                Toggle(
                    strings.iCloudSync,
                    isOn: Binding(
                        get: { appState.isCloudSyncEnabled },
                        set: { appState.setCloudSyncEnabled($0) }
                    )
                )

                Button {
                    Task {
                        await appState.syncCloudNow()
                    }
                } label: {
                    if appState.isCloudSyncing {
                        Label(strings.syncing, systemImage: "arrow.triangle.2.circlepath")
                    } else {
                        Label(strings.syncNow, systemImage: "arrow.triangle.2.circlepath")
                    }
                }
                .disabled(!appState.isCloudSyncEnabled || appState.isCloudSyncing)

                if let cloudLastSyncedAt = appState.cloudLastSyncedAt {
                    Text(strings.lastSyncedAt(cloudLastSyncedAt))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                if let message = appState.cloudSyncMessage {
                    Text(message)
                        .font(.caption)
                        .foregroundColor(appState.hasCloudSyncError ? .orange : .secondary)
                }

                Text(strings.iCloudSyncHelp)
                    .font(.caption)
                    .foregroundStyle(.secondary)
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

                Button {
                    Task {
                        await appState.sendTestNotification()
                    }
                } label: {
                    Label(strings.testNotification, systemImage: "paperplane")
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

                TextEditor(text: $appState.draftSettings.customPrompt)
                    .frame(minHeight: 110)
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

            Section(strings.openAIBilling) {
                Text(strings.openAIBillingHelp)
                    .font(.caption)
                    .foregroundStyle(.secondary)

                Link(strings.openAIUsageAndCostsPage, destination: URL(string: "https://platform.openai.com/usage")!)
                Link(strings.openAIBillingPage, destination: URL(string: "https://platform.openai.com/settings/organization/billing/overview")!)
            }

            if appState.isDebuggingEnabled {
                MobileDeveloperLogsSection()
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

private struct MobileDeveloperLogsSection: View {
    @EnvironmentObject private var appState: AppState

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

                Button {
                    appState.loadAppLogPage(appState.appLogPage - 1)
                } label: {
                    Image(systemName: "chevron.left")
                }
                .disabled(appState.appLogPage == 0)

                Text("\(appState.appLogPage + 1)/\(appState.appLogPageCount)")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .monospacedDigit()

                Button {
                    appState.loadAppLogPage(appState.appLogPage + 1)
                } label: {
                    Image(systemName: "chevron.right")
                }
                .disabled(appState.appLogPage >= appState.appLogPageCount - 1)
            }

            if appState.appLogs.isEmpty {
                Text(strings.noLogsDescription)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else {
                ForEach(appState.appLogs) { entry in
                    MobileLogRow(entry: entry)
                }
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
            appState.loadAppLogPage(0)
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

private struct MobileLogRow: View {
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
                .lineLimit(4)
                .truncationMode(.tail)
        }
        .padding(.vertical, 4)
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
