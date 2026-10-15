import VaultFormat

/// The reviewed week day by day against the week before: the weekly review's mini rhythm.
/// The range is the review's own device-calendar week, so it may start on a Sunday.
public struct WeeklyReviewRhythm: Sendable, Equatable {
    public struct Day: Sendable, Equatable {
        public let date: CalendarDate
        /// Events of the day; 0 for a day after `today`.
        public let events: Int
        /// Events of the day at the same position of the previous range, also for a day still to come.
        public let previousEvents: Int
        /// `full` when written, `none` when not, `notStarted` after `today`; never `partial`.
        public let writing: SummaryUnit.Writing
        public init(date: CalendarDate, events: Int, previousEvents: Int, writing: SummaryUnit.Writing) {
            self.date = date
            self.events = events
            self.previousEvents = previousEvents
            self.writing = writing
        }
    }

    public let days: [Day]
    /// Events of the measured days.
    public let events: Int
    /// Events of the previous range's days at the same positions as the measured days.
    public let previousEvents: Int
    /// The range holds `today` and has days still to come: the change compares up to the same weekday.
    public let isRunning: Bool
    public var change: Int { events - previousEvents }

    public init(days: [Day], events: Int, previousEvents: Int, isRunning: Bool) {
        self.days = days
        self.events = events
        self.previousEvents = previousEvents
        self.isRunning = isRunning
    }

    /// Day N of `range` is compared with day N of `previousRange`. Without `today` every day is measured.
    /// A day is written as ``SummaryCounts/writtenDays`` counts it; rows of one date add up.
    public static func compute(
        days: [SummaryInput.Day], range: ClosedRange<CalendarDate>, previousRange: ClosedRange<CalendarDate>,
        today: CalendarDate? = nil
    ) -> Self {
        var events: [CalendarDate: Int] = [:]
        var written: Set<CalendarDate> = []
        for row in days {
            events[row.date, default: 0] += max(0, row.events)
            if row.events > 0 || row.hasJournal { written.insert(row.date) }
        }
        var result: [Day] = []
        var total = 0
        var previousTotal = 0
        var cursor: CalendarDate? = range.lowerBound
        var previousCursor: CalendarDate? = previousRange.lowerBound
        while let date = cursor, date <= range.upperBound {
            let prior = previousCursor.flatMap { previousRange.contains($0) ? $0 : nil }
            let previous = prior.map { events[$0] ?? 0 } ?? 0
            let isMeasured = today.map { date <= $0 } ?? true
            let count = isMeasured ? events[date] ?? 0 : 0
            if isMeasured {
                total += count
                previousTotal += previous
            }
            let writing: SummaryUnit.Writing = !isMeasured ? .notStarted : written.contains(date) ? .full : .none
            result.append(Day(date: date, events: count, previousEvents: previous, writing: writing))
            cursor = date.addingDays(1)
            previousCursor = previousCursor?.addingDays(1)
        }
        let isRunning = today.map { range.contains($0) && $0 < range.upperBound } ?? false
        return Self(days: result, events: total, previousEvents: previousTotal, isRunning: isRunning)
    }
}
