import Foundation

/// A calendar in memory: UI tests (`JOURNAL_UITEST_CALENDAR=memory`) and unit tests use it in
/// place of EventKit, so adding, editing and deleting run without a real calendar.
@MainActor final class InMemoryCalendarSource: CalendarEventSource {
    var authorization: CalendarAuthorization
    var onChange: (@MainActor @Sendable () -> Void)?
    private(set) var stored: [CalendarEvent]
    let calendars: [CalendarTarget]
    private var nextID = 1

    init(
        authorization: CalendarAuthorization = .fullAccess, events: [CalendarEvent] = [],
        calendars: [CalendarTarget] = InMemoryCalendarSource.sampleCalendars
    ) {
        self.authorization = authorization
        self.stored = events
        self.calendars = calendars
    }

    static let sampleCalendars = [
        CalendarTarget(id: "home", title: "Ev", color: CalendarEventColor(red: 0.2, green: 0.5, blue: 0.9, alpha: 1)),
        CalendarTarget(id: "work", title: "İş", color: CalendarEventColor(red: 0.9, green: 0.4, blue: 0.2, alpha: 1)),
    ]

    func requestFullAccess() async throws -> Bool {
        authorization = .fullAccess
        return true
    }

    /// Repeating events answer one occurrence per period inside the range, as EventKit does.
    func events(from start: Date, to end: Date) async throws -> [CalendarEvent] {
        stored.flatMap { occurrences(of: $0, from: start, to: end) }
    }

    func writableCalendars() async throws -> [CalendarTarget] { calendars }
    func systemDefaultCalendarID() async -> String? { calendars.first?.id }

    func save(_ draft: CalendarEventDraft, editing: CalendarEvent?, span: CalendarEditSpan) async throws {
        let calendarID = draft.calendarID ?? calendars.first?.id
        guard let target = calendars.first(where: { $0.id == calendarID }) else { throw CalendarWriteError.noCalendar }
        let identifier: String
        if let editing {
            guard let index = stored.firstIndex(where: { $0.eventIdentifier == editing.eventIdentifier }) else {
                throw CalendarWriteError.notFound
            }
            identifier = editing.eventIdentifier ?? ""
            stored.remove(at: index)
        } else {
            identifier = "memory-\(nextID)"
            nextID += 1
        }
        stored.append(
            CalendarEvent(
                id: identifier, title: draft.title, start: draft.start, end: draft.end, isAllDay: draft.isAllDay,
                color: target.color, eventIdentifier: identifier, calendarID: target.id, calendarTitle: target.title,
                recurrence: draft.recurrence, isEditable: true))
        onChange?()
    }

    func delete(_ event: CalendarEvent, span: CalendarEditSpan) async throws {
        guard stored.contains(where: { $0.eventIdentifier == event.eventIdentifier }) else {
            throw CalendarWriteError.notFound
        }
        stored.removeAll { $0.eventIdentifier == event.eventIdentifier }
        onChange?()
    }

    private func occurrences(of event: CalendarEvent, from start: Date, to end: Date) -> [CalendarEvent] {
        let component: Calendar.Component
        switch event.recurrence {
        case .none, .custom:
            return event.start < end && event.end >= start ? [event] : []
        case .daily: component = .day
        case .weekly: component = .weekOfYear
        case .monthly: component = .month
        case .yearly: component = .year
        }
        let calendar = Calendar(identifier: .gregorian)
        let length = event.end.timeIntervalSince(event.start)
        var result: [CalendarEvent] = []
        var step = 0
        while result.count < 400, let begin = calendar.date(byAdding: component, value: step, to: event.start),
            begin < end
        {
            if begin.addingTimeInterval(length) >= start {
                result.append(
                    CalendarEvent(
                        id: (event.eventIdentifier ?? event.id) + ":" + String(begin.timeIntervalSince1970),
                        title: event.title, start: begin, end: begin.addingTimeInterval(length),
                        isAllDay: event.isAllDay,
                        color: event.color, attendees: event.attendees, eventIdentifier: event.eventIdentifier,
                        calendarID: event.calendarID, calendarTitle: event.calendarTitle, recurrence: event.recurrence,
                        isEditable: event.isEditable, isFromBirthdayCalendar: event.isFromBirthdayCalendar))
            }
            step += 1
        }
        return result
    }
}
