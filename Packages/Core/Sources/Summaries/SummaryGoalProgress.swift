import GoalTracking
import VaultFormat

extension SummaryInput.Goal {
    func progress(in range: ClosedRange<CalendarDate>) -> (amount: GoalAmount, contribution: Double, status: GoalStatus)
    {
        let status = GoalProgress.compute(definition: definition, logs: logs, today: range.upperBound)
        if definition.kind == .milestone {
            var contribution = 0.0
            for year in range.lowerBound.year...range.upperBound.year {
                let end =
                    year == range.upperBound.year ? range.upperBound : CalendarDate(year: year, month: 12, day: 31)!
                let date = GoalProgress.compute(definition: definition, logs: logs, today: end).completionDate
                if date.map(range.contains) == true { contribution += 1 }
            }
            return (status.progress, contribution, status)
        }
        var contribution = 0.0
        var cursor: CalendarDate? = range.lowerBound
        var weeks: Set<CalendarDate> = []
        var days = 0
        while let day = cursor, day <= range.upperBound {
            days += 1
            weeks.insert(day.startOfWeek ?? day)
            let amount = GoalProgress.compute(definition: definition, logs: logs.filter { $0.day == day }, today: day)
                .progress.done
            let sum = contribution + amount
            contribution = sum.isFinite ? sum : Double.greatestFiniteMagnitude
            cursor = day.addingDays(1)
        }
        if definition.period == .year { return (status.progress, contribution, status) }
        let multiplier = definition.period == .day ? days : weeks.count
        let target = definition.target * Double(multiplier)
        return (
            GoalAmount(done: contribution, target: target.isFinite ? target : Double.greatestFiniteMagnitude),
            contribution, status
        )
    }

    /// Daily score for the card. A period that has ended is measured through its last day, missed or not.
    /// A period still running is measured as the goal list measures it on `today`, so days that have not
    /// come yet are never counted as misses. Without `today` the period is taken as ended.
    func score(in range: ClosedRange<CalendarDate>, today: CalendarDate?) -> Int? {
        if let today, today <= range.upperBound {
            return GoalProgress.compute(definition: definition, logs: logs, today: today).score
        }
        return GoalProgress.score(definition: definition, logs: logs, through: range.upperBound)
    }
}
