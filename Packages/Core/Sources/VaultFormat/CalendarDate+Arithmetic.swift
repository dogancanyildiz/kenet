extension CalendarDate {
    /// Monday = 0, Sunday = 6, in the proleptic Gregorian calendar.
    public var weekday: Int { (ordinal - 1) % 7 }
    public var ordinal: Int {
        Self.daysBeforeYear(year) + (1..<month).reduce(0) { $0 + Self.daysInMonth(year: year, month: $1) } + day
    }
    public var startOfMonth: CalendarDate { CalendarDate(year: year, month: month, day: 1)! }
    public var endOfMonth: CalendarDate {
        CalendarDate(year: year, month: month, day: Self.daysInMonth(year: year, month: month))!
    }
    public var startOfYear: CalendarDate { CalendarDate(year: year, month: 1, day: 1)! }
    public var endOfYear: CalendarDate { CalendarDate(year: year, month: 12, day: 31)! }
    public var startOfWeek: CalendarDate? { addingDays(-weekday) }
    public var endOfWeek: CalendarDate? { addingDays(6 - weekday) }

    /// Returns nil outside supported years, including for extreme Int shifts.
    public func addingDays(_ days: Int) -> CalendarDate? {
        guard (-3_652_425...3_652_425).contains(days) else { return nil }
        let target = ordinal + days
        guard target > Self.daysBeforeYear(100), target <= Self.daysBeforeYear(10000) else { return nil }
        var low = 100
        var high = 9999
        while low < high {
            let middle = (low + high + 1) / 2
            if Self.daysBeforeYear(middle) < target { low = middle } else { high = middle - 1 }
        }
        var day = target - Self.daysBeforeYear(low)
        var month = 1
        while day > Self.daysInMonth(year: low, month: month) {
            day -= Self.daysInMonth(year: low, month: month)
            month += 1
        }
        return CalendarDate(year: low, month: month, day: day)
    }

    /// Calendar month shifts clamp the day to the destination month's last day.
    public func addingMonths(_ months: Int) -> CalendarDate? {
        guard (-120_000...120_000).contains(months) else { return nil }
        let index = year * 12 + month - 1 + months
        guard (1200..<120_000).contains(index) else { return nil }
        let nextYear = index / 12
        let nextMonth = index % 12 + 1
        return CalendarDate(
            year: nextYear, month: nextMonth, day: min(day, Self.daysInMonth(year: nextYear, month: nextMonth)))
    }

    private static func daysBeforeYear(_ year: Int) -> Int {
        let previous = year - 1
        return previous * 365 + previous / 4 - previous / 100 + previous / 400
    }
}
