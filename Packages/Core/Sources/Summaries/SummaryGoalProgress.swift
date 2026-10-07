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
}
