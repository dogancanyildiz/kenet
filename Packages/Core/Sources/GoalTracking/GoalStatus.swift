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
    /// Daily goals: success percent of the last 30 elapsed days, 0...100. Nil for other periods and
    /// when no day is measured yet.
    public let score: Int?
    public let yearDone: Double
    public let yearProgress: GoalAmount?
    public var completionDate: CalendarDate?

    public init(
        periodStart: CalendarDate, periodEnd: CalendarDate, progress: GoalAmount,
        streak: Int, longestStreak: Int, isPendingToday: Bool, score: Int?,
        yearDone: Double, yearProgress: GoalAmount?, completionDate: CalendarDate? = nil
    ) {
        self.periodStart = periodStart
        self.periodEnd = periodEnd
        self.progress = progress
        self.streak = streak
        self.longestStreak = longestStreak
        self.isPendingToday = isPendingToday
        self.score = score
        self.yearDone = yearDone
        self.yearProgress = yearProgress
        self.completionDate = completionDate
    }
}

/// `forgiven` is a forgiven day with no contribution; `forgivenPartial` one below the target but above zero.
public enum GoalDayMark: String, Sendable {
    case none, partial, full, forgiven, forgivenPartial

    /// A forgiven miss of a daily goal, with or without a partial contribution.
    public var isForgiven: Bool { self == .forgiven || self == .forgivenPartial }
}

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
