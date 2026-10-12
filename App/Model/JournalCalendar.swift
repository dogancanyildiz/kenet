import Foundation
import VaultFormat

struct JournalCalendar: Sendable {
    let month: CalendarDate
    let markedDays: Set<CalendarDate>
    let levels: [CalendarDate: Int]

    /// `days` may cover more than the month; only the month's days are marked.
    init(month: CalendarDate, days: [DayOverview]) {
        let firstOfMonth = CalendarDate(year: month.year, month: month.month, day: 1)!
        self.month = firstOfMonth
        var computedLevels: [CalendarDate: Int] = [:]
        for day in days where day.date.year == firstOfMonth.year && day.date.month == firstOfMonth.month {
            let level = Self.densityLevel(for: day)
            if level > 0 {
                computedLevels[day.date] = level
            }
        }
        self.levels = computedLevels
        self.markedDays = Set(computedLevels.keys)
    }

    /// The days the month of `month` spans, for the calendar's query.
    static func range(of month: CalendarDate) -> ClosedRange<CalendarDate> {
        let first = CalendarDate(year: month.year, month: month.month, day: 1)!
        let next = JournalCalendar(month: first, days: []).adjacentMonth(1)
        return first...(next.addingDays(-1) ?? first)
    }

    static func score(for day: DayOverview) -> Int {
        day.eventCount + (day.journalCount > 0 ? 1 : 0)
    }

    static func densityLevel(score: Int) -> Int {
        if score >= 5 {
            return 3
        } else if score >= 2 {
            return 2
        } else if score == 1 {
            return 1
        } else {
            return 0
        }
    }

    static func densityLevel(for day: DayOverview) -> Int {
        densityLevel(score: score(for: day))
    }

    func level(for date: CalendarDate) -> Int {
        levels[date] ?? 0
    }

    func cells(firstWeekday: Int) -> [CalendarDate?] {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = .gmt
        let date = LocalDay.instant(for: month, timeZone: .gmt)
        let weekday = calendar.component(.weekday, from: date)
        let padding = (weekday - firstWeekday + 7) % 7
        let count = calendar.range(of: .day, in: .month, for: date)!.count
        return Array(repeating: nil, count: padding)
            + (1...count).map { CalendarDate(year: month.year, month: month.month, day: $0) }
    }

    func adjacentMonth(_ offset: Int) -> CalendarDate {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = .gmt
        let current = LocalDay.instant(for: month, timeZone: .gmt)
        guard let next = calendar.date(byAdding: .month, value: offset, to: current) else { return month }
        let parts = calendar.dateComponents([.year, .month], from: next)
        return CalendarDate(year: parts.year!, month: parts.month!, day: 1) ?? month
    }
}
