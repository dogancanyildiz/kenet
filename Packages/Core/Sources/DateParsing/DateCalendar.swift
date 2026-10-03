import VaultFormat

/// Proleptic Gregorian arithmetic, bounded by CalendarDate's supported years.
enum DateCalendar {
    static func monthLength(year: Int, month: Int) -> Int {
        switch month {
        case 2: year % 4 == 0 && (year % 100 != 0 || year % 400 == 0) ? 29 : 28
        case 4, 6, 9, 11: 30
        default: 31
        }
    }

    static func daysBeforeYear(_ year: Int) -> Int {
        let previous = year - 1
        return previous * 365 + previous / 4 - previous / 100 + previous / 400
    }

    static func ordinal(_ date: CalendarDate) -> Int {
        daysBeforeYear(date.year) + (1..<date.month).reduce(0) { $0 + monthLength(year: date.year, month: $1) }
            + date.day
    }

    /// Monday = 0, Sunday = 6; 0001-01-01 was a Monday.
    static func weekday(_ date: CalendarDate) -> Int { (ordinal(date) - 1) % 7 }

    static func adding(_ days: Int, to date: CalendarDate) -> CalendarDate? {
        guard (-3_652_425...3_652_425).contains(days) else { return nil }
        let target = ordinal(date) + days
        guard target > daysBeforeYear(100), target <= daysBeforeYear(10000) else { return nil }
        var low = 100
        var high = 9999
        while low < high {
            let middle = (low + high + 1) / 2
            if daysBeforeYear(middle) < target { low = middle } else { high = middle - 1 }
        }
        var day = target - daysBeforeYear(low)
        var month = 1
        while day > monthLength(year: low, month: month) {
            day -= monthLength(year: low, month: month)
            month += 1
        }
        return CalendarDate(year: low, month: month, day: day)
    }

    static func annual(month: Int, day: Int, year: Int?, today: CalendarDate) -> CalendarDate? {
        if let year { return CalendarDate(year: year, month: month, day: day) }
        guard (1...12).contains(month), (1...31).contains(day) else { return nil }
        for year in today.year...min(today.year + 8, 9999) {
            if let date = CalendarDate(year: year, month: month, day: day), date >= today { return date }
        }
        return nil
    }
}
