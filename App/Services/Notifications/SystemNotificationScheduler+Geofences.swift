import Foundation
import UserNotifications
import VaultFormat

extension SystemNotificationScheduler: GeofenceNotificationDelivering {
    func activateGeofences(response: @escaping @MainActor @Sendable (GeofenceAction) async -> Void) {
        geofenceResponse = response
        UNUserNotificationCenter.current().delegate = self
        refreshGeofenceCategory()
    }

    /// When app lock is enabled, omit Mark so the only path is opening the app (default action).
    func refreshGeofenceCategory(lockEnabled: Bool? = nil) {
        let enabled = lockEnabled ?? UserDefaults.standard.bool(forKey: AppLockService.enabledKey)
        geofenceRegistration = Task {
            let center = UNUserNotificationCenter.current()
            let existing = await center.notificationCategories()
            let actions: [UNNotificationAction]
            if enabled {
                actions = []
            } else {
                actions = [
                    UNNotificationAction(
                        identifier: "geofence.mark", title: String(localized: "İşaretle"), options: []),
                    UNNotificationAction(
                        identifier: "geofence.skip", title: String(localized: "Şimdi değil"), options: []),
                ]
            }
            let category = UNNotificationCategory(
                identifier: "geofence.goal", actions: actions, intentIdentifiers: [], options: [])
            center.setNotificationCategories(
                Set(existing.filter { $0.identifier != "geofence.goal" }).union([category]))
        }
    }

    func sendGeofence(_ notice: GeofenceNotice) async throws -> Bool {
        refreshGeofenceCategory()
        await geofenceRegistration?.value
        guard await authorization().canSchedule else { return false }
        let content = UNMutableNotificationContent()
        content.title = LocationCopy.geofenceTitle(
            place: notice.placeName, goal: notice.goalName, automatic: notice.automatic,
            hideContent: notice.hideContent)
        content.sound = .default
        content.categoryIdentifier = notice.automatic ? "" : "geofence.goal"
        content.userInfo = [
            "geofence.region": notice.action.regionID, "geofence.vault": notice.action.vaultID,
            "geofence.day": notice.action.day.description,
        ]
        try await UNUserNotificationCenter.current().add(
            UNNotificationRequest(
                identifier: notice.id,
                content: content, trigger: UNTimeIntervalNotificationTrigger(timeInterval: 1, repeats: false)))
        return true
    }
}

extension GeofenceAction {
    static func decode(_ info: [AnyHashable: Any], mark: Bool) -> GeofenceAction? {
        guard let region = info["geofence.region"] as? String, region.hasPrefix(GeofenceRegion.prefix),
            let vault = info["geofence.vault"] as? String, vault.count == 64,
            let date = info["geofence.day"] as? String, let day = CalendarDate(date)
        else { return nil }
        return GeofenceAction(regionID: region, vaultID: vault, day: day, mark: mark)
    }
}
