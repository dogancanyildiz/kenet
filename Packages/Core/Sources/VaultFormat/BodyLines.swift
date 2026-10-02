/// The syntax category of a source block.
public enum BodyLineKind: Hashable, Sendable {
    /// An event in Events.
    case event
    /// A checkbox item.
    case task
}

/// The source extent and first-line content of an event or task.
public struct LineBlock: Hashable, Sendable {
    /// The first line's zero-based index.
    public var line: Int { lineRange.lowerBound }
    /// Occupied lines, zero-based and half-open, including indented continuations.
    public let lineRange: Range<Int>
    /// The trailing Obsidian identifier without its caret, if present.
    public let id: String?
    /// First-line text without syntax separators or a trailing identifier.
    public let text: String
    /// The exact first-line bytes, excluding its terminator.
    public let firstLineContent: [UInt8]
    /// The source block's syntax category.
    public let kind: BodyLineKind

    init(lineRange: Range<Int>, id: String?, text: String, firstLineContent: [UInt8] = [], kind: BodyLineKind = .event)
    {
        self.lineRange = lineRange
        self.id = id
        self.text = text
        self.firstLineContent = firstLineContent
        self.kind = kind
    }
}

/// The meaning of a task's checkbox character.
public enum TaskStatus: String, Hashable, Sendable {
    /// A space checkbox.
    case todo
    /// A slash checkbox.
    case inProgress
    /// An x or X checkbox.
    case done
    /// A dash checkbox.
    case cancelled
    /// Any other checkbox character, preserved in the task.
    case unknown

    /// Whether the task is completed or cancelled.
    public var isClosed: Bool { self == .done || self == .cancelled }
    /// Whether the task still counts as open.
    public var isOpen: Bool { !isClosed }
}

/// A checkbox list item anywhere in the document body.
public struct TaskLine: Hashable, Sendable {
    /// Its source extent, identifier and text.
    public let block: LineBlock
    /// The exact single Unicode scalar between the brackets.
    public let rawStatus: String
    /// The checkbox's interpreted meaning.
    public let status: TaskStatus
}

/// A valid local clock time with its original spelling.
public struct EventTime: Hashable, Sendable {
    /// The hour from 0 through 23.
    public let hour: Int
    /// The minute from 0 through 59.
    public let minute: Int
    /// The original H:MM or HH:MM token.
    public let raw: String
}

/// An unindented non-task list item in the first Events section.
public struct EventLine: Hashable, Sendable {
    /// Its source extent, identifier and text.
    public let block: LineBlock
    /// The optional leading clock time.
    public let time: EventTime?
}

/// Read-only task and event lists in source order.
public struct BodyLines: Hashable, Sendable {
    /// All body checkbox items, including nested tasks.
    public let tasks: [TaskLine]
    /// Non-task list items in the recognized Events section.
    public let events: [EventLine]
}

extension RawDocument {
    /// Reads tasks and events while sharing the section scanner's code fence state.
    public var bodyLines: BodyLines {
        BodyLineParser.parse(self)
    }
}
