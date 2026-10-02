import VaultFormat

/// Language-independent link fixture snapshots with physical byte offsets.
enum LinkSnapshot {
    static func json(_ links: [WikiLink]) -> JSONValue {
        .array(
            links.map { link in
                let anchor: JSONValue
                switch link.anchor {
                case .heading(let text): anchor = .object(["kind": .string("heading"), "text": .string(text)])
                case .block(let text): anchor = .object(["kind": .string("block"), "text": .string(text)])
                case nil: anchor = .null
                }
                let source: JSONValue
                switch link.source {
                case .body: source = .object(["kind": .string("body")])
                case .frontmatter(let key, let entry):
                    source = .object([
                        "kind": .string("frontmatter"), "key": .string(key),
                        "entry": entry.map(JSONValue.string) ?? .null,
                    ])
                }
                return .object([
                    "line": .integer(link.line + 1),
                    "byteRange": .array([.integer(link.byteRange.lowerBound), .integer(link.byteRange.upperBound)]),
                    "targetRange": .array([
                        .integer(link.targetRange.lowerBound), .integer(link.targetRange.upperBound),
                    ]),
                    "target": .string(link.target), "rawTarget": .string(link.rawTarget), "anchor": anchor,
                    "displayText": link.displayText.map(JSONValue.string) ?? .null,
                    "isEmbedded": .bool(link.isEmbedded), "isSameFile": .bool(link.isSameFile),
                    "isPath": .bool(link.isPath), "source": source,
                ])
            })
    }
}
