import EntityRecognition
import Foundation
import Observation
import VaultFormat

extension QuickEntryModel {
    /// What a calendar event adds to the field's text: the entry's time and the attendees the
    /// vault does not know, which wait as chips instead of entering the text.
    struct CalendarDraft: Equatable {
        /// The event's start; nil for an all-day event or one that began on another day.
        var time: Date?
        var unknownAttendees: [String]
        /// Set when the field holds a journaling suggestion's line (``SuggestionFill``).
        var suggestion: SuggestionFill? = nil
    }

    struct CalendarDraftSnapshot {
        let draft: CalendarDraft?
        let includesTime: Bool
    }

    var unknownAttendees: [String] { mode == .event ? calendarDraft?.unknownAttendees ?? [] : [] }
    var calendarDraftSnapshot: CalendarDraftSnapshot { .init(draft: calendarDraft, includesTime: includesTime) }

    /// Fills the empty field from a calendar event; the user still sends it. A draft already in
    /// the field is never replaced: the event is refused and the field says why.
    @discardableResult
    func applyCalendarDraft(_ event: CalendarEvent, timeZone: TimeZone = .current) -> Bool {
        guard text.allSatisfy(\.isWhitespace) else {
            composer.errorText = String(localized: "Kutuda yazılmış bir taslak var. Önce onu gönder ya da sil.")
            return false
        }
        let match = AttendeeMatching.match(event.attendees, entities: store.knownEntities)
        // An entry is one line; a title's line breaks become single blanks.
        var draft = event.title.split(whereSeparator: \.isNewline)
            .map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }.joined(separator: " ")
        var pinned: [(entity: KnownEntity, range: Range<Int>)] = []
        func append(_ spelling: String) -> Range<Int> {
            if !draft.isEmpty { draft += " " }
            let start = draft.utf8.count + 1
            draft += "@" + spelling
            return start..<draft.utf8.count
        }
        for certain in match.certain { pinned.append((certain.entity, append(certain.spelling))) }
        // Left unpinned: sending the entry asks which one is meant.
        for ambiguous in match.ambiguous { _ = append(ambiguous.spelling) }
        // A closing blank ends the mention, so the suggestion list stays shut.
        if !match.certain.isEmpty || !match.ambiguous.isEmpty { draft += " " }
        mode = .event
        text = draft
        for pin in pinned { composer.pin(pin.entity, nameRange: pin.range) }
        let startsThisDay = LocalDay.today(at: event.start, timeZone: timeZone) == (day ?? today())
        let time = event.isAllDay || !startsThisDay ? nil : event.start
        calendarDraft = CalendarDraft(time: time, unknownAttendees: match.unknown)
        includesTime = time != nil
        if let time { selectedTime = time }
        return true
    }

    /// Moves an attendee the vault does not know into the text as an explicit mention; sending
    /// the entry then asks whether to create it, as for any typed `@Name`.
    func addUnknownAttendee(_ name: String) {
        guard let index = calendarDraft?.unknownAttendees.firstIndex(of: name) else { return }
        var draft = text
        if !draft.isEmpty && draft.last?.isWhitespace != true { draft += " " }
        text = draft + "@" + name + " "
        calendarDraft?.unknownAttendees.remove(at: index)
    }

    /// The draft ends with its text, sent or deleted; the time control returns to the day's default.
    func clearCalendarDraft() {
        guard calendarDraft != nil else { return }
        calendarDraft = nil
        includesTime = day == nil || day == today()
    }

    /// A failed save puts the text back; its time and chips come back with it.
    func restoreCalendarDraft(_ snapshot: CalendarDraftSnapshot) {
        guard let draft = snapshot.draft else { return }
        calendarDraft = draft
        includesTime = snapshot.includesTime
    }
}

/// Carries a calendar row's event to the quick entry bar of the same day page.
@MainActor @Observable
final class CalendarDraftInbox {
    static let shared = CalendarDraftInbox()
    struct Request {
        let id = UUID()
        let event: CalendarEvent
        let day: CalendarDate
    }
    private(set) var request: Request?

    func post(_ event: CalendarEvent, on day: CalendarDate) { request = Request(event: event, day: day) }

    func take(on day: CalendarDate) -> CalendarEvent? {
        guard let request, request.day == day else { return nil }
        self.request = nil
        return request.event
    }
}
