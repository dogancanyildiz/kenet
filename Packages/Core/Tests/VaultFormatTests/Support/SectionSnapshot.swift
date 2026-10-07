import VaultFormat

/// Language-neutral, one-based section ranges for fixture comparisons.
enum SectionSnapshot {
    static func range(_ range: Range<Int>) -> JSONValue {
        range.isEmpty
            ? .null : .object(["firstLine": .integer(range.lowerBound + 1), "lastLine": .integer(range.upperBound)])
    }

    static func json(_ body: DaySections) -> JSONValue {
        .object([
            "preamble": range(body.preambleRange),
            "items": .array(
                body.sections.map {
                    .object([
                        "kind": $0.kind.map { .string($0.rawValue) } ?? .null,
                        "headingLine": .integer($0.headingLine + 1), "level": .integer($0.level),
                        "firstLine": .integer($0.lineRange.lowerBound + 1),
                        "lastLine": .integer($0.lineRange.upperBound),
                    ])
                }),
        ])
    }
}
