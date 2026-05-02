import Foundation
import UserNotifications

actor NotificationPoller {
    static let shared = NotificationPoller()
    private init() {}

    private var windowStart: Date = .distantPast
    private var surfacedInWindow: Int = 0

    private struct NotificationsResponse: Decodable {
        let notifications: [NotificationItem]
    }

    private struct NotificationItem: Decodable {
        let id: String
        let type: String
        let title: String
        let body: String
    }

    func pollAndSurface() async {
        let settings = AppSettings.shared
        guard settings.pushNotificationsEnabled,
              !settings.piServerURL.isEmpty,
              let url = URL(string: settings.piServerURL + "/notifications/unread") else { return }

        var req = URLRequest(url: url)
        req.timeoutInterval = 4
        guard let (data, _) = try? await URLSession.shared.data(for: req),
              let resp = try? JSONDecoder().decode(NotificationsResponse.self, from: data),
              !resp.notifications.isEmpty else { return }

        let all = resp.notifications
        let allIds = all.map { $0.id }

        // Client-side category filter — Pi sends everything; iOS decides what to surface
        let filtered = all.filter { n in
            switch n.type {
            case "recording.started", "recording.stopped", "still.captured":
                return settings.notifyRecording
            case "detection.animal":
                return settings.notifyDetections
            case "deployment.opened", "deployment.closed":
                return settings.notifyDeployments
            default:
                return true
            }
        }

        // Rate limit: max 3 notifications per 10-second window.
        // If queue is large (app was offline), surface newest 3 and silently mark rest read.
        let now = Date()
        if now.timeIntervalSince(windowStart) >= 10 {
            surfacedInWindow = 0
            windowStart = now
        }
        let remaining = max(0, 3 - surfacedInWindow)
        let toSurface = Array(filtered.prefix(remaining))

        for n in toSurface {
            let content = UNMutableNotificationContent()
            content.title = n.title
            content.body = n.body
            content.sound = .default
            let trigger = UNTimeIntervalNotificationTrigger(timeInterval: 1, repeats: false)
            let request = UNNotificationRequest(identifier: n.id, content: content, trigger: trigger)
            try? await UNUserNotificationCenter.current().add(request)
            surfacedInWindow += 1
        }

        // Mark ALL unread as read regardless of filter/rate-limit — keeps queue clean
        await markRead(ids: allIds)
    }

    private func markRead(ids: [String]) async {
        let base = AppSettings.shared.piServerURL
        guard let url = URL(string: base + "/notifications/mark-read") else { return }
        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.httpBody = try? JSONSerialization.data(withJSONObject: ["ids": ids])
        req.timeoutInterval = 4
        _ = try? await URLSession.shared.data(for: req)
    }
}
