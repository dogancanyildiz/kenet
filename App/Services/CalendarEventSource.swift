import EntityRecognition
import Foundation

struct CalendarEvent: Identifiable, Sendable, Equatable {
    let id: String
    let title: String
    let start: Date
    let end: Date
    let isAllDay: Bool
    let color: CalendarEventColor
    /// People invited to the event, as the calendar names them; read only to draft an entry.
    var attendees: [Attendee] = []
}

struct CalendarEventColor: Sendable, Equatable {
    let red: Double
    let green: Double
    let blue: Double
    let alpha: Double
}

enum CalendarAuthorization: Sendable, CaseIterable {
    case notDetermined, fullAccess, denied, restricted, writeOnly
    var canRead: Bool { self == .fullAccess }
    var canRequest: Bool { self == .notDetermined || self == .writeOnly }
}

/// Only reading and requesting permission are available through this interface.
@MainActor protocol CalendarEventSource: AnyObject {
    var authorization: CalendarAuthorization { get }
    var onChange: (@MainActor @Sendable () -> Void)? { get set }
    func requestFullAccess() async throws -> Bool
    func events(from start: Date, to end: Date) async throws -> [CalendarEvent]
}
