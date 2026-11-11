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
        if rules.count == 1, let rule = rules.first, isLastDayOfFebruary(rule) { return .lastDayOfFebruary }
        // A rule that ends after a count cannot be shown or kept by the plain choices.
        guard rules.count == 1, let rule = rules.first, rule.interval == 1,
            (rule.recurrenceEnd?.occurrenceCount ?? 0) == 0,
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

    /// Yearly, in February, on the month's last day (`daysOfTheMonth: [-1]`), with no count.
    static func isLastDayOfFebruary(_ rule: EKRecurrenceRule) -> Bool {
        rule.frequency == .yearly && rule.interval == 1 && (rule.recurrenceEnd?.occurrenceCount ?? 0) == 0
            && rule.monthsOfTheYear == [2] && rule.daysOfTheMonth == [-1] && rule.daysOfTheWeek == nil
            && rule.weeksOfTheYear == nil && rule.daysOfTheYear == nil && rule.setPositions == nil
    }

    static func rules(for change: CalendarWritePlan.RuleChange) -> [EKRecurrenceRule]? {
        switch change {
        case .remove: nil
        case .set(let recurrence, let end): rules(for: recurrence, end: end)
        }
    }

    static func span(_ span: CalendarEditSpan) -> EKSpan {
        span == .futureEvents ? .futureEvents : .thisEvent
    }

    /// Nil removes repetition. `custom` is never written: the caller keeps the event's own rules.
    /// `end`: the old rule's last day, carried over when the repeat changes.
    static func rules(for recurrence: CalendarRecurrence, end: Date? = nil) -> [EKRecurrenceRule]? {
        let frequency: EKRecurrenceFrequency
        switch recurrence {
        case .none, .custom: return nil
        case .daily: frequency = .daily
        case .weekly: frequency = .weekly
        case .monthly: frequency = .monthly
        case .yearly: frequency = .yearly
        case .lastDayOfFebruary:
            return [
                EKRecurrenceRule(
                    recurrenceWith: .yearly, interval: 1, daysOfTheWeek: nil, daysOfTheMonth: [-1],
                    monthsOfTheYear: [2], weeksOfTheYear: nil, daysOfTheYear: nil, setPositions: nil,
                    end: end.map { EKRecurrenceEnd(end: $0) })
            ]
        }
        return [
            EKRecurrenceRule(
                recurrenceWith: frequency, interval: 1, end: end.map { EKRecurrenceEnd(end: $0) })
        ]
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
        return store.events(matching: predicate).map(Self.value(of:))
    }

    private static func value(of event: EKEvent) -> CalendarEvent {
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
            recurrenceEnd: event.recurrenceRules?.first?.recurrenceEnd?.endDate,
            occurrenceDate: event.occurrenceDate,
            isEditable: CalendarWritePlan.isEditable(
                calendarAllowsModifications: event.calendar.allowsContentModifications,
                organizerIsOtherPerson: event.organizer.map { !$0.isCurrentUser } ?? false),
            isFromBirthdayCalendar: event.calendar.type == .birthday)
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
            event = try editable(editing)
        } else {
            event = EKEvent(eventStore: store)
        }
        let changes = CalendarWritePlan.changes(draft: draft, original: editing)
        if editing != nil, changes.isEmpty { return }
        if let title = changes.title { event.title = title }
        if let isAllDay = changes.isAllDay { event.isAllDay = isAllDay }
        if let start = changes.start { event.startDate = start }
        if let end = changes.end { event.endDate = end }
        let writable = Set(store.calendars(for: .event).filter(\.allowsContentModifications).map(\.calendarIdentifier))
        if changes.calendarID != nil || editing == nil,
            let id = CalendarWritePlan.calendarID(
                requested: changes.calendarID, current: event.calendar?.calendarIdentifier, writable: writable,
                systemDefault: store.defaultCalendarForNewEvents?.calendarIdentifier),
            let calendar = store.calendar(withIdentifier: id)
        {
            event.calendar = calendar
        }
        guard event.calendar != nil else { throw CalendarWriteError.noCalendar }
        if let rule = changes.rule { event.recurrenceRules = EventKitRecurrence.rules(for: rule) }
        try store.save(event, span: EventKitRecurrence.span(span), commit: true)
    }

    func delete(_ event: CalendarEvent, span: CalendarEditSpan) throws {
        try store.remove(try editable(event), span: EventKitRecurrence.span(span), commit: true)
    }

    /// The occurrence the user picked, as `CalendarWritePlan.pickOccurrence` decides; never a
    /// series' first occurrence in its place.
    private func editable(_ target: CalendarEvent) throws -> EKEvent {
        guard let identifier = target.eventIdentifier else { throw CalendarWriteError.notFound }
        let around = store.events(
            matching: store.predicateForEvents(
                withStart: target.start.addingTimeInterval(-86400), end: target.end.addingTimeInterval(86400),
                calendars: nil))
        let fallback = store.event(withIdentifier: identifier)
        let found: EKEvent
        switch CalendarWritePlan.pickOccurrence(
            target, in: around.map(Self.candidate(of:)), fallback: fallback.map(Self.candidate(of:)))
        {
        case .candidate(let index): found = around[index]
        case .fallback:
            guard let fallback else { throw CalendarWriteError.notFound }
            found = fallback
        case .notFound: throw CalendarWriteError.notFound
        }
        guard Self.value(of: found).isEditable else { throw CalendarWriteError.readOnly }
        return found
    }

    private static func candidate(of event: EKEvent) -> OccurrenceCandidate {
        OccurrenceCandidate(
            identifier: event.eventIdentifier, start: event.startDate, occurrenceDate: event.occurrenceDate,
            isRecurring: event.hasRecurrenceRules)
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
