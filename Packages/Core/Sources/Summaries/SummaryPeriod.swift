import VaultFormat

public enum SummaryPeriod: String, Sendable, CaseIterable {
    case week, month, year
    public func bounds(containing day: CalendarDate) -> ClosedRange<CalendarDate> {
        switch self {
        case .week:
            (day.startOfWeek ?? CalendarDate("0100-01-01")!)...(day.endOfWeek ?? CalendarDate("9999-12-31")!)
        case .month: day.startOfMonth...day.endOfMonth
        case .year: day.startOfYear...day.endOfYear
        }
    }
    public func previous(containing day: CalendarDate) -> ClosedRange<CalendarDate>? {
        bounds(containing: day).lowerBound.addingDays(-1).map { bounds(containing: $0) }
    }
    public func next(containing day: CalendarDate) -> ClosedRange<CalendarDate>? {
        bounds(containing: day).upperBound.addingDays(1).map { bounds(containing: $0) }
    }
    /// The rhythm units of the period that holds `day`: each day of a week, each month of a year, and
    /// 7-day slices of a month counted from the 1st (1–7, 8–14, 15–21, 22–28, then the rest).
    /// Month slices keep the same dates in every month, so slice N of two months compares like with like.
    public func units(containing day: CalendarDate) -> [ClosedRange<CalendarDate>] {
        let range = bounds(containing: day)
        var result: [ClosedRange<CalendarDate>] = []
        var cursor: CalendarDate? = range.lowerBound
        while let start = cursor, start <= range.upperBound {
            let end: CalendarDate
            switch self {
            case .week: end = start
            case .month: end = min(start.addingDays(6) ?? range.upperBound, range.upperBound)
            case .year: end = start.endOfMonth
            }
            result.append(start...end)
            cursor = end.addingDays(1)
        }
        return result
    }
    /// The same point one period earlier: the same weekday of the week before, the same date of the
    /// month or year before. A date the earlier month lacks becomes its last day (31 March → 28 February).
    public func sameDate(before day: CalendarDate) -> CalendarDate? {
        switch self {
        case .week: day.addingDays(-7)
        case .month: day.addingMonths(-1)
        case .year: day.addingMonths(-12)
        }
    }
}

public struct SummaryCounts: Sendable, Equatable {
    public var events = 0
    public var writtenDays = 0
    public var peopleMentions = 0
    public var placeMentions = 0
    public var firstPeople = 0
    public var firstPlaces = 0
    public var createdTasks = 0
    public var completedTasks = 0
    public var overdueTasks = 0
    public var undatedTasks = 0
    public init() {}
    public func difference(from previous: Self) -> Self {
        var result = Self()
        result.events = events - previous.events
        result.writtenDays = writtenDays - previous.writtenDays
        result.peopleMentions = peopleMentions - previous.peopleMentions
        result.placeMentions = placeMentions - previous.placeMentions
        result.firstPeople = firstPeople - previous.firstPeople
        result.firstPlaces = firstPlaces - previous.firstPlaces
        result.createdTasks = createdTasks - previous.createdTasks
        result.completedTasks = completedTasks - previous.completedTasks
        result.overdueTasks = overdueTasks - previous.overdueTasks
        result.undatedTasks = undatedTasks - previous.undatedTasks
        return result
    }
}

/// One column of the rhythm strip: a day, a month slice or a month.
public struct SummaryUnit: Sendable, Equatable {
    /// How much of the unit was written. A day is written or not; a longer unit is `full` when at
    /// least half of its measured days were written.
    public enum Writing: String, Sendable {
        case full, partial, none
        /// No day of the unit has come yet.
        case notStarted
    }
    public let range: ClosedRange<CalendarDate>
    /// Events of the measured days only.
    public let events: Int
    public let writtenDays: Int
    /// Days of the unit inside the measured range: the whole unit once it has ended, 0 before it starts.
    public let measuredDays: Int
    public var writing: Writing {
        if measuredDays == 0 { return .notStarted }
        if writtenDays == 0 { return .none }
        return writtenDays * 2 >= measuredDays ? .full : .partial
    }
    public init(range: ClosedRange<CalendarDate>, events: Int, writtenDays: Int, measuredDays: Int) {
        self.range = range
        self.events = events
        self.writtenDays = writtenDays
        self.measuredDays = measuredDays
    }
}

/// A person or place whose first body link in the whole journal falls in the measured range.
public struct SummaryFirstMention: Sendable, Equatable {
    public let id: String
    public let name: String
    public let day: CalendarDate
    public init(id: String, name: String, day: CalendarDate) {
        self.id = id
        self.name = name
        self.day = day
    }
}
