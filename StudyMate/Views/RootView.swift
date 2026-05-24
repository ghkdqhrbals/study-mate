import SwiftUI

struct RootView: View {
    @EnvironmentObject private var appState: AppState

    var body: some View {
        let strings = appState.strings

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

private extension View {
    func contentPadding() -> some View {
        padding(.horizontal, 12)
            .padding(.top, 18)
            .padding(.bottom, 16)
    }
}
