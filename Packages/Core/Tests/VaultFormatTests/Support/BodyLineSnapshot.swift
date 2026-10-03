import VaultFormat

/// Exact language-neutral snapshots for the line fixtures.
enum BodyLineSnapshot {
    static func block(_ block: LineBlock) -> [JSONValue.Member] {
        [
            .init(key: "line", value: .integer(block.line + 1)),
            .init(key: "firstLine", value: .integer(block.lineRange.lowerBound + 1)),
            .init(key: "lastLine", value: .integer(block.lineRange.upperBound)),
            .init(key: "id", value: block.id.map(JSONValue.string) ?? .null),
            .init(key: "text", value: .string(block.text)),
        ]
    }

    static func tasks(_ tasks: [TaskLine]) -> JSONValue { .array(tasks.map(task)) }

    private static func task(_ task: TaskLine) -> JSONValue {
        var members = block(task.block).filter { $0.key != "text" }
        let ranges: [JSONValue] = task.fieldRanges.map { field in
            .object([
                "kind": .string(field.kind.rawValue),
                "byteRange": .array([.integer(field.byteRange.lowerBound), .integer(field.byteRange.upperBound)]),
            ])
        }
        members.append(.init(key: "text", value: .string(task.text)))
        members.append(.init(key: "dueDate", value: task.dueDate.map { .string($0.description) } ?? .null))
        members.append(.init(key: "startDate", value: task.startDate.map { .string($0.description) } ?? .null))
        members.append(.init(key: "doneDate", value: task.doneDate.map { .string($0.description) } ?? .null))
        members.append(.init(key: "priority", value: priority(task.priority)))
        members.append(.init(key: "project", value: task.project.map(JSONValue.string) ?? .null))
        members.append(.init(key: "fieldRanges", value: .array(ranges)))
        members.append(.init(key: "rawStatus", value: .string(task.rawStatus)))
        members.append(.init(key: "status", value: .string(task.status.rawValue)))
        members.append(.init(key: "isClosed", value: .bool(task.status.isClosed)))
        members.append(.init(key: "isOpen", value: .bool(task.status.isOpen)))
        return .object(members)
    }

    private static func priority(_ priority: TaskPriority?) -> JSONValue {
        switch priority {
        case .high: .string("high")
        case .medium: .string("medium")
        case .low: .string("low")
        case .other(let token): .object(["other": .string(token)])
        case nil: .null
        }
    }

    static func events(_ events: [EventLine]) -> JSONValue {
        .array(
            events.map {
                .object(
                    block($0.block) + [
                        .init(
                            key: "time",
                            value: $0.time.map {
                                .object([
                                    "hour": .integer($0.hour), "minute": .integer($0.minute), "raw": .string($0.raw),
                                ])
                            } ?? .null)
                    ])
            })
    }
}
