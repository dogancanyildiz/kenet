import VaultFormat

/// The frontmatter model in the language-independent form the `parse` fixtures expect.
///
/// The form is documented in `docs/fixtures.md`. Line numbers start at 1.
enum FrontmatterSnapshot {
    static func json(_ state: FrontmatterState) -> JSONValue {
        switch state {
        case .absent:
            return .object(["state": .string("absent")])
        case .unreadable:
            return .object(["state": .string("unreadable")])
        case .parsed(let frontmatter):
            return .object([
                "state": .string("parsed"),
                "firstLine": .integer(frontmatter.lineRange.lowerBound + 1),
                "lastLine": .integer(frontmatter.lineRange.upperBound),
                "fields": .array(frontmatter.fields.map { json($0, withLines: true) }),
            ])
        }
    }

    /// A field with or without its line numbers; without them two fields compare by meaning and spelling.
    static func json(_ field: FrontmatterField, withLines: Bool) -> JSONValue {
        var members: [JSONValue.Member] = [.init(key: "key", value: .string(field.key))]
        if withLines {
            members.append(.init(key: "firstLine", value: .integer(field.lineRange.lowerBound + 1)))
            members.append(.init(key: "lastLine", value: .integer(field.lineRange.upperBound)))
        }
        switch field.value {
        case .scalar(let scalar):
            members.append(.init(key: "scalar", value: json(scalar)))
        case .list(let items, let style):
            let list: JSONValue = .object([
                "style": .string(style == .inline ? "inline" : "block"),
                "items": .array(items.map(json)),
            ])
            members.append(.init(key: "list", value: list))
        case .mapping(let entries):
            let mapping = entries.map { entry -> JSONValue in
                var entryMembers: [JSONValue.Member] = [.init(key: "key", value: .string(entry.key))]
                if withLines { entryMembers.append(.init(key: "line", value: .integer(entry.line + 1))) }
                entryMembers.append(.init(key: "value", value: json(entry.value)))
                return .object(entryMembers)
            }
            members.append(.init(key: "mapping", value: .array(mapping)))
        case .raw(let text):
            members.append(.init(key: "raw", value: .string(text)))
        }
        if let items = field.value.listItems {
            members.append(.init(key: "listItems", value: .array(items.map { .string($0.text) })))
        }
        return .object(members)
    }

    static func json(_ scalar: FrontmatterScalar) -> JSONValue {
        let type =
            switch scalar.kind {
            case .text: "text"
            case .boolean: "boolean"
            case .number: "number"
            case .date: "date"
            case .empty: "empty"
            }
        return .object(["type": .string(type), "text": .string(scalar.text), "raw": .string(scalar.raw)])
    }
}
