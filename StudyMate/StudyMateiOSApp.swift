import SwiftUI
import UIKit
import BackgroundTasks

@main
@MainActor
struct StudyMateiOSApp: App {
    @UIApplicationDelegateAdaptor(StudyMateiOSAppDelegate.self) private var appDelegate
    @Environment(\.scenePhase) private var scenePhase
    @StateObject private var appState: AppState

    init() {
        let appState = AppState()
        _appState = StateObject(wrappedValue: appState)
        StudyNotificationDelegate.shared.configure(appState: appState)
        StudyRemoteNotificationBridge.shared.configure(appState: appState)
        StudyMateBackgroundRefreshBridge.shared.configure(appState: appState)
        StudyMateBackgroundRefreshBridge.shared.register()

        Task { @MainActor in
            await appState.start()
        }
    }

    var body: some Scene {
        WindowGroup {
            MobileRootView()
                .environmentObject(appState)
        }
        .onChange(of: scenePhase) { _, phase in
            switch phase {
            case .active:
                Task {
                    StudyNotificationDelegate.shared.processPendingLocalResponsesIfActive()
                    StudyRemoteNotificationBridge.shared.processPendingNotificationsIfActive()
                    await appState.handleAppBecameActive()
                    StudyNotificationDelegate.shared.processPendingLocalResponsesIfActive()
                    StudyRemoteNotificationBridge.shared.processPendingNotificationsIfActive()
                }
            case .background:
                StudyMateBackgroundRefreshBridge.shared.schedule()
                Task {
                    await appState.prepareBackgroundQuestionNotifications()
                }
            case .inactive:
                break
            @unknown default:
                break
            }
        }
    }
}

final class StudyMateiOSAppDelegate: NSObject, UIApplicationDelegate {
    func application(
        _ application: UIApplication,
        didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil
    ) -> Bool {
        StudyNotificationDelegate.shared.register()
        return true
    }

    func application(
        _ application: UIApplication,
        didRegisterForRemoteNotificationsWithDeviceToken deviceToken: Data
    ) {
        Task { @MainActor in
            StudyRemoteNotificationBridge.shared.didRegisterForRemoteNotifications(deviceToken: deviceToken)
        }
    }

    func application(
        _ application: UIApplication,
        didFailToRegisterForRemoteNotificationsWithError error: Error
    ) {
        Task { @MainActor in
            StudyRemoteNotificationBridge.shared.didFailToRegisterForRemoteNotifications(error: error)
        }
    }

    func application(
        _ application: UIApplication,
        didReceiveRemoteNotification userInfo: [AnyHashable: Any],
        fetchCompletionHandler completionHandler: @escaping (UIBackgroundFetchResult) -> Void
    ) {
        Task { @MainActor in
            let didUpdate = await StudyRemoteNotificationBridge.shared.handleRemoteNotification(
                userInfo: userInfo,
                openStudy: false
            )
            completionHandler(didUpdate ? .newData : .noData)
        }
    }

    func applicationDidEnterBackground(_ application: UIApplication) {
        StudyMateBackgroundRefreshBridge.shared.schedule()
    }
}

@MainActor
final class StudyMateBackgroundRefreshBridge {
    static let shared = StudyMateBackgroundRefreshBridge()
    static let identifier = "io.github.ghkdqhrbals.StudyMate.refresh"

    private weak var appState: AppState?
    private var didRegister = false

    private init() {}

    func configure(appState: AppState) {
        self.appState = appState
    }

    func register() {
        guard !didRegister else {
            return
        }

        didRegister = true
        BGTaskScheduler.shared.register(
            forTaskWithIdentifier: Self.identifier,
            using: nil
        ) { task in
            guard let refreshTask = task as? BGAppRefreshTask else {
                task.setTaskCompleted(success: false)
                return
            }

            Task { @MainActor in
                await self.handle(task: refreshTask)
            }
        }
    }

    func schedule() {
        let request = BGAppRefreshTaskRequest(identifier: Self.identifier)
        let minimumWakeUpDate = Date(timeIntervalSinceNow: 60)
        let requestedWakeUpDate = appState?.backgroundRefreshEarliestBeginDate() ?? Date(timeIntervalSinceNow: 15 * 60)
        request.earliestBeginDate = max(minimumWakeUpDate, requestedWakeUpDate)

        do {
            try BGTaskScheduler.shared.submit(request)
            appState?.logRemoteNotificationEvent("iPhone background refresh를 예약했습니다: \(request.earliestBeginDate?.description ?? "-")")
        } catch {
            appState?.logRemoteNotificationEvent(
                "iPhone background refresh 예약 실패: \(error.localizedDescription)",
                isWarning: true
            )
        }
    }

    private func handle(task: BGAppRefreshTask) async {
        schedule()

        let worker = Task { @MainActor in
            await appState?.handleBackgroundRefresh() ?? false
        }

        task.expirationHandler = {
            worker.cancel()
        }

        let didUpdate = await worker.value
        task.setTaskCompleted(success: didUpdate)
    }
}
