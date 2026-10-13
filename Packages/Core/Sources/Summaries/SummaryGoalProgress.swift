import GoalTracking
import VaultFormat

/// A goal's logs grouped by day once, so that each range reads only its own logged days.
/// A day without a log adds nothing, so skipping it leaves every sum unchanged.
struct SummaryGoalHistory {
    let goal: SummaryInput.Goal
    private let byDay: [CalendarDate: [GoalLog]]
    private let days: [CalendarDate]

    init(_ goal: SummaryInput.Goal) {
        self.goal = goal
        byDay = Dictionary(grouping: goal.logs, by: \.day)
        days = byDay.keys.sorted()
    }

    /// The target is the whole range's; what is done counts only the `measured` days, so in a running
    /// period a log on a day file after today adds nothing yet.
    func progress(in range: ClosedRange<CalendarDate>, measured: ClosedRange<CalendarDate>? = nil) -> (
        amount: GoalAmount, contribution: Double, status: GoalStatus
    ) {
        let definition = goal.definition
        let measured = measured ?? range
        let status = GoalProgress.compute(definition: definition, logs: goal.logs, today: measured.upperBound)
        let contribution = contribution(in: measured)
        if definition.kind == .milestone || definition.period == .year {
            return (status.progress, contribution, status)
        }
        let multiplier = definition.period == .day ? Self.dayCount(range) : Self.weekCount(range)
        let target = definition.target * Double(multiplier)
        return (
            GoalAmount(done: contribution, target: target.isFinite ? target : Double.greatestFiniteMagnitude),
            contribution, status
        )
    }

    /// What the days of the range added: the logged amounts in day order, or the milestone's completions.
    func contribution(in range: ClosedRange<CalendarDate>) -> Double {
        let definition = goal.definition
        if definition.kind == .milestone {
            var contribution = 0.0
            for year in range.lowerBound.year...range.upperBound.year {
                let end =
                    year == range.upperBound.year ? range.upperBound : CalendarDate(year: year, month: 12, day: 31)!
                let date = GoalProgress.compute(definition: definition, logs: goal.logs, today: end).completionDate
                if date.map(range.contains) == true { contribution += 1 }
            }
            return contribution
        }
        var contribution = 0.0
        var index = firstIndex(atOrAfter: range.lowerBound)
        while index < days.count, days[index] <= range.upperBound {
            let day = days[index]
            let amount = GoalProgress.compute(definition: definition, logs: byDay[day] ?? [], today: day).progress.done
            let sum = contribution + amount
            contribution = sum.isFinite ? sum : Double.greatestFiniteMagnitude
            index += 1
        }
        return contribution
    }

    private func firstIndex(atOrAfter day: CalendarDate) -> Int {
        var low = 0
        var high = days.count
        while low < high {
            let middle = (low + high) / 2
            if days[middle] < day { low = middle + 1 } else { high = middle }
        }
        return low
    }

    static func dayCount(_ range: ClosedRange<CalendarDate>) -> Int {
        range.upperBound.ordinal - range.lowerBound.ordinal + 1
    }

    /// Monday weeks the range touches, partial weeks at both ends included.
    static func weekCount(_ range: ClosedRange<CalendarDate>) -> Int {
        if let first = range.lowerBound.startOfWeek, let last = range.upperBound.startOfWeek {
            return (last.ordinal - first.ordinal) / 7 + 1
        }
        // Near the first supported day a week has no Monday; each such day stands for itself.
        var weeks: Set<CalendarDate> = []
        var cursor: CalendarDate? = range.lowerBound
        while let day = cursor, day <= range.upperBound {
            weeks.insert(day.startOfWeek ?? day)
            cursor = day.addingDays(1)
        }
        return weeks.count
    }
}

extension SummaryInput.Goal {
    /// Streak and daily score for the card. A period that has ended is measured at its last day. A period
    /// still running, or not started, is measured as the goal list measures it on `today`, so days that
    /// have not come yet never break the chain or count as misses. Without `today` the period is taken as ended.
    func standing(in range: ClosedRange<CalendarDate>, ended: GoalStatus, today: CalendarDate?) -> (
        streak: Int, score: Int?
    ) {
        if let today, today <= range.upperBound {
            let listed = GoalProgress.compute(definition: definition, logs: logs, today: today)
            return (listed.streak, listed.score)
        }
        return (ended.streak, GoalProgress.score(definition: definition, logs: logs, through: range.upperBound))
    }
}
