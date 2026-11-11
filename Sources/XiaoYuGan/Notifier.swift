import Foundation
import UserNotifications

/// Schedules the clock-in and clock-out reminders the page asks for, and routes the notification buttons back.
final class Notifier: NSObject, UNUserNotificationCenterDelegate {
    private var onAction: (@MainActor (String) -> Void)?

    func setUp(log: @escaping @MainActor (String) -> Void, onAction: @escaping @MainActor (String) -> Void) {
        self.onAction = onAction
        let center = UNUserNotificationCenter.current()
        center.delegate = self
        let clockIn = UNNotificationAction(identifier: "clockIn", title: "开始工作", options: [])
        let clockOut = UNNotificationAction(identifier: "clockOut", title: "结束工作", options: [])
        center.setNotificationCategories([
            UNNotificationCategory(identifier: "start", actions: [clockIn], intentIdentifiers: [], options: []),
            UNNotificationCategory(identifier: "end", actions: [clockOut], intentIdentifiers: [], options: []),
        ])
        center.requestAuthorization(options: [.alert, .sound]) { granted, error in
            let detail = error.map { " (\($0.localizedDescription))" } ?? ""
            Task { @MainActor in log("notifications allowed: \(granted)\(detail)") }
        }
    }

    /// Replaces every pending reminder with the list from the page: [{id, at (ms), kind, title, body}].
    func schedule(_ items: [[String: Any]]) -> Int {
        let center = UNUserNotificationCenter.current()
        center.removeAllPendingNotificationRequests()
        let now = Date()
        var count = 0
        for item in items.prefix(60) {
            guard let id = item["id"] as? String,
                  let at = (item["at"] as? NSNumber)?.doubleValue,
                  let title = item["title"] as? String else { continue }
            let date = Date(timeIntervalSince1970: at / 1000)
            guard date > now else { continue }
            let content = UNMutableNotificationContent()
            content.title = title
            content.body = item["body"] as? String ?? ""
            content.sound = .default
            content.categoryIdentifier = item["kind"] as? String ?? "start"
            let parts = Calendar.current.dateComponents([.year, .month, .day, .hour, .minute, .second], from: date)
            let trigger = UNCalendarNotificationTrigger(dateMatching: parts, repeats: false)
            center.add(UNNotificationRequest(identifier: id, content: content, trigger: trigger))
            count += 1
        }
        return count
    }

    func userNotificationCenter(_ center: UNUserNotificationCenter, willPresent notification: UNNotification,
                                withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void) {
        completionHandler([.banner, .list, .sound])
    }

    func userNotificationCenter(_ center: UNUserNotificationCenter, didReceive response: UNNotificationResponse,
                                withCompletionHandler completionHandler: @escaping () -> Void) {
        let action = response.actionIdentifier
        let handler = onAction
        Task { @MainActor in handler?(action) }
        completionHandler()
    }
}
