import Foundation
import UserNotifications

/// The system center is accessed lazily; constructing a test-host service cannot register a delegate.
@MainActor
final class SystemNotificationScheduler: NSObject, NotificationScheduling, UNUserNotificationCenterDelegate {
    private var response: (@MainActor @Sendable (NotificationDestination) -> Void)?
    func activate(response: @escaping @MainActor @Sendable (NotificationDestination) -> Void) {
        self.response = response
        UNUserNotificationCenter.current().delegate = self
    }
    func authorization() async -> NotificationAuthorization {
        switch await UNUserNotificationCenter.current().notificationSettings().authorizationStatus {
        case .notDetermined: .notDetermined
        case .denied: .denied
        case .authorized: .authorized
        case .provisional: .provisional
        #if os(iOS)
            case .ephemeral: .ephemeral
        #endif
        default: .unknown
        }
    }
    func requestAuthorization() async throws -> Bool {
        try await UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound])
    }
    func pendingRequests() async -> [NotificationRequest] {
        await UNUserNotificationCenter.current().pendingNotificationRequests().compactMap { request in
            guard let destination = NotificationDestination.from(identifier: request.identifier),
                let date = (request.trigger as? UNCalendarNotificationTrigger)?.nextTriggerDate()
                    ?? (request.content.userInfo["fireDate"] as? Double).map(Date.init(timeIntervalSince1970:))
            else { return nil }
            return NotificationRequest(
                id: request.identifier, date: date, title: request.content.title, body: request.content.body,
                destination: destination)
        }
    }
    func add(_ request: NotificationRequest) async throws {
        let content = UNMutableNotificationContent()
        content.title = request.title
        content.body = request.body
        content.sound = .default
        content.userInfo = ["fireDate": request.date.timeIntervalSince1970]
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = .current
        var components = calendar.dateComponents([.year, .month, .day, .hour, .minute, .second], from: request.date)
        components.calendar = calendar
        components.timeZone = calendar.timeZone
        try await UNUserNotificationCenter.current().add(
            UNNotificationRequest(
                identifier: request.id, content: content,
                trigger: UNCalendarNotificationTrigger(dateMatching: components, repeats: false)))
    }
    func remove(identifiers: [String]) async {
        UNUserNotificationCenter.current().removePendingNotificationRequests(withIdentifiers: identifiers)
    }
    nonisolated func userNotificationCenter(
        _ center: UNUserNotificationCenter, willPresent notification: UNNotification,
        withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void
    ) { completionHandler([.banner, .sound]) }

    nonisolated func userNotificationCenter(
        _ center: UNUserNotificationCenter, didReceive response: UNNotificationResponse,
        withCompletionHandler completionHandler: @escaping () -> Void
    ) {
        if response.actionIdentifier == UNNotificationDefaultActionIdentifier,
            let destination = NotificationDestination.from(identifier: response.notification.request.identifier)
        {
            Task { @MainActor [weak self] in self?.response?(destination) }
        }
        completionHandler()
    }
}
