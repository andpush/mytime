import Foundation
import UserNotifications
import AppKit

final class NotificationManager: NSObject, UNUserNotificationCenterDelegate {
    static let shared = NotificationManager()

    private(set) var authorized: Bool = false
    var onResumeTapped: (() -> Void)?
    var onStopTapped: (() -> Void)?
    var onAuthorizationChanged: ((Bool) -> Void)?

    private override init() {
        super.init()
    }

    func configure() {
        let center = UNUserNotificationCenter.current()
        center.delegate = self

        let resume = UNNotificationAction(identifier: "ACT_RESUME", title: "Back to work (Resume)", options: [.foreground])
        let stop = UNNotificationAction(identifier: "ACT_STOP", title: "Stop timer", options: [.destructive])
        let pauseCat = UNNotificationCategory(identifier: "CAT_PAUSE",
                                              actions: [resume, stop],
                                              intentIdentifiers: [],
                                              options: [])
        let remindCat = UNNotificationCategory(identifier: "CAT_REMIND",
                                               actions: [],
                                               intentIdentifiers: [],
                                               options: [])
        let pomodoroCat = UNNotificationCategory(identifier: "CAT_POMODORO",
                                                 actions: [],
                                                 intentIdentifiers: [],
                                                 options: [])
        center.setNotificationCategories([pauseCat, remindCat, pomodoroCat])

        center.getNotificationSettings { settings in
            DispatchQueue.main.async {
                self.authorized = (settings.authorizationStatus == .authorized || settings.authorizationStatus == .provisional)
                self.onAuthorizationChanged?(self.authorized)
            }
        }
    }

    func requestAuthorization() {
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound]) { granted, _ in
            DispatchQueue.main.async {
                self.authorized = granted
                self.onAuthorizationChanged?(granted)
            }
        }
    }

    func refreshAuthorization() {
        UNUserNotificationCenter.current().getNotificationSettings { settings in
            DispatchQueue.main.async {
                let newValue = (settings.authorizationStatus == .authorized || settings.authorizationStatus == .provisional)
                if newValue != self.authorized {
                    self.authorized = newValue
                    self.onAuthorizationChanged?(newValue)
                }
            }
        }
    }

    func openSystemNotificationSettings() {
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.notifications") {
            NSWorkspace.shared.open(url)
        }
    }

    // MARK: - Posting

    func postRemind() {
        let c = UNMutableNotificationContent()
        c.title = "MyTime"
        c.body = "Start tracking your time!"
        c.categoryIdentifier = "CAT_REMIND"
        post(id: "remind", content: c)
    }

    func postAutoPause(reason: PauseReason, client: String, activity: String) {
        let c = UNMutableNotificationContent()
        c.title = "MyTime"
        let suffix = activity.isEmpty ? client : "\(client) - \(activity)"
        switch reason {
        case .idle(let min):
            c.body = "Time tracking has been paused, because you were idle for \(min) min."
        case .sleep:
            c.body = "Time tracking has been paused because the computer went asleep."
        case .manual:
            c.body = "Time tracking paused."
        }
        c.subtitle = "Resume or stop \(suffix)"
        c.categoryIdentifier = "CAT_PAUSE"
        post(id: "pause", content: c)
    }

    func postPomodoroFinished(client: String, activity: String) {
        let c = UNMutableNotificationContent()
        c.title = "MyTime"
        let suffix = activity.isEmpty ? client : "\(client) - \(activity)"
        c.body = "Pomodoro finished. Stopped \(suffix)."
        c.categoryIdentifier = "CAT_POMODORO"
        post(id: "pomodoro", content: c)
    }

    private func post(id: String, content: UNMutableNotificationContent) {
        guard authorized else { return }
        content.sound = .default
        let req = UNNotificationRequest(identifier: id + "-" + UUID().uuidString,
                                        content: content, trigger: nil)
        UNUserNotificationCenter.current().add(req, withCompletionHandler: nil)
    }

    // MARK: - Delegate

    func userNotificationCenter(_ center: UNUserNotificationCenter,
                                willPresent notification: UNNotification,
                                withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void) {
        completionHandler([.banner, .sound])
    }

    func userNotificationCenter(_ center: UNUserNotificationCenter,
                                didReceive response: UNNotificationResponse,
                                withCompletionHandler completionHandler: @escaping () -> Void) {
        switch response.actionIdentifier {
        case "ACT_RESUME":
            DispatchQueue.main.async { self.onResumeTapped?() }
        case "ACT_STOP":
            DispatchQueue.main.async { self.onStopTapped?() }
        default:
            break
        }
        completionHandler()
    }
}
