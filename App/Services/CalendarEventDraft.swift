import EntityRecognition
import Foundation
import VaultFormat

/// The repeat choices the form offers. `custom` is any other rule the calendar holds: the app shows
/// it and never rewrites it unless the user picks one of the plain choices.
enum CalendarRecurrence: String, CaseIterable, Sendable, Hashable {
    case none, daily, weekly, monthly, yearly, custom

    /// The form's menu, without `custom`.
    static let choices: [CalendarRecurrence] = [.none, .daily, .weekly, .monthly, .yearly]

    /// String Catalog key of the menu item and the row caption.
    var catalogKey: String {
        switch self {
        case .none: "Tekrar yok"
        case .daily: "Her gün"
        case .weekly: "Her hafta"
        case .monthly: "Her ay"
        case .yearly: "Her yıl"
        case .custom: "Özel tekrar"
        }
    }
}

/// Which occurrences of a repeating event a change touches.
enum CalendarEditSpan: Sendable, Equatable {
    case thisEvent, futureEvents
}

/// A calendar new events can go to.
struct CalendarTarget: Identifiable, Sendable, Hashable {
    let id: String
    let title: String
    let color: CalendarEventColor
}

/// The form's values. Pure: the source maps it onto the calendar.
struct CalendarEventDraft: Equatable, Sendable {
    var title: String
    var start: Date
    var end: Date
    var isAllDay: Bool
    var recurrence: CalendarRecurrence
    /// Nil: the default calendar (Settings, then the system's).
    var calendarID: String?

    /// A new event on `day`, one hour long: another day starts at 09:00, today at the next full
    /// hour, and after 23:00 (whose next hour is tomorrow) at the current five minutes.
    static func new(
        on day: CalendarDate, now: Date, calendarID: String?, timeZone: TimeZone = .current
    ) -> CalendarEventDraft {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = timeZone
        let dayStart = calendar.startOfDay(for: LocalDay.instant(for: day, timeZone: timeZone))
        var start = calendar.date(bySettingHour: 9, minute: 0, second: 0, of: dayStart) ?? dayStart
        if LocalDay.today(at: now, timeZone: timeZone) == day, let hour = calendar.dateInterval(of: .hour, for: now) {
            if calendar.isDate(hour.end, inSameDayAs: dayStart) {
                start = hour.end
            } else {
                let minute = calendar.component(.minute, from: now)
                start = hour.start.addingTimeInterval(Double(minute - minute % 5) * 60)
            }
        }
        return CalendarEventDraft(
            title: "", start: start, end: start.addingTimeInterval(3600), isAllDay: false,
            recurrence: .none, calendarID: calendarID)
    }

    /// A yearly all-day event "<Ad> doğum günü" on `date`.
    static func birthday(
        name: String, on date: Date, calendarID: String?, locale: Locale, timeZone: TimeZone = .current
    ) -> CalendarEventDraft {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = timeZone
        let start = calendar.startOfDay(for: date)
        let resolved = PresentationLocalization.resolvedLocale(locale)
        let title = String(
            localized: "\(name) doğum günü", bundle: PresentationLocalization.bundle(resolved), locale: resolved)
        return CalendarEventDraft(
            title: title, start: start, end: start, isAllDay: true, recurrence: .yearly, calendarID: calendarID)
    }

    init(
        title: String, start: Date, end: Date, isAllDay: Bool, recurrence: CalendarRecurrence,
        calendarID: String?
    ) {
        self.title = title
        self.start = start
        self.end = end
        self.isAllDay = isAllDay
        self.recurrence = recurrence
        self.calendarID = calendarID
    }

    init(event: CalendarEvent) {
        self.init(
            title: event.title, start: event.start, end: event.end, isAllDay: event.isAllDay,
            recurrence: event.recurrence, calendarID: event.calendarID)
    }

    var trimmedTitle: String { title.trimmingCharacters(in: .whitespacesAndNewlines) }
    var canSave: Bool { !trimmedTitle.isEmpty }

    /// What is written: a trimmed title and an end never before the start. An all-day event spans
    /// whole days from the start's day to the end's day.
    func normalized(timeZone: TimeZone = .current) -> CalendarEventDraft {
        var copy = self
        copy.title = trimmedTitle
        if isAllDay {
            var calendar = Calendar(identifier: .gregorian)
            calendar.timeZone = timeZone
            copy.start = calendar.startOfDay(for: start)
            // An end exactly at midnight closes the day before: 23:00–00:00 stays one day.
            let lastDay = end > start && calendar.startOfDay(for: end) == end ? end.addingTimeInterval(-1) : end
            copy.end = max(copy.start, calendar.startOfDay(for: lastDay))
        } else if end < start {
            copy.end = start
        }
        return copy
    }

    /// Choices for saving a change to `original`: a changed repeat rule or calendar only applies
    /// from here on (one occurrence cannot move to another calendar).
    static func spans(saving draft: CalendarEventDraft, over original: CalendarEvent) -> [CalendarEditSpan] {
        guard original.recurrence != .none else { return [.thisEvent] }
        let movesCalendar = draft.calendarID != nil && draft.calendarID != original.calendarID
        return draft.recurrence == original.recurrence && !movesCalendar
            ? [.thisEvent, .futureEvents] : [.futureEvents]
    }
}

/// The names a person answers to on the calendar (decision 2026-11-11): the file's full name and
/// its aliases.
struct CalendarPersonNames: Equatable, Sendable {
    let fullName: String
    let aliases: [String]
}

/// Matches calendar events to a person. A name of several words matches whole adjacent title words
/// or an attendee's whole name; a one-word name or alias ("Can", "Deniz") is a common word too,
/// so it matches an attendee's whole name only. The recognizer's fold: case, Turkish İ/ı.
enum CalendarPersonMatch {
    static func words(_ text: String) -> [String] {
        nameComparisonFold(text)
            .split { !($0.isLetter || $0.isNumber) }
            .map(String.init)
    }

    static func matches(_ event: CalendarEvent, names: CalendarPersonNames) -> Bool {
        let wanted = ([names.fullName] + names.aliases).map(words).filter { !$0.isEmpty }
        guard !wanted.isEmpty else { return false }
        let title = words(event.title)
        let people = event.attendees.filter { !$0.isCurrentUser }.map { words($0.name) }
        return wanted.contains { name in
            people.contains(name) || (name.count > 1 && contains(title, name))
        }
    }

    /// The person's upcoming events, earliest first; at most `limit`.
    static func upcoming(_ events: [CalendarEvent], names: CalendarPersonNames, limit: Int = 5) -> [CalendarEvent] {
        Array(
            events.filter { matches($0, names: names) }
                .sorted { ($0.start, $0.title, $0.id) < ($1.start, $1.title, $1.id) }
                .prefix(limit))
    }

    static func contains(_ haystack: [String], _ needle: [String]) -> Bool {
        guard !needle.isEmpty, needle.count <= haystack.count else { return false }
        return (0...(haystack.count - needle.count)).contains { Array(haystack[$0..<($0 + needle.count)]) == needle }
    }
}

/// Which event is the person's birthday: its title, without the marker and the small words around
/// it, is exactly the person's full name. Another "Ayşe Kaya doğum günü" is never Ayşe's.
enum CalendarBirthday {
    /// "doğum günü", "birthday".
    private static let markers: [[String]] = [["doğum", "günü"], ["birthday"]].map {
        $0.map(nameComparisonFold)
    }
    /// Possessive endings split off by the apostrophe and the birthdays calendar's Turkish
    /// wording ("Ayşe Kaya adlı kişinin doğum günü").
    private static let fillers: Set<String> = Set(
        ["s", "in", "ın", "un", "ün", "nin", "nın", "nun", "nün", "adlı", "kişinin"].map(nameComparisonFold))

    static func isBirthday(_ event: CalendarEvent, fullName: String) -> Bool {
        let name = CalendarPersonMatch.words(fullName)
        guard !name.isEmpty else { return false }
        if !event.isFromBirthdayCalendar, !(event.isAllDay && event.recurrence == .yearly) { return false }
        var title = CalendarPersonMatch.words(event.title)
        guard let marker = markers.first(where: { CalendarPersonMatch.contains(title, $0) }),
            let at = (0...(title.count - marker.count)).first(where: {
                Array(title[$0..<($0 + marker.count)]) == marker
            })
        else { return false }
        title.removeSubrange(at..<(at + marker.count))
        return title.filter { !fillers.contains($0) } == name
    }

    /// The person's first birthday event.
    static func find(in events: [CalendarEvent], fullName: String) -> CalendarEvent? {
        events.filter { isBirthday($0, fullName: fullName) }.min { $0.start < $1.start }
    }
}
