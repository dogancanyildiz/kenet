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

    static func tasks(_ tasks: [TaskLine]) -> JSONValue {
        .array(
            tasks.map {
                .object(
                    block($0.block) + [
                        .init(key: "rawStatus", value: .string($0.rawStatus)),
                        .init(key: "status", value: .string($0.status.rawValue)),
                        .init(key: "isClosed", value: .bool($0.status.isClosed)),
                        .init(key: "isOpen", value: .bool($0.status.isOpen)),
                    ])
            })
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
