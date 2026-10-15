import VaultFormat

/// A number goal's recorded values over the last `span` days. A day without a record is a gap,
/// not a zero: each run of recorded days is its own line segment.
public struct GoalValueSeries: Equatable, Sendable {
    public struct Point: Equatable, Sendable {
        /// 0 = the first day of the span, `span - 1` = today.
        public let index: Int
        public let day: CalendarDate
        public let value: Double
        /// Consecutive recorded days share a segment; a gap starts the next one.
        public let segment: Int
    }

    /// One day of the 7-day moving average.
    public struct AveragePoint: Equatable, Sendable {
        public let index: Int
        public let value: Double
        /// A day without enough records in its window ends the segment.
        public let segment: Int
    }

    public let span: Int
    public let start: CalendarDate
    public let target: Double
    public let points: [Point]
    public let averages: [AveragePoint]

    /// Days in the moving-average window (the day and the six before it).
    public static let window = 7
    /// Records a window needs before its day is drawn.
    public static let windowMinimum = 3

    /// Mean of the recorded days; nil with none.
    public var average: Double? {
        points.isEmpty ? nil : points.reduce(0) { $0 + $1.value } / Double(points.count)
    }
    /// Recorded days at or above the target.
    public var metCount: Int { points.filter { $0.value >= target }.count }
    /// The highest value, the latest day on a tie.
    public var peak: Point? { points.max { $0.value < $1.value || ($0.value == $1.value && $0.index < $1.index) } }

    public static func daily(logs: [GoalLog], target: Double, today: CalendarDate, span: Int = 90) -> Self {
        let span = max(1, span)
        let start = today.addingDays(-(span - 1)) ?? today
        // The window of the first days reaches back before the span.
        let reach = start.addingDays(-(window - 1)) ?? start
        // A day's amount as `GoalProgress` reads it: the last log wins; a wrong kind or invalid number is 0.
        let values = GoalProgress.amounts(kind: .number, logs: logs.filter { $0.day >= reach && $0.day <= today })
        var points: [Point] = []
        var segment = 0
        var previous: Int?
        for index in 0..<span {
            guard let day = start.addingDays(index), let value = values[day] else { continue }
            if let previous, previous != index - 1 { segment += 1 }
            points.append(Point(index: index, day: day, value: value, segment: segment))
            previous = index
        }
        var averages: [AveragePoint] = []
        var averageSegment = 0
        var previousAverage: Int?
        for index in 0..<span {
            // Unrecorded days stay out of the mean; too few records leave the day undrawn.
            let recorded = (index - window + 1...index).compactMap { start.addingDays($0).flatMap { values[$0] } }
            guard recorded.count >= windowMinimum else { continue }
            if let previousAverage, previousAverage != index - 1 { averageSegment += 1 }
            averages.append(
                AveragePoint(
                    index: index, value: recorded.reduce(0, +) / Double(recorded.count), segment: averageSegment))
            previousAverage = index
        }
        return Self(span: span, start: start, target: target, points: points, averages: averages)
    }
}

/// A number goal's totals per week (weekly goal) or per month (yearly goal), oldest first.
public struct GoalPeriodTotals: Equatable, Sendable {
    public struct Bucket: Equatable, Sendable {
        public let index: Int
        public let start: CalendarDate
        public let total: Double
    }

    public enum Unit: Equatable, Sendable { case week, month }

    public let unit: Unit
    public let buckets: [Bucket]
    /// The amount per bucket that keeps the goal on track: the weekly target, or a twelfth of the yearly one.
    public let pace: Double

    public var total: Double { buckets.reduce(0) { $0 + $1.total } }
    public var peak: Bucket? { buckets.max { $0.total < $1.total || ($0.total == $1.total && $0.index < $1.index) } }

    public static func make(goal: GoalDefinition, logs: [GoalLog], today: CalendarDate, count: Int = 12) -> Self? {
        guard goal.kind == .number, count > 0 else { return nil }
        let unit: Unit
        let starts: [CalendarDate]
        switch goal.period {
        case .day: return nil
        case .week:
            unit = .week
            guard let current = today.startOfWeek else { return nil }
            starts = (0..<count).reversed().compactMap { current.addingDays(-7 * $0) }
        case .year:
            unit = .month
            starts = (0..<count).reversed().compactMap { today.startOfMonth.addingMonths(-$0) }
        }
        guard let first = starts.first else { return nil }
        var totals = [Double](repeating: 0, count: starts.count)
        let values = GoalProgress.amounts(kind: .number, logs: logs.filter { $0.day >= first && $0.day <= today })
        for (day, value) in values.sorted(by: { $0.key < $1.key }) {
            guard let index = starts.lastIndex(where: { $0 <= day }) else { continue }
            totals[index] += value
        }
        let buckets = starts.indices.map { Bucket(index: $0, start: starts[$0], total: totals[$0]) }
        return Self(unit: unit, buckets: buckets, pace: unit == .week ? goal.target : goal.target / 12)
    }
}
