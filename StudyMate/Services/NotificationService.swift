import Foundation
import AppKit
import SwiftUI
import UserNotifications

enum StudyNotificationAction {
    static let category = "STUDY_QUESTION_CATEGORY"
    static let reply = "STUDY_QUESTION_REPLY"
    static let ignore = "STUDY_QUESTION_IGNORE"
    static let otherAnswer = "STUDY_QUESTION_OTHER_ANSWER"
    static let questionCreatedAt = "questionCreatedAt"
}

@MainActor
final class NotificationService {
    private var previewSound: NSSound?

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

    func openSystemNotificationSettings() {
        guard let url = URL(string: "x-apple.systempreferences:com.apple.preference.notifications") else {
            return
        }

        NSWorkspace.shared.open(url)
    }

    func playPreview(sound: NotificationSoundOption) {
        previewSound?.stop()
        previewSound = nil

        switch sound {
        case .defaultSound:
            NSSound.beep()
        case .none:
            return
        case .softPing, .chime, .pop, .bell, .tap:
            guard let fileName = sound.bundledFileName else {
                NSSound.beep()
                return
            }

            let resourceName = NSString(string: fileName).deletingPathExtension
            let fileExtension = NSString(string: fileName).pathExtension

            guard let url = Bundle.main.url(forResource: resourceName, withExtension: fileExtension),
                  let sound = NSSound(contentsOf: url, byReference: false) else {
                NSSound.beep()
                return
            }

            previewSound = sound
            sound.play()
        }
    }

    func showQuestionNotification(
        question: QuestionItem,
        title: String,
        sound: NotificationSoundOption,
        language: AppLanguage
    ) async {
        guard await requestAuthorizationIfNeeded(language: language) else {
            return
        }

        let content = UNMutableNotificationContent()
        content.title = title
        content.body = question.question
        content.sound = sound.userNotificationSound
        content.categoryIdentifier = StudyNotificationAction.category
        content.userInfo = [
            StudyNotificationAction.questionCreatedAt: question.createdAt.timeIntervalSince1970
        ]

        let request = UNNotificationRequest(
            identifier: "study-question-\(question.createdAt.timeIntervalSince1970)",
            content: content,
            trigger: nil
        )

        try? await UNUserNotificationCenter.current().add(request)
    }
}

private extension NotificationSoundOption {
    var userNotificationSound: UNNotificationSound? {
        switch self {
        case .defaultSound:
            .default
        case .none:
            nil
        case .softPing, .chime, .pop, .bell, .tap:
            bundledFileName.map {
                UNNotificationSound(named: UNNotificationSoundName(rawValue: $0))
            } ?? .default
        }
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
        notification.request.content.sound == nil ? [.banner] : [.banner, .sound]
    }

    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse
    ) async {
        let actionIdentifier = response.actionIdentifier
        let replyText = (response as? UNTextInputNotificationResponse)?.userText
        let questionCreatedAt = Self.questionCreatedAt(from: response.notification.request.content.userInfo)

        await StudyNotificationDelegate.shared.handle(
            actionIdentifier: actionIdentifier,
            questionCreatedAt: questionCreatedAt,
            replyText: replyText
        )
    }

    @MainActor
    func handle(actionIdentifier: String, questionCreatedAt: TimeInterval?, replyText: String?) {
        guard let appState else {
            return
        }

        switch actionIdentifier {
        case StudyNotificationAction.ignore, UNNotificationDismissActionIdentifier:
            appState.statusMessage = "질문을 무시했습니다."

        case StudyNotificationAction.reply:
            appState.openRecordFromNotification(questionCreatedAt: questionCreatedAt, replyText: replyText)
            StudyWindowPresenter.shared.show(appState: appState)

        case StudyNotificationAction.otherAnswer:
            appState.openRecordFromNotification(questionCreatedAt: questionCreatedAt)
            appState.statusMessage = "다른 응답을 입력하세요."
            StudyWindowPresenter.shared.show(appState: appState)

        case UNNotificationDefaultActionIdentifier:
            appState.openRecordFromNotification(questionCreatedAt: questionCreatedAt)
            StudyWindowPresenter.shared.show(appState: appState)

        default:
            appState.openRecordFromNotification(questionCreatedAt: questionCreatedAt)
            StudyWindowPresenter.shared.show(appState: appState)
        }
    }

    nonisolated private static func questionCreatedAt(from userInfo: [AnyHashable: Any]) -> TimeInterval? {
        let value = userInfo[StudyNotificationAction.questionCreatedAt]

        if let timeInterval = value as? TimeInterval {
            return timeInterval
        }

        if let number = value as? NSNumber {
            return number.doubleValue
        }

        return nil
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
