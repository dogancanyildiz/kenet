import CoreGraphics
import EntityRecognition
import EventKit
import Foundation

@MainActor final class EventKitCalendarSource: CalendarEventSource {
    var onChange: (@MainActor @Sendable () -> Void)?
    private let reader = CalendarEventReader()
    private var observation: CalendarChangeObservation?

    init() {
        observation = CalendarChangeObservation { [weak self] in self?.onChange?() }
    }

    var authorization: CalendarAuthorization {
        switch EKEventStore.authorizationStatus(for: .event) {
        case .notDetermined: .notDetermined
        case .fullAccess: .fullAccess
        case .denied: .denied
        case .restricted: .restricted
        case .writeOnly: .writeOnly
        @unknown default: .restricted
        }
    }

    func requestFullAccess() async throws -> Bool { try await reader.requestFullAccess() }
    func events(from start: Date, to end: Date) async throws -> [CalendarEvent] {
        await reader.events(from: start, to: end)
    }
    func writableCalendars() async throws -> [CalendarTarget] { await reader.writableCalendars() }
    func systemDefaultCalendarID() async -> String? { await reader.systemDefaultCalendarID() }
    func save(_ draft: CalendarEventDraft, editing: CalendarEvent?, span: CalendarEditSpan) async throws {
        try await reader.save(draft, editing: editing, span: span)
    }
    func delete(_ event: CalendarEvent, span: CalendarEditSpan) async throws {
        try await reader.delete(event, span: span)
    }
}

/// Maps the form's repeat choices onto EventKit rules (unit-tested).
enum EventKitRecurrence {
    static func recurrence(of rules: [EKRecurrenceRule]?) -> CalendarRecurrence {
        guard let rules, !rules.isEmpty else { return .none }
        guard rules.count == 1, let rule = rules.first, rule.interval == 1,
            rule.daysOfTheWeek == nil, rule.daysOfTheMonth == nil, rule.monthsOfTheYear == nil,
            rule.weeksOfTheYear == nil, rule.daysOfTheYear == nil, rule.setPositions == nil
        else { return .custom }
        switch rule.frequency {
        case .daily: return .daily
        case .weekly: return .weekly
        case .monthly: return .monthly
        case .yearly: return .yearly
        @unknown default: return .custom
        }
    }

    /// Nil removes repetition. `custom` is never written: the caller keeps the event's own rules.
    static func rules(for recurrence: CalendarRecurrence) -> [EKRecurrenceRule]? {
        let frequency: EKRecurrenceFrequency
        switch recurrence {
        case .none, .custom: return nil
        case .daily: frequency = .daily
        case .weekly: frequency = .weekly
        case .monthly: frequency = .monthly
        case .yearly: frequency = .yearly
        }
        return [EKRecurrenceRule(recurrenceWith: frequency, interval: 1, end: nil)]
    }
}

extension CalendarEventColor {
    fileprivate init(_ color: CGColor?) {
        let converted = color?.converted(
            to: CGColorSpace(name: CGColorSpace.sRGB)!, intent: .defaultIntent, options: nil)
        let components = converted?.components ?? [0.2, 0.5, 0.9, 1]
        self.init(red: components[0], green: components[1], blue: components[2], alpha: components[3])
    }
}

/// EventKit objects stay on one actor; potentially blocking queries never run on the UI thread.
private actor CalendarEventReader {
    private lazy var store = EKEventStore()

    func requestFullAccess() async throws -> Bool {
        try await withCheckedThrowingContinuation { continuation in
            store.requestFullAccessToEvents { granted, error in
                if let error { continuation.resume(throwing: error) } else { continuation.resume(returning: granted) }
            }
        }
    }

    func events(from start: Date, to end: Date) -> [CalendarEvent] {
        let predicate = store.predicateForEvents(withStart: start, end: end, calendars: nil)
        return store.events(matching: predicate).map { event in
            CalendarEvent(
                id: (event.eventIdentifier ?? event.calendarItemIdentifier) + ":"
                    + String(event.startDate.timeIntervalSince1970),
                title: event.title ?? "", start: event.startDate, end: event.endDate,
                isAllDay: event.isAllDay,
                color: CalendarEventColor(event.calendar.cgColor),
                // Rooms, resources and groups are not people to mention.
                attendees: (event.attendees ?? [])
                    .filter { $0.participantType == .person || $0.participantType == .unknown }
                    .map { Attendee(name: $0.name ?? "", isCurrentUser: $0.isCurrentUser) },
                eventIdentifier: event.eventIdentifier,
                calendarID: event.calendar.calendarIdentifier,
                calendarTitle: event.calendar.title,
                recurrence: EventKitRecurrence.recurrence(of: event.recurrenceRules),
                isEditable: event.calendar.allowsContentModifications,
                isFromBirthdayCalendar: event.calendar.type == .birthday)
        }
    }

    func writableCalendars() -> [CalendarTarget] {
        store.calendars(for: .event).filter(\.allowsContentModifications).map {
            CalendarTarget(id: $0.calendarIdentifier, title: $0.title, color: CalendarEventColor($0.cgColor))
        }
    }

    func systemDefaultCalendarID() -> String? { store.defaultCalendarForNewEvents?.calendarIdentifier }

    func save(_ draft: CalendarEventDraft, editing: CalendarEvent?, span: CalendarEditSpan) throws {
        let event: EKEvent
        if let editing {
            guard let found = occurrence(of: editing) else { throw CalendarWriteError.notFound }
            guard found.calendar.allowsContentModifications else { throw CalendarWriteError.readOnly }
            event = found
        } else {
            event = EKEvent(eventStore: store)
        }
        event.title = draft.title
        event.isAllDay = draft.isAllDay
        event.startDate = draft.start
        event.endDate = draft.end
        if let id = draft.calendarID, let calendar = store.calendar(withIdentifier: id),
            calendar.allowsContentModifications
        {
            event.calendar = calendar
        } else if event.calendar == nil {
            event.calendar = store.defaultCalendarForNewEvents
        }
        guard event.calendar != nil else { throw CalendarWriteError.noCalendar }
        // An unchanged choice keeps the event's own rule (an end date, a custom pattern).
        if draft.recurrence != .custom, draft.recurrence != editing?.recurrence {
            event.recurrenceRules = EventKitRecurrence.rules(for: draft.recurrence)
        }
        try store.save(event, span: span == .futureEvents ? .futureEvents : .thisEvent, commit: true)
    }

    func delete(_ event: CalendarEvent, span: CalendarEditSpan) throws {
        guard let found = occurrence(of: event) else { throw CalendarWriteError.notFound }
        guard found.calendar.allowsContentModifications else { throw CalendarWriteError.readOnly }
        try store.remove(found, span: span == .futureEvents ? .futureEvents : .thisEvent, commit: true)
    }

    /// `event(withIdentifier:)` answers a repeating event's first occurrence; the one the user
    /// picked is found by its start.
    private func occurrence(of event: CalendarEvent) -> EKEvent? {
        guard let identifier = event.eventIdentifier else { return nil }
        let predicate = store.predicateForEvents(
            withStart: event.start.addingTimeInterval(-86400), end: event.end.addingTimeInterval(86400),
            calendars: nil)
        if let match = store.events(matching: predicate).first(where: {
            $0.eventIdentifier == identifier && $0.startDate == event.start
        }) {
            return match
        }
        return store.event(withIdentifier: identifier)
    }
}

/// NotificationCenter permits removal from any thread. The callback always hops to MainActor.
private final class CalendarChangeObservation: @unchecked Sendable {
    private let token: any NSObjectProtocol
    init(action: @escaping @MainActor @Sendable () -> Void) {
        token = NotificationCenter.default.addObserver(forName: .EKEventStoreChanged, object: nil, queue: nil) { _ in
            Task { @MainActor in action() }
        }
    }
    deinit { NotificationCenter.default.removeObserver(token) }
}
