import SwiftUI

struct RootView: View {
    @EnvironmentObject private var appState: AppState

    var body: some View {
        let strings = appState.strings

        if !appState.hasCompletedOnboarding {
            OnboardingView()
        } else {
            TabView(selection: $appState.selectedTab) {
                StudyView()
                    .contentPadding()
                    .tabItem {
                        Label(strings.tabStudy, systemImage: "book.fill")
                    }
                    .tag(AppTab.study)

                SettingsView()
                    .tabItem {
                        Label(strings.tabSettings, systemImage: "gearshape.fill")
                    }
                    .tag(AppTab.settings)

                HistoryView()
                    .contentPadding()
                    .tabItem {
                        Label(strings.tabRecords, systemImage: "clock.arrow.circlepath")
                    }
                    .tag(AppTab.records)

                StatisticsView()
                    .contentPadding()
                    .tabItem {
                        Label(strings.tabStatistics, systemImage: "chart.xyaxis.line")
                    }
                    .tag(AppTab.statistics)
            }
            .frame(maxHeight: .infinity)
        }
    }
}

private struct OnboardingView: View {
    @EnvironmentObject private var appState: AppState
    @State private var language: AppLanguage = .korean
    @State private var apiKey = ""
    @State private var showsAPIKey = false
    @State private var topic = ""
    @State private var difficultyLevel = Difficulty.beginner.level
    @State private var intervalMinutes = 15
    @State private var didSeedFields = false
    @State private var isCompleting = false

    private var strings: AppStrings {
        AppStrings(language: language)
    }

    private var canStart: Bool {
        !topic.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && !isCompleting
    }

    var body: some View {
        VStack(spacing: 0) {
            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 10) {
                    Image(systemName: "book.pages.fill")
                        .font(.system(size: 24, weight: .semibold))
                        .foregroundStyle(Color.accentColor)

                    Text(strings.onboardingTitle)
                        .font(.system(size: 24, weight: .bold))
                }

                Text(strings.onboardingSubtitle)
                    .font(.system(size: 14))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)

                Text(strings.onboardingFreeNote)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(.primary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 28)
            .padding(.top, 28)
            .padding(.bottom, 18)

            Divider()

            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    OnboardingSection(title: strings.onboardingLanguage) {
                        Picker(strings.appLanguage, selection: $language) {
                            ForEach(AppLanguage.allCases) { language in
                                Text(language.displayName).tag(language)
                            }
                        }
                        .pickerStyle(.segmented)

                        Text(strings.appLanguageHelp)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }

                    OnboardingSection(title: strings.onboardingOpenAI) {
                        HStack(spacing: 8) {
                            Group {
                                if showsAPIKey {
                                    TextField("", text: $apiKey)
                                } else {
                                    SecureField("", text: $apiKey)
                                }
                            }
                            .textFieldStyle(.roundedBorder)

                            Button(showsAPIKey ? strings.hide : strings.show) {
                                showsAPIKey.toggle()
                            }
                            .frame(width: 56)
                        }

                        Text(strings.onboardingAPIKeyHelp)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }

                    OnboardingSection(title: strings.onboardingStudySetup) {
                        LabeledContent(strings.studyTopic) {
                            TextField("", text: $topic)
                                .textFieldStyle(.roundedBorder)
                                .frame(maxWidth: 260)
                        }

                        VStack(alignment: .leading, spacing: 8) {
                            HStack {
                                Text(strings.difficulty)
                                Spacer()
                                Text(Difficulty(level: difficultyLevel).displayName(language: language))
                                    .foregroundStyle(.secondary)
                            }

                            Slider(
                                value: Binding(
                                    get: { Double(difficultyLevel) },
                                    set: { difficultyLevel = Int($0.rounded()) }
                                ),
                                in: 1...10,
                                step: 1
                            )

                            Text(strings.difficultyScaleHint)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }

                        Stepper(
                            strings.questionInterval(minutes: intervalMinutes),
                            value: $intervalMinutes,
                            in: 1...240
                        )
                    }
                }
                .padding(.horizontal, 28)
                .padding(.vertical, 22)
            }

            Divider()

            HStack(spacing: 10) {
                Button(strings.onboardingSkip) {
                    appState.skipOnboarding()
                }

                Spacer()

                Button {
                    Task {
                        isCompleting = true
                        await appState.completeOnboarding(
                            settings: pendingSettings,
                            apiKey: apiKey
                        )
                        isCompleting = false
                    }
                } label: {
                    if isCompleting || appState.isValidatingAPIKey {
                        HStack(spacing: 6) {
                            ProgressView()
                                .controlSize(.small)
                            Text(strings.checking)
                        }
                    } else {
                        Text(strings.onboardingStart)
                    }
                }
                .buttonStyle(.borderedProminent)
                .keyboardShortcut(.defaultAction)
                .disabled(!canStart)
            }
            .padding(.horizontal, 28)
            .padding(.vertical, 18)
        }
        .onAppear(perform: seedFieldsIfNeeded)
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

    private func seedFieldsIfNeeded() {
        guard !didSeedFields else {
            return
        }

        language = appState.settings.appLanguage
        apiKey = appState.apiKey
        topic = appState.settings.topic
        difficultyLevel = appState.settings.difficulty.level
        intervalMinutes = appState.settings.sanitizedIntervalMinutes
        didSeedFields = true
    }
}

private struct OnboardingSection<Content: View>: View {
    var title: String
    @ViewBuilder var content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(title)
                .font(.headline)

            content
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

private extension View {
    func contentPadding() -> some View {
        padding(.leading, 12)
            .padding(.trailing, 18)
            .padding(.top, 18)
            .padding(.bottom, 16)
    }
}
