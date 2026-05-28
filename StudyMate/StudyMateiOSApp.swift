import SwiftUI

@main
@MainActor
struct StudyMateiOSApp: App {
    @StateObject private var appState: AppState

    init() {
        let appState = AppState()
        _appState = StateObject(wrappedValue: appState)
        StudyNotificationDelegate.shared.configure(appState: appState)

        Task { @MainActor in
            await appState.start()
        }
    }

    var body: some Scene {
        WindowGroup {
            MobileRootView()
                .environmentObject(appState)
        }
    }
}
