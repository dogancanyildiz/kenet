import VaultFormat

public struct GoalAmount: Sendable, Equatable {
    public let done: Double
    public let target: Double
    public var isComplete: Bool { done >= target }
    public var fraction: Double { min(1, done / target) }
    public init(done: Double, target: Double) {
        self.done = done
        self.target = target
    }
}

public struct GoalStatus: Sendable, Equatable {
    public let periodStart: CalendarDate
    public let periodEnd: CalendarDate
    public let progress: GoalAmount
    public let streak: Int
    public let longestStreak: Int
    /// The current period has not yet reached its target; the streak starts at the previous period.
    public let isPendingToday: Bool
    public let yearDone: Double
    public let yearProgress: GoalAmount?
}

public enum GoalDayMark: String, Sendable { case none, partial, full }

extension GoalPeriod {
    func bounds(on day: CalendarDate) -> (start: CalendarDate, end: CalendarDate) {
        switch self {
        case .day: (day, day)
        case .week: (day.startOfWeek ?? CalendarDate("0100-01-01")!, day.endOfWeek ?? CalendarDate("9999-12-31")!)
        case .year: (day.startOfYear, day.endOfYear)
        }
    }
    func previous(before start: CalendarDate) -> CalendarDate? {
        start.addingDays(-1).map { bounds(on: $0).start }
    }
}
