import VaultFormat

/// The written days of one calendar year, month by month: the Özetler year map.
/// A day is written as ``SummaryCounts/writtenDays`` counts it: an event or a non-empty Journal.
public struct YearWritingCalendar: Sendable, Equatable {
    public enum Day: String, Sendable {
        case unwritten
        /// Journal text and no event.
        case journal
        /// At least one event.
        case events
    }
    public struct Month: Sendable, Equatable {
        /// 1 to 12.
        public let month: Int
        /// The measured days from the 1st, in order. Days after the measured end are left out,
        /// so a month that has not begun is empty.
        public let days: [Day]
        public var writtenDays: Int { days.count { $0 != .unwritten } }
        public init(month: Int, days: [Day]) {
            self.month = month
            self.days = days
        }
    }

    public let year: Int
    /// Twelve months from January; empty when the year is outside the calendar's range.
    public let months: [Month]
    /// The last measured day: `today` in the running year, the year's last day once it has ended
    /// or without `today`, nil for a year that has not begun. A period that has not begun is counted
    /// whole by ``PeriodSummary``; the screen never shows one.
    public let measuredEnd: CalendarDate?
    public var writtenDays: Int { months.reduce(0) { $0 + $1.writtenDays } }

    public init(year: Int, months: [Month], measuredEnd: CalendarDate?) {
        self.year = year
        self.months = months
        self.measuredEnd = measuredEnd
    }

    /// The state of a measured day of this year; nil for another year and for a day after the measured end.
    public func day(_ date: CalendarDate) -> Day? {
        guard date.year == year, date.month <= months.count else { return nil }
        let days = months[date.month - 1].days
        return date.day <= days.count ? days[date.day - 1] : nil
    }

    /// `today` ends the running year like it ends ``PeriodSummary``'s measured range: a day file
    /// dated after it does not count. Rows of other years are ignored; rows of one date add up.
    public static func compute(days: [SummaryInput.Day], year: Int, today: CalendarDate? = nil) -> Self {
        guard let start = CalendarDate(year: year, month: 1, day: 1),
            let end = CalendarDate(year: year, month: 12, day: 31)
        else { return Self(year: year, months: [], measuredEnd: nil) }
        let measuredEnd: CalendarDate? =
            switch today {
            case .none: end
            case .some(let today) where today < start: nil
            case .some(let today): min(today, end)
            }
        var events: Set<CalendarDate> = []
        var journal: Set<CalendarDate> = []
        for row in days where row.date.year == year {
            if row.events > 0 { events.insert(row.date) }
            if row.hasJournal { journal.insert(row.date) }
        }
        let months = (1...12).map { month in
            var states: [Day] = []
            if let measuredEnd {
                for number in 1...CalendarDate.daysInMonth(year: year, month: month) {
                    guard let date = CalendarDate(year: year, month: month, day: number), date <= measuredEnd else {
                        break
                    }
                    states.append(events.contains(date) ? .events : journal.contains(date) ? .journal : .unwritten)
                }
            }
            return Month(month: month, days: states)
        }
        return Self(year: year, months: months, measuredEnd: measuredEnd)
    }
}
