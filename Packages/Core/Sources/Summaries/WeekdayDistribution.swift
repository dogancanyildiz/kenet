import VaultFormat

/// Per-weekday written-day ratios and event counts for a period (Monday = 0 … Sunday = 6):
/// the "Haftanın günleri" section in Özetler.
/// A day is written as ``SummaryCounts/writtenDays`` counts it: an event or a non-empty Journal.
public struct WeekdayDistribution: Sendable, Equatable {
    public struct Entry: Identifiable, Sendable, Equatable {
        /// Monday = 0 … Sunday = 6 (`CalendarDate.weekday`).
        public let weekday: Int
        public let writtenDays: Int
        public let totalDays: Int
        public let events: Int

        public var id: Int { weekday }
        public var ratio: Double {
            guard totalDays > 0 else { return 0 }
            return Double(writtenDays) / Double(totalDays)
        }

        public init(weekday: Int, writtenDays: Int, totalDays: Int, events: Int) {
            self.weekday = weekday
            self.writtenDays = writtenDays
            self.totalDays = totalDays
            self.events = events
        }
    }

    /// Seven entries from Monday (0) through Sunday (6).
    public let entries: [Entry]
    /// The weekday (0…6) with the highest written-day ratio; ties break by higher event count,
    /// then earlier weekday (Monday first). `nil` when no day was written.
    public let leadingWeekday: Int?

    public var writtenDays: Int { entries.reduce(0) { $0 + $1.writtenDays } }
    public var totalDays: Int { entries.reduce(0) { $0 + $1.totalDays } }

    public init(entries: [Entry], leadingWeekday: Int?) {
        self.entries = entries
        self.leadingWeekday = leadingWeekday
    }

    /// Measured days follow ``PeriodSummary`` and ``YearWritingCalendar``: the whole period once
    /// ended or without `today`, its start through `today` while running, and no days when `today`
    /// is before the period starts. Rows outside the measured range are ignored; rows of one date add up.
    public static func compute(
        days: [SummaryInput.Day],
        period: SummaryPeriod,
        containing day: CalendarDate,
        today: CalendarDate? = nil
    ) -> Self {
        let range = period.bounds(containing: day)
        let measured: ClosedRange<CalendarDate>? =
            switch today {
            case .none:
                range
            case .some(let today) where today < range.lowerBound:
                nil
            case .some(let today):
                range.lowerBound...min(today, range.upperBound)
            }

        var eventsByDate: [CalendarDate: Int] = [:]
        var writtenDates: Set<CalendarDate> = []
        if let measured {
            for row in days where measured.contains(row.date) {
                eventsByDate[row.date, default: 0] += max(0, row.events)
                if row.events > 0 || row.hasJournal {
                    writtenDates.insert(row.date)
                }
            }
        }

        var writtenCount = Array(repeating: 0, count: 7)
        var totalCount = Array(repeating: 0, count: 7)
        var eventCount = Array(repeating: 0, count: 7)

        if let measured {
            var cursor: CalendarDate? = measured.lowerBound
            while let date = cursor, date <= measured.upperBound {
                let index = date.weekday
                totalCount[index] += 1
                eventCount[index] += eventsByDate[date] ?? 0
                if writtenDates.contains(date) {
                    writtenCount[index] += 1
                }
                cursor = date.addingDays(1)
            }
        }

        let entries = (0..<7).map { index in
            Entry(
                weekday: index,
                writtenDays: writtenCount[index],
                totalDays: totalCount[index],
                events: eventCount[index]
            )
        }

        let leadingWeekday = entries.filter { $0.totalDays > 0 && $0.writtenDays > 0 }.max { lhs, rhs in
            let lhsCross = lhs.writtenDays * rhs.totalDays
            let rhsCross = rhs.writtenDays * lhs.totalDays
            if lhsCross != rhsCross { return lhsCross < rhsCross }
            if lhs.events != rhs.events { return lhs.events < rhs.events }
            return lhs.weekday > rhs.weekday
        }?.weekday

        return Self(entries: entries, leadingWeekday: leadingWeekday)
    }
}
