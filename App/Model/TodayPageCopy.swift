import Foundation
import GoalTracking
import VaultFormat

/// Hour-banded greeting for Today's künye sentence (unit-tested).
enum TodayGreeting: Equatable, Sendable {
    case morning
    case afternoon
    case evening

    /// Local hour in `0...23`. Bands: 05–12 morning, 12–18 afternoon, 18–05 evening.
    static func resolve(hour: Int) -> Self {
        let clamped = ((hour % 24) + 24) % 24
        if clamped >= 5 && clamped < 12 { return .morning }
        if clamped >= 12 && clamped < 18 { return .afternoon }
        return .evening
    }

    static func resolve(date: Date, calendar: Calendar) -> Self {
        resolve(hour: calendar.component(.hour, from: date))
    }

    /// String Catalog key for the spoken greeting word including the period.
    var catalogKey: String.LocalizationValue {
        switch self {
        case .morning: "Günaydın."
        case .afternoon: "İyi günler."
        case .evening: "İyi akşamlar."
        }
    }

    func text(locale: Locale) -> String {
        String(
            localized: catalogKey, bundle: PresentationLocalization.bundle(locale), locale: locale)
    }
}

/// Pure builders for Today's ``InkSummaryLine`` parts (unit-tested).
enum TodaySummaryCopy: Sendable {
    static let eventSymbol = "pencil.line"
    static let taskSymbol = "checkmark.square"
    static let goalSymbol = "target"

    /// Greeting + count parts. All-zero counts leave only the greeting (screens.md).
    static func parts(
        greeting: TodayGreeting?, events: Int, tasks: Int, goals: Int, locale: Locale
    ) -> [InkSummaryLine.Part] {
        let resolved = PresentationLocalization.resolvedLocale(locale)
        let bundle = PresentationLocalization.bundle(resolved)
        var parts: [InkSummaryLine.Part] = []
        if let greeting {
            parts.append(.text(greeting.text(locale: resolved)))
        }
        if events <= 0 && tasks <= 0 && goals <= 0 {
            return parts
        }

        let turkish = TurkishSuffix.isTurkish(resolved)
        if turkish {
            parts.append(.text(String(localized: "Bugün", bundle: bundle, locale: resolved)))
        } else {
            parts.append(
                .text(
                    String(
                        localized: "Today you have", bundle: bundle, locale: resolved)))
        }

        var counts: [(Int, String, String)] = []
        if events > 0 {
            counts.append(
                (
                    events,
                    String(localized: "\(events) olay", bundle: bundle, locale: resolved),
                    eventSymbol
                ))
        }
        if tasks > 0 {
            counts.append(
                (
                    tasks,
                    String(localized: "\(tasks) görev", bundle: bundle, locale: resolved),
                    taskSymbol
                ))
        }
        if goals > 0 {
            counts.append(
                (
                    goals,
                    String(localized: "\(goals) hedef", bundle: bundle, locale: resolved),
                    goalSymbol
                ))
        }

        for (index, item) in counts.enumerated() {
            let noun = nounOnly(from: item.1, count: item.0)
            let isLast = index == counts.count - 1
            let isSecondLast = index == counts.count - 2
            let suffix: String
            if !isLast && !isSecondLast {
                suffix = ","
            } else if isLast {
                suffix = turkish ? "" : ""
            } else {
                suffix = ""
            }
            parts.append(.count(item.0, noun, symbol: item.2, suffix: suffix))
            if isSecondLast {
                parts.append(
                    .text(
                        turkish
                            ? String(localized: "ve", bundle: bundle, locale: resolved)
                            : String(localized: "and", bundle: bundle, locale: resolved)))
            }
        }
        if turkish {
            parts.append(.text(String(localized: "var.", bundle: bundle, locale: resolved)))
        } else {
            parts.append(.text("."))
        }
        return parts
    }

    /// Full spoken / equality string: spaces between parts, no space before attached count suffixes.
    static func spoken(_ parts: [InkSummaryLine.Part]) -> String {
        InkSummaryLine.spoken(parts)
    }

    /// Strips the leading count from a localized "%lld noun" string.
    static func nounOnly(from localizedCount: String, count: Int) -> String {
        let prefix = "\(count)"
        var rest = localizedCount
        if rest.hasPrefix(prefix) {
            rest = String(rest.dropFirst(prefix.count))
        }
        return rest.trimmingCharacters(in: .whitespaces)
    }
}

/// Insight chips under the künye (unit-tested). Nil / zero values stay hidden.
enum TodayInsightChip: Equatable, Sendable {
    case streak(days: Int, goalID: String)
    case yesterdayEvents(count: Int, day: CalendarDate)
    case lastMeeting(name: String, entityID: String)

    struct Inputs: Equatable, Sendable {
        var longestDailyStreak: Int
        var streakGoalID: String?
        var yesterdayEventCount: Int
        var yesterday: CalendarDate
        var lastPersonName: String?
        var lastPersonID: String?
    }

    static func make(from inputs: Inputs) -> [TodayInsightChip] {
        var chips: [TodayInsightChip] = []
        if inputs.longestDailyStreak > 0, let goalID = inputs.streakGoalID {
            chips.append(.streak(days: inputs.longestDailyStreak, goalID: goalID))
        }
        if inputs.yesterdayEventCount > 0 {
            chips.append(
                .yesterdayEvents(count: inputs.yesterdayEventCount, day: inputs.yesterday))
        }
        if let name = inputs.lastPersonName, let id = inputs.lastPersonID, !name.isEmpty {
            chips.append(.lastMeeting(name: name, entityID: id))
        }
        return chips
    }

    /// Longest current streak among daily goals; ties keep the earlier definition order.
    static func longestDailyStreak(
        goals: [GoalDefinition], statuses: [String: GoalStatus]
    ) -> (days: Int, goalID: String?) {
        var best = 0
        var bestID: String?
        for goal in goals where goal.period == .day {
            let value = statuses[goal.key]?.streak ?? 0
            if value > best {
                best = value
                bestID = goal.id
            }
        }
        return (best, best > 0 ? bestID : nil)
    }

    /// Most recent person encounter on or before `today`, within the last `windowDays` days.
    static func lastPerson(
        people: [EntitySummary], encounters: [String: CalendarDate], today: CalendarDate,
        windowDays: Int = 7
    ) -> (id: String, name: String)? {
        let earliest = today.addingDays(-(windowDays - 1)) ?? today
        var best: (id: String, name: String, day: CalendarDate)?
        for person in people where person.kind == "person" {
            guard let day = encounters[person.id], day >= earliest, day <= today else { continue }
            if let current = best {
                if day > current.day || (day == current.day && person.name < current.name) {
                    best = (person.id, person.name, day)
                }
            } else {
                best = (person.id, person.name, day)
            }
        }
        return best.map { ($0.id, $0.name) }
    }

    func title(locale: Locale) -> String {
        let bundle = PresentationLocalization.bundle(locale)
        switch self {
        case .streak(let days, _):
            return String(localized: "\(days) gün zincir", bundle: bundle, locale: locale)
        case .yesterdayEvents(let count, _):
            return String(localized: "Dün \(count) olay", bundle: bundle, locale: locale)
        case .lastMeeting(let name, _):
            return String(localized: "Son görüşme \(name)", bundle: bundle, locale: locale)
        }
    }

    var systemImage: String? {
        switch self {
        case .streak: "flame"
        case .yesterdayEvents: nil
        case .lastMeeting: nil
        }
    }
}

/// Week-strip day math (unit-tested). Same rule as ``InkWeekStrip/daysInWeek(containing:calendar:)``.
enum TodayWeekStripMath: Sendable {
    /// Seven dates for the week containing `date`, ordered from the calendar's first weekday.
    static func daysInWeek(containing date: Date, calendar: Calendar) -> [Date] {
        let start = calendar.startOfDay(for: date)
        let weekday = calendar.component(.weekday, from: start)
        let first = calendar.firstWeekday
        let delta = (weekday - first + 7) % 7
        let weekStart = calendar.date(byAdding: .day, value: -delta, to: start) ?? start
        return (0..<7).compactMap { calendar.date(byAdding: .day, value: $0, to: weekStart) }
    }

    /// A day is selectable when it is on or before `today` (future days stay passive).
    static func isSelectable(_ day: Date, today: Date, calendar: Calendar) -> Bool {
        calendar.startOfDay(for: day) <= calendar.startOfDay(for: today)
    }
}

/// Above-the-fold budget for jury condition 4 (unit-tested).
enum TodayAboveFoldBudget: Sendable {
    /// Open task rows shown on Today before the "N görev daha" disclosure.
    static let maxVisibleTaskRows = 3
    /// Fold only when at least this many open tasks would hide.
    static let minimumHiddenRows = 2

    /// Approximate chrome below the scroll content (tab bar + quick-entry shelf + home).
    static let bottomChromeHeight: CGFloat = 150

    static let mastheadHeight: CGFloat = 72
    static let weekStripHeight: CGFloat = 56
    static let summaryHeight: CGFloat = 48
    static let chipsHeight: CGFloat = 44
    static let sectionHeaderHeight: CGFloat = 28
    static let goalColumnHeight: CGFloat = 96
    static let taskRowHeight: CGFloat = 56
    static let eventRowHeight: CGFloat = 52
    static let calendarRowHeight: CGFloat = 52
    static let sectionGap: CGFloat = 16

    /// Whether Today should fold open tasks to ``maxVisibleTaskRows``.
    /// - Parameters:
    ///   - foldsAllowed: false on regular-width layouts (iPad / Mac).
    ///   - calendarEventCount: device-calendar rows between tasks and events.
    ///   - viewportHeight: measured scroll viewport (not a hard-coded phone constant).
    static func shouldFoldTasks(
        goalCount: Int, openTaskCount: Int, eventCount: Int, calendarEventCount: Int = 0,
        viewportHeight: CGFloat, foldsAllowed: Bool = true
    ) -> Bool {
        guard foldsAllowed else { return false }
        let hidden = openTaskCount - maxVisibleTaskRows
        guard hidden >= minimumHiddenRows else { return false }
        let usable = viewportHeight - bottomChromeHeight
        guard usable > 0 else { return false }
        let goals = goalCount > 0
            ? sectionHeaderHeight + goalColumnHeight + sectionGap : 0
        let tasks = sectionHeaderHeight
            + CGFloat(openTaskCount) * taskRowHeight + sectionGap
        let calendar = calendarEventCount > 0
            ? sectionHeaderHeight + CGFloat(calendarEventCount) * calendarRowHeight + sectionGap
            : 0
        let events = eventCount > 0
            ? sectionHeaderHeight + eventRowHeight + sectionGap : 0
        let top =
            mastheadHeight + weekStripHeight + summaryHeight + chipsHeight + sectionGap
        return top + goals + tasks + calendar + events > usable
    }

    /// Section order from the top of the page through the first event (for the unit check).
    static func aboveFoldSections(
        hasGoals: Bool, hasTasks: Bool, hasEvents: Bool
    ) -> [String] {
        var sections = ["masthead", "week", "summary", "chips"]
        if hasGoals { sections.append("goals") }
        if hasTasks { sections.append("tasks") }
        if hasEvents { sections.append("events") }
        return sections
    }
}

/// Day-ring progress for ``InkDayHeader`` from daily goal completion (unit-tested).
enum TodayDayRing: Sendable {
    static func progress(completed: Int, total: Int) -> Double {
        guard total > 0 else { return 0 }
        return min(1, max(0, Double(completed) / Double(total)))
    }

    static func remaining(completed: Int, total: Int) -> Int {
        max(0, total - completed)
    }

    static func showsRing(total: Int) -> Bool { total > 0 }

    static func accessibilityLabel(remaining: Int, locale: Locale) -> String {
        String(
            localized: "\(remaining) hedef kaldı",
            bundle: PresentationLocalization.bundle(locale), locale: locale)
    }
}

/// Journal file path used by Mac Days selection (`journal/YYYY-MM-DD.md`).
enum TodayDayPath {
    static func file(for day: CalendarDate) -> String { "journal/\(day).md" }

    static func day(fromFile path: String) -> CalendarDate? {
        guard path.hasPrefix("journal/"), path.hasSuffix(".md") else { return nil }
        let stamp = String(path.dropFirst("journal/".count).dropLast(3))
        return CalendarDate(stamp)
    }
}
