import Foundation
import UserNotifications

final class NotificationManager: NSObject, UNUserNotificationCenterDelegate {
    static let shared = NotificationManager()

    private override init() {
        super.init()
        UNUserNotificationCenter.current().delegate = self
        registerCategories()
    }

    func requestPermission() {
        UNUserNotificationCenter.current().requestAuthorization(
            options: [.alert, .sound, .badge]
        ) { _, _ in }
    }

    private func registerCategories() {
        let ids = ["DETECTION", "RECORDING_START", "RECORDING_STOP",
                   "TRANSFER_COMPLETE", "ENCLOSURE_WARNING"]
        let categories = Set(ids.map {
            UNNotificationCategory(identifier: $0, actions: [], intentIdentifiers: [])
        })
        UNUserNotificationCenter.current().setNotificationCategories(categories)
    }

    func scheduleSimulatedDetection(deploymentName: String, positionName: String) {
        let content = UNMutableNotificationContent()
        content.title = "DEER DETECTED"
        content.body = "Recording started — \(deploymentName) · \(positionName)"
        content.categoryIdentifier = "DETECTION"
        content.sound = .default
        let trigger = UNTimeIntervalNotificationTrigger(timeInterval: 30, repeats: false)
        let request = UNNotificationRequest(
            identifier: "sim.detection.\(UUID().uuidString)",
            content: content,
            trigger: trigger
        )
        UNUserNotificationCenter.current().add(request)
    }

    func schedule(title: String, body: String, category: String, delay: TimeInterval = 1) {
        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        content.categoryIdentifier = category
        content.sound = .default
        let trigger = UNTimeIntervalNotificationTrigger(timeInterval: max(1, delay), repeats: false)
        let request = UNNotificationRequest(identifier: UUID().uuidString, content: content, trigger: trigger)
        UNUserNotificationCenter.current().add(request)
    }

    // Show notifications while app is in foreground
    func userNotificationCenter(_ center: UNUserNotificationCenter,
                                 willPresent notification: UNNotification,
                                 withCompletionHandler handler: @escaping (UNNotificationPresentationOptions) -> Void) {
        handler([.banner, .sound])
    }
}
