import GoalTracking
import VaultFormat

public struct SummaryEntityCount: Sendable, Equatable {
    public let id: String
    public let name: String
    public let count: Int
    public let change: Int
}
public struct SummaryGoal: Sendable {
    public let definition: GoalDefinition
    /// Done over the measured days against the whole period's target: a running week of a "3 a week" goal
    /// reads 2/3 on Wednesday, even when a day file of Friday already holds a third.
    public let progress: GoalAmount
    /// What the measured days added.
    public let contribution: Double
    public let streak: Int
    public let change: Double
    public let streakChange: Int
    /// Daily success percent of the 30 days ending at the period end, or at `today` while the period runs.
    /// Nil for week, year, and milestone, and when no day is measured.
    public let score: Int?
    public let completionDate: CalendarDate?
    /// A daily goal's marks for the measured days of a week or a month, as the Goals heatmap draws them.
    /// Empty for other goals and for a year.
    public let dayMarks: [CalendarDate: GoalDayMark]
}

public struct PeriodSummary: Sendable {
    public let period: SummaryPeriod
    public let range: ClosedRange<CalendarDate>
    public let previousRange: ClosedRange<CalendarDate>?
    /// The days the counts cover: the whole period, or its start to `today` while it runs.
    public let measuredRange: ClosedRange<CalendarDate>
    /// The days `previous` covers: the whole previous period, or its start to the same date while this one runs.
    public let previousMeasuredRange: ClosedRange<CalendarDate>?
    public let counts: SummaryCounts
    public let previous: SummaryCounts
    public var change: SummaryCounts { counts.difference(from: previous) }
    public let people: [SummaryEntityCount]
    public let places: [SummaryEntityCount]
    public let goals: [SummaryGoal]
    /// Rhythm units of this period; their events add up to `counts.events`.
    public let units: [SummaryUnit]
    /// Rhythm units of the whole previous period, in the same order.
    public let previousUnits: [SummaryUnit]
    /// Every first mention of the measured range, by day and then name; not only the top five.
    public let firstPeople: [SummaryFirstMention]
    public let firstPlaces: [SummaryFirstMention]
    /// The period holds `today` and has days still to come; counts compare up to the same date.
    public var isRunning: Bool { measuredRange.upperBound < range.upperBound }
    public var isEmpty: Bool {
        counts.events == 0 && counts.writtenDays == 0 && counts.peopleMentions == 0 && counts.placeMentions == 0
            && counts.createdTasks == 0 && counts.completedTasks == 0 && goals.allSatisfy { $0.contribution == 0 }
    }
    /// `today` bounds a period that has started and not ended: counts run to `today` and the previous
    /// period is counted to the same date. It also bounds goal progress, streak and score. Without `today`,
    /// or for a period that has not started, the whole period is counted.
    public static func compute(
        period: SummaryPeriod, containing day: CalendarDate, data: SummaryInput, today: CalendarDate? = nil
    ) -> Self {
        let range = period.bounds(containing: day)
        let previousRange = period.previous(containing: day)
        var measured = range
        var previousMeasured = previousRange
        if let today, range.lowerBound <= today, today < range.upperBound {
            measured = range.lowerBound...today
            previousMeasured = previousRange.map { prior in
                let same = period.sameDate(before: today).map { min($0, prior.upperBound) } ?? prior.upperBound
                return prior.lowerBound...max(prior.lowerBound, same)
            }
        }
        let counts = count(data, in: measured)
        let previous = previousMeasured.map { count(data, in: $0) } ?? SummaryCounts()
        let mentions = mentionCounts(data, in: measured)
        let oldMentions = previousMeasured.map { mentionCounts(data, in: $0) } ?? [:]
        return Self(
            period: period, range: range, previousRange: previousRange, measuredRange: measured,
            previousMeasuredRange: previousMeasured, counts: counts, previous: previous,
            people: leaders(data, kind: .person, counts: mentions, previous: oldMentions),
            places: leaders(data, kind: .place, counts: mentions, previous: oldMentions),
            goals: data.goals.map { goal in
                let history = SummaryGoalHistory(goal)
                // Like the counts, progress ends at today while the period runs; the target stays the whole period's.
                let current = history.progress(in: range, measured: measured)
                let old = previousRange.map { history.progress(in: $0) }
                let standing = goal.standing(in: range, ended: current.status, today: today)
                // The period before has ended whenever this one has started; before that it follows today too.
                let oldStreak = previousRange.flatMap { prior in
                    old.map { goal.standing(in: prior, ended: $0.status, today: today).streak }
                }
                // The change compares the measured days with the same days before.
                let oldContribution =
                    previousMeasured == previousRange
                    ? old?.contribution : previousMeasured.map { history.contribution(in: $0) }
                return SummaryGoal(
                    definition: goal.definition, progress: current.amount, contribution: current.contribution,
                    streak: standing.streak, change: current.contribution - (oldContribution ?? 0),
                    streakChange: standing.streak - (oldStreak ?? 0),
                    score: standing.score, completionDate: current.status.completionDate,
                    // A year has no day row on the screen, so its marks are not computed.
                    dayMarks: goal.definition.period == .day && period != .year
                        ? GoalProgress.heatmap(
                            definition: goal.definition, logs: goal.logs, from: measured.lowerBound,
                            to: measured.upperBound, today: today) : [:])
            }.sorted {
                $0.definition.name == $1.definition.name
                    ? $0.definition.id < $1.definition.id : $0.definition.name < $1.definition.name
            },
            units: units(data, period: period, containing: range.lowerBound, measured: measured),
            previousUnits: previousRange.map {
                units(data, period: period, containing: $0.lowerBound, measured: $0)
            } ?? [],
            firstPeople: firstMentions(data, kind: .person, in: measured),
            firstPlaces: firstMentions(data, kind: .place, in: measured))
    }
    private static func mentionCounts(_ data: SummaryInput, in range: ClosedRange<CalendarDate>) -> [String: Int] {
        var counts: [String: Int] = [:]
        for mention in data.mentions where range.contains(mention.day) { counts[mention.entity, default: 0] += 1 }
        return counts
    }
    private static func leaders(
        _ data: SummaryInput, kind: SummaryInput.Entity.Kind, counts: [String: Int], previous: [String: Int]
    ) -> [SummaryEntityCount] {
        Array(
            data.entities.filter { $0.kind == kind && (counts[$0.id] ?? 0) > 0 }.map {
                SummaryEntityCount(
                    id: $0.id, name: $0.name, count: counts[$0.id]!, change: counts[$0.id]! - (previous[$0.id] ?? 0))
            }.sorted {
                if $0.count != $1.count { return $0.count > $1.count }
                return $0.name == $1.name ? $0.id < $1.id : $0.name < $1.name
            }.prefix(5))
    }
    private static func firstMentions(
        _ data: SummaryInput, kind: SummaryInput.Entity.Kind, in range: ClosedRange<CalendarDate>
    ) -> [SummaryFirstMention] {
        data.entities.compactMap { entity -> SummaryFirstMention? in
            guard entity.kind == kind, let day = entity.firstMention, range.contains(day) else { return nil }
            return SummaryFirstMention(id: entity.id, name: entity.name, day: day)
        }.sorted {
            if $0.day != $1.day { return $0.day < $1.day }
            return $0.name == $1.name ? $0.id < $1.id : $0.name < $1.name
        }
    }
    private static func units(
        _ data: SummaryInput, period: SummaryPeriod, containing day: CalendarDate,
        measured: ClosedRange<CalendarDate>
    ) -> [SummaryUnit] {
        var events: [CalendarDate: Int] = [:]
        var written: Set<CalendarDate> = []
        for row in data.days where measured.contains(row.date) {
            events[row.date, default: 0] += max(0, row.events)
            if row.events > 0 || row.hasJournal { written.insert(row.date) }
        }
        return period.units(containing: day).map { unit in
            var total = 0
            var writtenDays = 0
            var measuredDays = 0
            var cursor: CalendarDate? = unit.lowerBound
            while let date = cursor, date <= unit.upperBound {
                if measured.contains(date) {
                    measuredDays += 1
                    total += events[date] ?? 0
                    if written.contains(date) { writtenDays += 1 }
                }
                cursor = date.addingDays(1)
            }
            return SummaryUnit(range: unit, events: total, writtenDays: writtenDays, measuredDays: measuredDays)
        }
    }
    private static func count(_ data: SummaryInput, in range: ClosedRange<CalendarDate>) -> SummaryCounts {
        var result = SummaryCounts()
        let days = data.days.filter { range.contains($0.date) }
        result.events = days.reduce(0) { $0 + max(0, $1.events) }
        result.writtenDays = Set(days.filter { $0.events > 0 || $0.hasJournal }.map(\.date)).count
        let people = Set(data.entities.filter { $0.kind == .person }.map(\.id))
        let places = Set(data.entities.filter { $0.kind == .place }.map(\.id))
        for mention in data.mentions where range.contains(mention.day) {
            if people.contains(mention.entity) { result.peopleMentions += 1 }
            if places.contains(mention.entity) { result.placeMentions += 1 }
        }
        for entity in data.entities where entity.firstMention.map(range.contains) == true {
            if entity.kind == .person { result.firstPeople += 1 } else { result.firstPlaces += 1 }
        }
        for task in data.tasks {
            if task.created.map(range.contains) == true { result.createdTasks += 1 }
            if task.status == .done && task.done.map(range.contains) == true { result.completedTasks += 1 }
            guard let created = task.created, created <= range.upperBound, task.status != .cancelled else { continue }
            let open = task.status != .done || task.done.map { $0 > range.upperBound } == true
            guard open else { continue }
            if let due = task.due {
                if due < range.upperBound { result.overdueTasks += 1 }
            } else {
                result.undatedTasks += 1
            }
        }
        return result
    }
}
