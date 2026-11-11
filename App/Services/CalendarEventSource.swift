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
    /// The calendar's own identifier of the event (shared by every occurrence); nil when unknown.
    var eventIdentifier: String? = nil
    var calendarID: String? = nil
    var calendarTitle: String = ""
    var recurrence: CalendarRecurrence = .none
    /// The last day a dated repeat rule allows; nil for an endless rule.
    var recurrenceEnd: Date? = nil
    /// The occurrence's original start in its series (EventKit `occurrenceDate`).
    var occurrenceDate: Date? = nil
    /// False for subscribed, holiday and birthday calendars and for invitations someone else
    /// organizes: no edit and no delete.
    var isEditable: Bool = false
    /// The event comes from the system's birthdays calendar.
    var isFromBirthdayCalendar: Bool = false
}

struct CalendarEventColor: Sendable, Hashable {
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

/// Reading, requesting permission and, on the user's request only, writing events. Tasks and
/// journal entries never go through here (decision 2026-11-11).
@MainActor protocol CalendarEventSource: AnyObject {
    var authorization: CalendarAuthorization { get }
    var onChange: (@MainActor @Sendable () -> Void)? { get set }
    func requestFullAccess() async throws -> Bool
    func events(from start: Date, to end: Date) async throws -> [CalendarEvent]
    /// Calendars that accept new events, in the calendar app's order.
    func writableCalendars() async throws -> [CalendarTarget]
    /// The system's calendar for new events; nil when there is none.
    func systemDefaultCalendarID() async -> String?
    /// Adds `draft` (`editing == nil`) or changes the occurrence `editing`.
    func save(_ draft: CalendarEventDraft, editing: CalendarEvent?, span: CalendarEditSpan) async throws
    func delete(_ event: CalendarEvent, span: CalendarEditSpan) async throws
}

enum CalendarWriteError: Error, Equatable {
    /// `notFound`: the event changed or went away in the calendar meanwhile.
    case unsupported, notFound, noCalendar, readOnly, failed
}

/// A read-only source (tests, widget snapshot) writes nothing.
extension CalendarEventSource {
    func writableCalendars() async throws -> [CalendarTarget] { [] }
    func systemDefaultCalendarID() async -> String? { nil }
    func save(_ draft: CalendarEventDraft, editing: CalendarEvent?, span: CalendarEditSpan) async throws {
        throw CalendarWriteError.unsupported
    }
    func delete(_ event: CalendarEvent, span: CalendarEditSpan) async throws {
        throw CalendarWriteError.unsupported
    }
}
