import SwiftUI

struct RootView: View {
    @EnvironmentObject private var appState: AppState
    @State private var selectedTab = 0

    var body: some View {
        let strings = appState.strings

        TabView(selection: $selectedTab) {
            StudyView()
                .contentPadding()
                .tabItem {
                    Label(strings.tabStudy, systemImage: "book.fill")
                }
                .tag(0)

            SettingsView()
                .tabItem {
                    Label(strings.tabSettings, systemImage: "gearshape.fill")
                }
                .tag(1)

            HistoryView()
                .contentPadding()
                .tabItem {
                    Label(strings.tabRecords, systemImage: "clock.arrow.circlepath")
                }
                .tag(2)

            StatisticsView()
                .contentPadding()
                .tabItem {
                    Label(strings.tabStatistics, systemImage: "chart.xyaxis.line")
                }
                .tag(3)
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
