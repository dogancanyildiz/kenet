import Foundation
import VaultFormat

enum NotificationDestination: String, Codable, Sendable {
    case tasks, goals, journal
    var prefix: String { self == .tasks ? "task" : rawValue }
    static func from(identifier: String) -> Self? {
        for destination in [Self.tasks, .goals, .journal] {
            let prefix = destination.prefix + "-"
            if identifier.hasPrefix(prefix), CalendarDate(String(identifier.dropFirst(prefix.count))) != nil {
                return destination
            }
        }
        return nil
    }
}

struct NotificationRequest: Identifiable, Sendable, Equatable {
    let id: String
    let date: Date
    let title: String
    let body: String
    let destination: NotificationDestination
}

struct NotificationNavigationRequest: Identifiable, Sendable {
    let id = UUID()
    let destination: NotificationDestination
}

enum NotificationAuthorization: CaseIterable, Sendable {
    case notDetermined, denied, authorized, provisional, ephemeral, unknown
    var canSchedule: Bool { self == .authorized || self == .provisional || self == .ephemeral }
    var canRequest: Bool { self == .notDetermined }
}

@MainActor
protocol NotificationScheduling {
    func authorization() async -> NotificationAuthorization
    func requestAuthorization() async throws -> Bool
    func pendingRequests() async -> [NotificationRequest]
    func add(_ request: NotificationRequest) async throws
    func remove(identifiers: [String]) async
    func activate(response: @escaping @MainActor @Sendable (NotificationDestination) -> Void)
}
