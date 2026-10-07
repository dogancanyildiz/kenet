/// Supported Obsidian Tasks priorities; other priorities are read-only.
public enum TaskPriority: Hashable, Sendable {
    case high, medium, low
    case other(String)

    public var sortRank: Int {
        switch self {
        case .high: 0
        case .medium: 1
        case .low: 3
        case .other: 2
        }
    }

    /// The source emoji, also used by the disposable index.
    public var token: String {
        switch self {
        case .high: "⏫"
        case .medium: "🔼"
        case .low: "🔽"
        case .other(let token): token
        }
    }
}

/// A field's token range in the first line's UTF-8 content, excluding separator and identifier.
public struct TaskFieldRange: Hashable, Sendable {
    /// The semantic category of a field.
    public enum Kind: String, Hashable, Sendable { case startDate, dueDate, doneDate, priority, recurrence, project }
    public let kind: Kind
    public let byteRange: Range<Int>
}

struct TaskFieldValues: Hashable, Sendable {
    var text: String
    var dueDate: CalendarDate?
    var startDate: CalendarDate?
    var doneDate: CalendarDate?
    var priority: TaskPriority?
    var project: String?
    var recurrence: TaskRecurrence?
    var recurrenceSource: String?
}

struct ParsedTaskFields: Hashable, Sendable {
    var values: TaskFieldValues
    let ranges: [TaskFieldRange]
}
