import SwiftUI
import AppKit

@main
@MainActor
struct StudyMateApp: App {
    @NSApplicationDelegateAdaptor(StudyMateAppDelegate.self) private var appDelegate
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
        MenuBarExtra {
            MenuBarMenuView()
                .environmentObject(appState)
        } label: {
            MenuBarIcon(isRunning: appState.isRunning, hasAPIKeyError: appState.hasAPIKeyError)
        }
    }
}

final class StudyMateAppDelegate: NSObject, NSApplicationDelegate {
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        false
    }
}

private struct MenuBarMenuView: View {
    @EnvironmentObject private var appState: AppState

    private let timerOptions = [1, 5, 10, 15, 30, 45, 60, 120]

    var body: some View {
        let strings = appState.strings

        StatusMenuRow(isRunning: appState.isRunning, title: strings.statusTitle(isRunning: appState.isRunning))

        if appState.hasAPIKeyError {
            Text("⚠ \(strings.invalidAPIKey)")
                .foregroundStyle(.orange)
        }

        Divider()

        Button {
            StudyWindowPresenter.shared.show(appState: appState)
        } label: {
            Label(strings.openStudy, systemImage: "book")
        }
        .keyboardShortcut("o", modifiers: .command)

        Button {
            NSApp.activate(ignoringOtherApps: true)
            NSApp.orderFrontStandardAboutPanel(options: [
                .applicationName: "StudyMate",
                .applicationVersion: "1.0",
                .credits: NSAttributedString(string: "AI teacher menu bar app")
            ])
            AppWindowFocus.bringWindowToFront(named: "About StudyMate")
        } label: {
            Label(strings.aboutStudyMate, systemImage: "info.circle")
        }

        Menu(strings.timerTitle(minutes: appState.settings.sanitizedIntervalMinutes)) {
            ForEach(timerOptions, id: \.self) { minutes in
                Button {
                    appState.setTimerInterval(minutes)
                    NSApp.activate(ignoringOtherApps: true)
                } label: {
                    if appState.settings.sanitizedIntervalMinutes == minutes {
                        Label(strings.minuteLabel(minutes), systemImage: "checkmark")
                    } else {
                        Text(strings.minuteLabel(minutes))
                    }
                }
            }
        }

        Menu("\(strings.languageMenu): \(appState.settings.appLanguage.displayName)") {
            ForEach(AppLanguage.allCases) { language in
                Button {
                    appState.setAppLanguage(language)
                    NSApp.activate(ignoringOtherApps: true)
                } label: {
                    if appState.settings.appLanguage == language {
                        Label(language.displayName, systemImage: "checkmark")
                    } else {
                        Text(language.displayName)
                    }
                }
            }
        }

        Divider()

        Button {
            appState.setRunning(!appState.isRunning)
            NSApp.activate(ignoringOtherApps: true)
        } label: {
            Text(appState.isRunning ? strings.pause : strings.resume)
        }
        .keyboardShortcut("p", modifiers: .command)

        Button {
            NSApp.terminate(nil)
        } label: {
            Text(strings.quit)
        }
        .keyboardShortcut("q", modifiers: .command)
    }
}

private struct MenuBarIcon: View {
    var isRunning: Bool
    var hasAPIKeyError: Bool

    var body: some View {
        ZStack {
            Image(systemName: isRunning ? "book.fill" : "book.closed.fill")
                .font(.system(size: 16, weight: .semibold))
                .symbolRenderingMode(.hierarchical)
                .frame(width: 22, height: 18, alignment: .center)

            if hasAPIKeyError {
                ZStack {
                    Circle()
                        .fill(Color.orange)
                    Text("!")
                        .font(.system(size: 7, weight: .black, design: .rounded))
                        .foregroundStyle(.white)
                }
                .frame(width: 10, height: 10)
                .overlay {
                    Circle()
                        .stroke(Color.black.opacity(0.7), lineWidth: 1)
                }
                .offset(x: 7, y: 4)
            }
        }
        .frame(width: 24, height: 20, alignment: .center)
        .clipped()
    }
}

private struct StatusMenuRow: View {
    var isRunning: Bool
    var title: String

    var body: some View {
        Text("● ")
            .font(.system(size: 10, weight: .semibold))
            .foregroundStyle(isRunning ? Color.green : Color.orange)
            + Text(title)
    }
}

private enum AppWindowFocus {
    static func bringWindowToFront(named title: String, attempt: Int = 0) {
        let delay = attempt == 0 ? 0.05 : 0.12

        DispatchQueue.main.asyncAfter(deadline: .now() + delay) {
            NSApp.activate(ignoringOtherApps: true)

            if let window = NSApp.windows.first(where: { $0.title == title || $0.title.contains(title) }) {
                window.level = .floating
                window.makeKeyAndOrderFront(nil)

                DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
                    window.level = .normal
                }
            } else if attempt < 4 {
                bringWindowToFront(named: title, attempt: attempt + 1)
            }
        }
    }
}
