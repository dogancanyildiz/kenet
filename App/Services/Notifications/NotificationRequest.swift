import Foundation
import VaultFormat

enum NotificationDestination: String, Codable, Sendable {
    case tasks, goals, diary, people
    var prefix: String { self == .tasks ? "task" : rawValue }
    /// Also reads the diary reminder's identifier of a build before 2026-11-13, so a reminder
    /// still pending or delivered from it opens the diary and the next plan removes it.
    static func from(identifier: String) -> Self? {
        let prefixes =
            [Self.tasks, .goals, .diary, .people].map { ($0, $0.prefix) }
            + [(Self.diary, LegacyDefaults.codeName)]
        for (destination, prefix) in prefixes {
            let prefix = prefix + "-"
            if identifier.hasPrefix(prefix), CalendarDate(String(identifier.dropFirst(prefix.count))) != nil {
                return destination
            }
        }
        return nil
    }
}

/// Screen a tapped notification opens. Goals and the diary prompt both land on Today.
enum NotificationRoute: Equatable, Sendable {
    case today
    case tasks
    case unseenPeople

    init(_ destination: NotificationDestination) {
        switch destination {
        case .tasks: self = .tasks
        case .goals, .diary: self = .today
        case .people: self = .unseenPeople
        }
    }
}

struct NotificationRequest: Identifiable, Sendable, Equatable {
    let id: String
    let date: Date
    let title: String
    let body: String
    let destination: NotificationDestination
}

extension NotificationRequest {
    /// Same identifier, text and destination, firing within the same second. The system keeps the
    /// trigger's date only to the second, so a pending copy compares to the planned one this way.
    func isSameSchedule(as other: NotificationRequest) -> Bool {
        id == other.id && title == other.title && body == other.body && destination == other.destination
            && Int(date.timeIntervalSince1970.rounded(.down)) == Int(other.date.timeIntervalSince1970.rounded(.down))
    }
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
    func removeAllDeliveredNotifications() async
    func activate(response: @escaping @MainActor @Sendable (NotificationDestination) -> Void)
}
