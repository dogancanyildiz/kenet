import VaultFormat

/// Parser-specific annual date resolution; shared arithmetic lives in VaultFormat.
enum DateCalendar {
    static func monthLength(year: Int, month: Int) -> Int { CalendarDate.daysInMonth(year: year, month: month) }
    static func weekday(_ date: CalendarDate) -> Int { date.weekday }
    static func adding(_ days: Int, to date: CalendarDate) -> CalendarDate? { date.addingDays(days) }

    static func annual(month: Int, day: Int, year: Int?, today: CalendarDate) -> CalendarDate? {
        if let year { return CalendarDate(year: year, month: month, day: day) }
        guard (1...12).contains(month), (1...31).contains(day) else { return nil }
        for year in today.year...min(today.year + 8, 9999) {
            if let date = CalendarDate(year: year, month: month, day: day), date >= today { return date }
        }
        return nil
    }
}
