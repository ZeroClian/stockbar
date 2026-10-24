import Foundation
import UserNotifications

@MainActor
protocol NotificationSending {
    func status() async -> UNAuthorizationStatus
    func requestPermission() async throws -> Bool
    func send(identifier: String, title: String, body: String) async throws
}

@MainActor
final class NotificationService: NSObject, UNUserNotificationCenterDelegate, NotificationSending {
    private let center = UNUserNotificationCenter.current()

    override init() {
        super.init()
        center.delegate = self
    }

    func status() async -> UNAuthorizationStatus {
        await center.notificationSettings().authorizationStatus
    }

    func requestPermission() async throws -> Bool {
        try await center.requestAuthorization(options: [.alert, .sound])
    }

    func send(identifier: String, title: String, body: String) async throws {
        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        try await center.add(UNNotificationRequest(identifier: identifier, content: content, trigger: nil))
    }

    nonisolated func userNotificationCenter(_ center: UNUserNotificationCenter,
        willPresent notification: UNNotification,
        withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void) {
        completionHandler([.banner, .list])
    }

    nonisolated func userNotificationCenter(_ center: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse,
        withCompletionHandler completionHandler: @escaping () -> Void) {
        DispatchQueue.main.async { NotificationCenter.default.post(name: .openStockPanel, object: nil) }
        completionHandler()
    }
}

extension Notification.Name {
    static let openStockPanel = Notification.Name("StockBar.openPanel")
    static let closeStockPanel = Notification.Name("StockBar.closePanel")
}
