import VaultFormat

public enum GoalProgress {
    public static func compute(definition: GoalDefinition, logs: [GoalLog], today: CalendarDate) -> GoalStatus {
        if definition.kind == .milestone {
            let daily = amounts(definition: definition, logs: logs)
            let date = daily.keys.filter { $0.year == today.year && $0 <= today && daily[$0] == 1 }.min()
            return GoalStatus(
                periodStart: today.startOfYear, periodEnd: today.endOfYear,
                progress: GoalAmount(done: date == nil ? 0 : 1, target: 1), streak: 0, longestStreak: 0,
                isPendingToday: date == nil, score: nil, yearDone: date == nil ? 0 : 1, yearProgress: nil,
                completionDate: date)
        }
        let daily = amounts(definition: definition, logs: logs.filter { $0.day <= today })
        var totals: [CalendarDate: Double] = [:]
        var yearDone = 0.0
        for (day, amount) in daily.sorted(by: { $0.key < $1.key }) {
            let start = definition.period.bounds(on: day).start
            totals[start] = adding(totals[start] ?? 0, amount)
            if day.year == today.year { yearDone = adding(yearDone, amount) }
        }
        let bounds = definition.period.bounds(on: today)
        let progress = GoalAmount(done: totals[bounds.start] ?? 0, target: definition.target)
        let successful = Set(totals.filter { $0.value >= definition.target }.map(\.key))
        var cursor = progress.isComplete ? bounds.start : definition.period.previous(before: bounds.start)
        // Today is still open, so it can still forgive yesterday's miss: the chain is not dropped yet.
        if definition.period == .day, !progress.isComplete, let yesterday = cursor, !successful.contains(yesterday),
            canForgive(yesterday, successful: successful), let before = yesterday.addingDays(-1)
        {
            cursor = before
        }
        var streak = 0
        while let current = cursor {
            if successful.contains(current) {
                streak += 1
            } else if isForgiven(current, today: today, period: definition.period, successful: successful) {
                // A forgiven miss keeps the chain and is not counted.
            } else {
                break
            }
            cursor = definition.period.previous(before: current)
        }
        let longest =
            definition.period == .day
            ? dailyLongest(successful: successful) : periodLongest(definition: definition, successful: successful)
        // Today joins the score only once it succeeds.
        let scoreEnd = progress.isComplete ? today : today.addingDays(-1)
        let score =
            definition.period == .day
            ? scoreEnd.flatMap { dailyScore(daily: daily, through: $0, target: definition.target) } : nil
        return GoalStatus(
            periodStart: bounds.start, periodEnd: bounds.end, progress: progress,
            streak: streak, longestStreak: longest, isPendingToday: !progress.isComplete, score: score,
            yearDone: yearDone,
            yearProgress: definition.period == .year ? GoalAmount(done: yearDone, target: definition.target) : nil)
    }

    /// Daily goals: success percent of the 30 days ending at `end`, both ends included. Nil for other
    /// periods and when no day is measured.
    public static func score(definition: GoalDefinition, logs: [GoalLog], through end: CalendarDate) -> Int? {
        guard definition.period == .day else { return nil }
        let daily = amounts(definition: definition, logs: logs.filter { $0.day <= end })
        return dailyScore(daily: daily, through: end, target: definition.target)
    }

    public static func heatmap(
        definition: GoalDefinition, logs: [GoalLog], from: CalendarDate, to: CalendarDate,
        today: CalendarDate? = nil
    ) -> [CalendarDate: GoalDayMark] {
        guard definition.kind != .milestone, from <= to else { return [:] }
        let daily = amounts(definition: definition, logs: logs)
        let successful = Set(daily.filter { $0.value >= definition.target }.map(\.key))
        var marks: [CalendarDate: GoalDayMark] = [:]
        var cursor: CalendarDate? = from
        while let day = cursor, day <= to {
            let amount = daily[day] ?? 0
            let contribution: GoalDayMark =
                amount <= 0
                ? .none : (definition.kind == .boolean || amount >= definition.target ? .full : .partial)
            if let today, isForgiven(day, today: today, period: definition.period, successful: successful) {
                // The day's own contribution stays visible under the forgiven mark.
                marks[day] = contribution == .partial ? .forgivenPartial : .forgiven
            } else {
                marks[day] = contribution
            }
            cursor = day.addingDays(1)
        }
        return marks
    }

    /// Daily only. A past miss whose next day succeeded and that `canForgive` allows.
    private static func isForgiven(
        _ start: CalendarDate, today: CalendarDate, period: GoalPeriod, successful: Set<CalendarDate>
    ) -> Bool {
        guard period == .day, start < today, !successful.contains(start), let next = start.addingDays(1) else {
            return false
        }
        return canForgive(start, successful: successful) && successful.contains(next)
    }

    /// Daily only. A miss can be forgiven when the two days before it both succeeded. A forgiven day is not a
    /// success, so it cannot be one of those two days.
    private static func canForgive(_ day: CalendarDate, successful: Set<CalendarDate>) -> Bool {
        guard let previous = day.addingDays(-1), let earlier = day.addingDays(-2) else { return false }
        return successful.contains(previous) && successful.contains(earlier)
    }

    /// Daily only. Walks successes, not calendar days, so one stray old date cannot stretch the work.
    /// Two successes with exactly one day between them stay in one run when `canForgive` allows the day between.
    private static func dailyLongest(successful: Set<CalendarDate>) -> Int {
        var longest = 0
        var run = 0
        var last: CalendarDate?
        for day in successful.sorted() {
            let gap = last.map { day.ordinal - $0.ordinal }
            let forgiven = gap == 2 && day.addingDays(-1).map { canForgive($0, successful: successful) } == true
            run = gap == 1 || forgiven ? run + 1 : 1
            longest = max(longest, run)
            last = day
        }
        return longest
    }

    private static func periodLongest(definition: GoalDefinition, successful: Set<CalendarDate>) -> Int {
        var longest = 0
        var run = 0
        var last: CalendarDate?
        for start in successful.sorted() {
            run = definition.period.previous(before: start) == last && last != nil ? run + 1 : 1
            longest = max(longest, run)
            last = start
        }
        return longest
    }

    /// The 30 days ending at `end`. Days before the first log are omitted. Nil when no day is measured.
    private static func dailyScore(daily: [CalendarDate: Double], through end: CalendarDate, target: Double) -> Int? {
        guard let start = daily.keys.min(), end >= start else { return nil }
        let first = end.addingDays(-29).map { max($0, start) } ?? start
        var total = 0
        var hits = 0
        var cursor: CalendarDate? = first
        while let day = cursor, day <= end {
            total += 1
            if (daily[day] ?? 0) >= target { hits += 1 }
            cursor = day.addingDays(1)
        }
        return total > 0 ? (hits * 100) / total : nil
    }

    private static func amounts(definition: GoalDefinition, logs: [GoalLog]) -> [CalendarDate: Double] {
        amounts(kind: definition.kind, logs: logs)
    }

    /// Each day's amount: the day's last log wins, in log order. A log of the wrong kind or an invalid
    /// number counts as 0. The value chart (`GoalValueSeries`, `GoalPeriodTotals`) reads days the same way.
    static func amounts(kind: GoalKind, logs: [GoalLog]) -> [CalendarDate: Double] {
        var result: [CalendarDate: Double] = [:]
        for log in logs {
            let amount: Double
            switch (kind, log.value) {
            case (.boolean, .boolean(let done)), (.milestone, .boolean(let done)): amount = done ? 1 : 0
            case (.number, .number(let value)) where log.value.isValid: amount = value
            default: amount = 0
            }
            result[log.day] = amount
        }
        return result
    }
    private static func adding(_ lhs: Double, _ rhs: Double) -> Double {
        let sum = lhs + rhs
        return sum.isFinite ? sum : Double.greatestFiniteMagnitude
    }
}
