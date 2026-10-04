import Foundation
import VaultFormat

struct GeofenceAction: Sendable {
    let regionID: String
    let vaultID: String
    let day: CalendarDate
    let mark: Bool
}
struct GeofenceNotice: Sendable {
    let action: GeofenceAction
    let goalName: String
    let placeName: String
    let automatic: Bool
    var id: String { "geofence-" + action.regionID + "-" + action.day.description }
}
@MainActor
protocol GeofenceNotificationDelivering {
    func activateGeofences(response: @escaping @MainActor @Sendable (GeofenceAction) async -> Void)
    func sendGeofence(_ notice: GeofenceNotice) async throws -> Bool
}
