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
    public let progress: GoalAmount
    public let contribution: Double
    public let streak: Int
    public let change: Double
    public let streakChange: Int
    public let completionDate: CalendarDate?
}

public struct PeriodSummary: Sendable {
    public let period: SummaryPeriod
    public let range: ClosedRange<CalendarDate>
    public let previousRange: ClosedRange<CalendarDate>?
    public let counts: SummaryCounts
    public let previous: SummaryCounts
    public var change: SummaryCounts { counts.difference(from: previous) }
    public let people: [SummaryEntityCount]
    public let places: [SummaryEntityCount]
    public let goals: [SummaryGoal]
    public var isEmpty: Bool {
        counts.events == 0 && counts.writtenDays == 0 && counts.peopleMentions == 0 && counts.placeMentions == 0
            && counts.createdTasks == 0 && counts.completedTasks == 0 && goals.allSatisfy { $0.contribution == 0 }
    }
    public static func compute(period: SummaryPeriod, containing day: CalendarDate, data: SummaryInput) -> Self {
        let range = period.bounds(containing: day)
        let previousRange = period.previous(containing: day)
        let counts = count(data, in: range)
        let previous = previousRange.map { count(data, in: $0) } ?? SummaryCounts()
        let mentions = mentionCounts(data, in: range)
        let oldMentions = previousRange.map { mentionCounts(data, in: $0) } ?? [:]
        return Self(
            period: period, range: range, previousRange: previousRange, counts: counts, previous: previous,
            people: leaders(data, kind: .person, counts: mentions, previous: oldMentions),
            places: leaders(data, kind: .place, counts: mentions, previous: oldMentions),
            goals: data.goals.map { goal in
                let current = goal.progress(in: range)
                let old = previousRange.map { goal.progress(in: $0) }
                return SummaryGoal(
                    definition: goal.definition, progress: current.amount, contribution: current.contribution,
                    streak: current.status.streak, change: current.contribution - (old?.contribution ?? 0),
                    streakChange: current.status.streak - (old?.status.streak ?? 0),
                    completionDate: current.status.completionDate)
            }.sorted {
                $0.definition.name == $1.definition.name
                    ? $0.definition.id < $1.definition.id : $0.definition.name < $1.definition.name
            })
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
