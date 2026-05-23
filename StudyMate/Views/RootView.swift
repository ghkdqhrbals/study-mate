import SwiftUI

struct RootView: View {
    @EnvironmentObject private var appState: AppState
    @State private var selectedTab = 0

    var body: some View {
        TabView(selection: $selectedTab) {
            StudyView()
                .tabItem {
                    Label("학습", systemImage: "book.fill")
                }
                .tag(0)

            SettingsView()
                .tabItem {
                    Label("설정", systemImage: "gearshape.fill")
                }
                .tag(1)

            HistoryView()
                .tabItem {
                    Label("기록", systemImage: "clock.arrow.circlepath")
                }
                .tag(2)

            StatisticsView()
                .tabItem {
                    Label("통계", systemImage: "chart.xyaxis.line")
                }
                .tag(3)
        }
        .padding(.horizontal, 12)
        .padding(.top, 18)
        .padding(.bottom, 16)
        .frame(maxHeight: .infinity)
    }
}
