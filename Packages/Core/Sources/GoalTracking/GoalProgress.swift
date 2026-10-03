import VaultFormat

public enum GoalProgress {
    public static func compute(definition: GoalDefinition, logs: [GoalLog], today: CalendarDate) -> GoalStatus {
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
        var streak = 0
        while let current = cursor, successful.contains(current) {
            streak += 1
            cursor = definition.period.previous(before: current)
        }
        var longest = 0
        var run = 0
        var last: CalendarDate?
        for start in successful.sorted() {
            run = definition.period.previous(before: start) == last && last != nil ? run + 1 : 1
            longest = max(longest, run)
            last = start
        }
        return GoalStatus(
            periodStart: bounds.start, periodEnd: bounds.end, progress: progress,
            streak: streak, longestStreak: longest, isPendingToday: !progress.isComplete,
            yearDone: yearDone,
            yearProgress: definition.period == .year ? GoalAmount(done: yearDone, target: definition.target) : nil)
    }

    public static func heatmap(definition: GoalDefinition, logs: [GoalLog], from: CalendarDate, to: CalendarDate)
        -> [CalendarDate: GoalDayMark]
    {
        guard from <= to else { return [:] }
        let daily = amounts(definition: definition, logs: logs)
        var marks: [CalendarDate: GoalDayMark] = [:]
        var cursor: CalendarDate? = from
        while let day = cursor, day <= to {
            let amount = daily[day] ?? 0
            marks[day] =
                amount <= 0
                ? GoalDayMark.none : (definition.kind == .boolean || amount >= definition.target ? .full : .partial)
            cursor = day.addingDays(1)
        }
        return marks
    }

    private static func amounts(definition: GoalDefinition, logs: [GoalLog]) -> [CalendarDate: Double] {
        var result: [CalendarDate: Double] = [:]
        for log in logs {
            let amount: Double
            switch (definition.kind, log.value) {
            case (.boolean, .boolean(let done)): amount = done ? 1 : 0
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
