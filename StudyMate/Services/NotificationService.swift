import Foundation
import AppKit
import SwiftUI
import UserNotifications

enum StudyNotificationAction {
    static let category = "STUDY_QUESTION_CATEGORY"
    static let reply = "STUDY_QUESTION_REPLY"
    static let ignore = "STUDY_QUESTION_IGNORE"
    static let otherAnswer = "STUDY_QUESTION_OTHER_ANSWER"
}

@MainActor
final class NotificationService {
    func requestAuthorizationIfNeeded(language: AppLanguage) async -> Bool {
        let center = UNUserNotificationCenter.current()
        StudyNotificationDelegate.shared.register(language: language)
        let settings = await center.notificationSettings()

        switch settings.authorizationStatus {
        case .authorized, .provisional:
            return true
        case .denied:
            return false
        case .notDetermined:
            do {
                return try await center.requestAuthorization(options: [.alert, .sound])
            } catch {
                return false
            }
        case .ephemeral:
            return true
        @unknown default:
            return false
        }
    }

    func showQuestionNotification(question: QuestionItem, title: String, language: AppLanguage) async {
        guard await requestAuthorizationIfNeeded(language: language) else {
            return
        }

        let content = UNMutableNotificationContent()
        content.title = title
        content.body = question.question
        content.sound = .default
        content.categoryIdentifier = StudyNotificationAction.category

        let request = UNNotificationRequest(
            identifier: "study-question-\(question.createdAt.timeIntervalSince1970)",
            content: content,
            trigger: nil
        )

        try? await UNUserNotificationCenter.current().add(request)
    }
}

final class StudyNotificationDelegate: NSObject, UNUserNotificationCenterDelegate {
    nonisolated(unsafe) static let shared = StudyNotificationDelegate()

    @MainActor
    private weak var appState: AppState?

    @MainActor
    func configure(appState: AppState) {
        self.appState = appState
        register(language: appState.settings.appLanguage)
    }

    func register(language: AppLanguage = .korean) {
        let strings = AppStrings(language: language)
        let center = UNUserNotificationCenter.current()
        center.delegate = self

        let replyAction = UNTextInputNotificationAction(
            identifier: StudyNotificationAction.reply,
            title: strings.reply,
            options: [.foreground],
            textInputButtonTitle: strings.send,
            textInputPlaceholder: strings.answerPlaceholder
        )

        let otherAnswerAction = UNNotificationAction(
            identifier: StudyNotificationAction.otherAnswer,
            title: strings.otherAnswer,
            options: [.foreground]
        )

        let ignoreAction = UNNotificationAction(
            identifier: StudyNotificationAction.ignore,
            title: strings.ignore,
            options: []
        )

        let category = UNNotificationCategory(
            identifier: StudyNotificationAction.category,
            actions: [replyAction, otherAnswerAction, ignoreAction],
            intentIdentifiers: [],
            options: [.customDismissAction]
        )

        center.setNotificationCategories([category])
    }

    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification
    ) async -> UNNotificationPresentationOptions {
        [.banner, .sound]
    }

    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse
    ) async {
        let actionIdentifier = response.actionIdentifier
        let replyText = (response as? UNTextInputNotificationResponse)?.userText

        await StudyNotificationDelegate.shared.handle(actionIdentifier: actionIdentifier, replyText: replyText)
    }

    @MainActor
    func handle(actionIdentifier: String, replyText: String?) {
        guard let appState else {
            return
        }

        switch actionIdentifier {
        case StudyNotificationAction.ignore, UNNotificationDismissActionIdentifier:
            appState.statusMessage = "질문을 무시했습니다."

        case StudyNotificationAction.reply:
            if let replyText {
                appState.updateAnswer(replyText)
                appState.statusMessage = "알림 답장을 입력했습니다. 채점 받기를 눌러 확인하세요."
            }
            StudyWindowPresenter.shared.show(appState: appState)

        case StudyNotificationAction.otherAnswer:
            appState.statusMessage = "다른 응답을 입력하세요."
            StudyWindowPresenter.shared.show(appState: appState)

        case UNNotificationDefaultActionIdentifier:
            appState.statusMessage = "알림에서 열린 질문입니다."
            StudyWindowPresenter.shared.show(appState: appState)

        default:
            StudyWindowPresenter.shared.show(appState: appState)
        }
    }
}

@MainActor
final class StudyWindowPresenter {
    static let shared = StudyWindowPresenter()

    private var window: NSWindow?

    private init() {}

    func show(appState: AppState) {
        if window == nil {
            window = NSApp.windows.first {
                $0.title == "AI Teacher" || $0.title == "AI 선생님"
            }
        }

        if window == nil {
            let rootView = RootView()
                .environmentObject(appState)
                .frame(width: 560, height: 700)

            let window = NSWindow(
                contentRect: NSRect(x: 0, y: 0, width: 560, height: 700),
                styleMask: [.titled, .closable, .miniaturizable],
                backing: .buffered,
                defer: false
            )
            window.title = "AI Teacher"
            window.isReleasedWhenClosed = false
            window.minSize = NSSize(width: 560, height: 700)
            window.maxSize = NSSize(width: 560, height: 700)
            window.contentViewController = NSHostingController(rootView: rootView)
            window.center()
            self.window = window
        }

        NSApp.activate(ignoringOtherApps: true)
        window?.level = .floating
        window?.makeKeyAndOrderFront(nil)

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) { [weak self] in
            self?.window?.level = .normal
        }
    }
}
