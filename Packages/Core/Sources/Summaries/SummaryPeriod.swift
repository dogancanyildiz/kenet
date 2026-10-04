import VaultFormat

public enum SummaryPeriod: String, Sendable, CaseIterable {
    case week, month
    public func bounds(containing day: CalendarDate) -> ClosedRange<CalendarDate> {
        switch self {
        case .week:
            (day.startOfWeek ?? CalendarDate("0100-01-01")!)...(day.endOfWeek ?? CalendarDate("9999-12-31")!)
        case .month: day.startOfMonth...day.endOfMonth
        }
    }
    public func previous(containing day: CalendarDate) -> ClosedRange<CalendarDate>? {
        bounds(containing: day).lowerBound.addingDays(-1).map { bounds(containing: $0) }
    }
    public func next(containing day: CalendarDate) -> ClosedRange<CalendarDate>? {
        bounds(containing: day).upperBound.addingDays(1).map { bounds(containing: $0) }
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
