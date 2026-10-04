import GoalTracking
import VaultFormat

/// Source-derived values only; no filesystem timestamps or index-specific types.
public struct SummaryInput: Sendable {
    public struct Day: Sendable {
        public let date: CalendarDate
        public let events: Int
        public let hasJournal: Bool
        public init(date: CalendarDate, events: Int, hasJournal: Bool) {
            self.date = date
            self.events = events
            self.hasJournal = hasJournal
        }
    }
    public struct Entity: Sendable {
        public enum Kind: String, Sendable { case person, place }
        public let id: String
        public let name: String
        public let kind: Kind
        /// Earliest resolved body link in a day file, not a creation timestamp.
        public let firstMention: CalendarDate?
        public init(id: String, name: String, kind: Kind, firstMention: CalendarDate? = nil) {
            self.id = id
            self.name = name
            self.kind = kind
            self.firstMention = firstMention
        }
    }
    public struct Mention: Sendable {
        public let day: CalendarDate
        public let entity: String
        public init(day: CalendarDate, entity: String) {
            self.day = day
            self.entity = entity
        }
    }
    public struct Task: Sendable {
        public let created: CalendarDate?
        public let status: TaskStatus
        public let due: CalendarDate?
        public let done: CalendarDate?
        public init(created: CalendarDate?, status: TaskStatus, due: CalendarDate?, done: CalendarDate?) {
            self.created = created
            self.status = status
            self.due = due
            self.done = done
        }
    }
    public struct Goal: Sendable {
        public let definition: GoalDefinition
        public let logs: [GoalLog]
        public init(definition: GoalDefinition, logs: [GoalLog]) {
            self.definition = definition
            self.logs = logs
        }
    }
    public let days: [Day]
    public let entities: [Entity]
    public let mentions: [Mention]
    public let tasks: [Task]
    public let goals: [Goal]
    public init(
        days: [Day] = [], entities: [Entity] = [], mentions: [Mention] = [], tasks: [Task] = [], goals: [Goal] = []
    ) {
        self.days = days
        self.entities = entities
        self.mentions = mentions
        self.tasks = tasks
        self.goals = goals
    }
}
