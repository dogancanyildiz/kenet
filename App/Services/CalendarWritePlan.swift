import Foundation

/// One event the calendar answers while looking for the occurrence the user picked.
struct OccurrenceCandidate: Equatable, Sendable {
    let identifier: String?
    let start: Date
    /// The occurrence's original start (EventKit `occurrenceDate`): it stays put when only this
    /// occurrence was moved.
    let occurrenceDate: Date?
    let isRecurring: Bool
}

/// Pure decisions of a calendar write. `EventKitCalendarSource` and `InMemoryCalendarSource` both
/// follow them, so the unit tests run the same rules the device does.
enum CalendarWritePlan {
    enum Pick: Equatable {
        case candidate(Int)
        case fallback
        case notFound
    }

    /// The occurrence `target` names among `candidates` (the events around its start), matched by
    /// identifier and original start, else by start. `fallback` (what the identifier alone
    /// answers) is used only for a single event: on a repeating series it is the first occurrence,
    /// and writing there would hit the wrong day or, with "Bu ve sonrakiler", the whole series.
    static func pickOccurrence(
        _ target: CalendarEvent, in candidates: [OccurrenceCandidate], fallback: OccurrenceCandidate?
    ) -> Pick {
        guard let identifier = target.eventIdentifier else { return .notFound }
        let same = candidates.indices.filter { candidates[$0].identifier == identifier }
        if let wanted = target.occurrenceDate,
            let index = same.first(where: { candidates[$0].occurrenceDate == wanted })
        {
            return .candidate(index)
        }
        if let index = same.first(where: { candidates[$0].start == target.start }) { return .candidate(index) }
        if let fallback, fallback.identifier == identifier, !fallback.isRecurring, target.recurrence == .none {
            return .fallback
        }
        return .notFound
    }

    /// An invitation someone else organizes is not ours to change: editing it would decline or
    /// fork it.
    static func isEditable(calendarAllowsModifications: Bool, organizerIsOtherPerson: Bool) -> Bool {
        calendarAllowsModifications && !organizerIsOtherPerson
    }

    /// The calendar an event goes to: the requested one while writable, else the event's own
    /// (an edit), else the system's default.
    static func calendarID(
        requested: String?, current: String?, writable: Set<String>, systemDefault: String?
    ) -> String? {
        if let requested, writable.contains(requested) { return requested }
        if let current { return current }
        return systemDefault
    }

    /// The repeat rule to write; nil leaves the event's rule as it is.
    enum RuleChange: Equatable {
        case remove
        case set(CalendarRecurrence, end: Date?)
    }

    /// What a save writes. Nil fields stay as the calendar has them, so a change made elsewhere
    /// after the form opened is not overwritten by the form's snapshot.
    struct Changes: Equatable {
        var title: String?
        var start: Date?
        var end: Date?
        var isAllDay: Bool?
        var calendarID: String?
        var rule: RuleChange?

        var isEmpty: Bool { self == Changes() }
    }

    /// A new event writes every field; an edit only what differs from `original`. A changed repeat
    /// keeps the old rule's end date.
    static func changes(draft: CalendarEventDraft, original: CalendarEvent?, timeZone: TimeZone = .current) -> Changes {
        guard let original else {
            return Changes(
                title: draft.title, start: draft.start, end: draft.end, isAllDay: draft.isAllDay,
                calendarID: draft.calendarID, rule: rule(for: draft.recurrence, end: nil))
        }
        // Compared in the written form: EventKit ends an all-day event at 23:59:59 of its last day.
        let before = CalendarEventDraft(event: original).normalized(timeZone: timeZone)
        var changes = Changes()
        if draft.title != before.title { changes.title = draft.title }
        if draft.start != before.start { changes.start = draft.start }
        if draft.end != before.end { changes.end = draft.end }
        if draft.isAllDay != before.isAllDay { changes.isAllDay = draft.isAllDay }
        if let id = draft.calendarID, id != original.calendarID { changes.calendarID = id }
        if draft.recurrence != original.recurrence, draft.recurrence != .custom {
            changes.rule = rule(for: draft.recurrence, end: original.recurrenceEnd)
        }
        return changes
    }

    private static func rule(for recurrence: CalendarRecurrence, end: Date?) -> RuleChange? {
        switch recurrence {
        case .none: .remove
        case .custom: nil
        default: .set(recurrence, end: end)
        }
    }
}
