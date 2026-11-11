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

    /// A new event on `day`: today starts at the next full hour, another day at 09:00; one hour long.
    static func new(
        on day: CalendarDate, now: Date, calendarID: String?, timeZone: TimeZone = .current
    ) -> CalendarEventDraft {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = timeZone
        let dayStart = calendar.startOfDay(for: LocalDay.instant(for: day, timeZone: timeZone))
        var start = calendar.date(bySettingHour: 9, minute: 0, second: 0, of: dayStart) ?? dayStart
        if LocalDay.today(at: now, timeZone: timeZone) == day,
            let hour = calendar.dateInterval(of: .hour, for: now)?.end,
            calendar.isDate(hour, inSameDayAs: dayStart)
        {
            start = hour
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
            copy.end = max(copy.start, calendar.startOfDay(for: end))
        } else if end < start {
            copy.end = start
        }
        return copy
    }

    /// Choices for saving a change to `original`: a changed repeat rule only applies from here on.
    static func spans(saving draft: CalendarEventDraft, over original: CalendarEvent) -> [CalendarEditSpan] {
        guard original.recurrence != .none else { return [.thisEvent] }
        return draft.recurrence == original.recurrence ? [.thisEvent, .futureEvents] : [.futureEvents]
    }
}

/// Matches calendar events to a person by name or alias (decision 2026-11-11). Whole words, with the
/// recognizer's name fold: case, Turkish dotted and dotless i.
enum CalendarPersonMatch {
    static func words(_ text: String) -> [String] {
        nameComparisonFold(text)
            .split { !($0.isLetter || $0.isNumber) }
            .map(String.init)
    }

    static func matches(_ event: CalendarEvent, names: [String]) -> Bool {
        let wanted = names.map(words).filter { !$0.isEmpty }
        guard !wanted.isEmpty else { return false }
        let title = words(event.title)
        let people = event.attendees.filter { !$0.isCurrentUser }.map { words($0.name) }
        return wanted.contains { name in
            contains(title, name) || people.contains(name)
        }
    }

    /// The person's upcoming events, earliest first; at most `limit`.
    static func upcoming(_ events: [CalendarEvent], names: [String], limit: Int = 5) -> [CalendarEvent] {
        Array(
            events.filter { matches($0, names: names) }
                .sorted { ($0.start, $0.title, $0.id) < ($1.start, $1.title, $1.id) }
                .prefix(limit))
    }

    private static func contains(_ haystack: [String], _ needle: [String]) -> Bool {
        guard needle.count <= haystack.count else { return false }
        for index in 0...(haystack.count - needle.count)
        where Array(haystack[index..<(index + needle.count)]) == needle {
            return true
        }
        return false
    }
}

/// Which matched event counts as the person's birthday.
enum CalendarBirthday {
    /// Words that mark a birthday title, folded: "doğum günü", "birthday".
    private static let markers: [[String]] = [["doğum", "günü"], ["birthday"]].map {
        $0.map(nameComparisonFold)
    }

    static func isBirthday(_ event: CalendarEvent) -> Bool {
        if event.isFromBirthdayCalendar { return true }
        guard event.isAllDay, event.recurrence == .yearly else { return false }
        let title = CalendarPersonMatch.words(event.title)
        return markers.contains { marker in
            title.count >= marker.count
                && (0...(title.count - marker.count)).contains { Array(title[$0..<($0 + marker.count)]) == marker }
        }
    }

    /// The first birthday among the person's matched events.
    static func find(in events: [CalendarEvent], names: [String]) -> CalendarEvent? {
        events.filter { CalendarPersonMatch.matches($0, names: names) && isBirthday($0) }
            .min { $0.start < $1.start }
    }
}
