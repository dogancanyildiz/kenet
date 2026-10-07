import Foundation
import VaultFormat

struct JournalCalendar {
    let month: CalendarDate
    let markedDays: Set<CalendarDate>

    init(month: CalendarDate, days: [DaySummary]) {
        self.month = CalendarDate(year: month.year, month: month.month, day: 1)!
        markedDays = Set(days.map(\.date))
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
