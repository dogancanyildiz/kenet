import VaultFormat

/// A frontmatter edit as the `write` fixtures describe it in `operation.json`.
///
/// The form is documented in `docs/fixtures.md`.
enum FrontmatterOperation: Sendable, CustomStringConvertible {
    case setValue(key: String, value: FrontmatterLiteral)
    case setList(key: String, items: [FrontmatterLiteral])
    case setEntry(key: String, entry: String, value: FrontmatterLiteral)
    case removeEntry(key: String, entry: String)
    case removeField(key: String)

    struct Malformed: Error, CustomStringConvertible {
        var description: String
    }

    init(json: JSONValue) throws {
        func string(_ name: String) throws -> String {
            guard let value = json[name]?.stringValue else {
                throw Malformed(description: "missing string \"\(name)\"")
            }
            return value
        }
        func literal(_ name: String) throws -> FrontmatterLiteral {
            guard let value = json[name] else { throw Malformed(description: "missing \"\(name)\"") }
            return try Self.literal(value)
        }
        func expectKeys(_ expected: Set<String>) throws {
            guard Set(json.keys) == expected else {
                throw Malformed(description: "expected the keys \(expected.sorted()), found \(json.keys.sorted())")
            }
        }

        switch try string("operation") {
        case "set-value":
            try expectKeys(["operation", "key", "value"])
            self = .setValue(key: try string("key"), value: try literal("value"))
        case "set-list":
            try expectKeys(["operation", "key", "items"])
            guard let items = json["items"]?.arrayValue else { throw Malformed(description: "missing array \"items\"") }
            self = .setList(key: try string("key"), items: try items.map(Self.literal))
        case "set-entry":
            try expectKeys(["operation", "key", "entry", "value"])
            self = .setEntry(key: try string("key"), entry: try string("entry"), value: try literal("value"))
        case "remove-entry":
            try expectKeys(["operation", "key", "entry"])
            self = .removeEntry(key: try string("key"), entry: try string("entry"))
        case "remove-field":
            try expectKeys(["operation", "key"])
            self = .removeField(key: try string("key"))
        case let other:
            throw Malformed(description: "unknown operation \"\(other)\"")
        }
    }

    /// A value to write: an object with exactly one member that names its type.
    private static func literal(_ json: JSONValue) throws -> FrontmatterLiteral {
        guard case .object(let members) = json, members.count == 1, let member = members.first else {
            throw Malformed(description: "a value is an object with one member, found \(json)")
        }
        switch (member.key, member.value) {
        case ("text", .string(let text)): return .text(text)
        case ("boolean", .bool(let value)): return .boolean(value)
        case ("integer", .integer(let value)): return .integer(value)
        case ("number", .string(let spelling)): return .number(spelling)
        case ("date", .string(let text)):
            guard let date = CalendarDate(text) else { throw Malformed(description: "\"\(text)\" is not a date") }
            return .date(date)
        default: throw Malformed(description: "unknown value \(json)")
        }
    }

    /// The top-level key the operation targets.
    var key: String {
        switch self {
        case .setValue(let key, _), .setList(let key, _), .setEntry(let key, _, _), .removeEntry(let key, _),
            .removeField(let key):
            key
        }
    }

    func apply(to document: RawDocument) throws(EditError) -> RawDocument {
        switch self {
        case .setValue(let key, let value):
            try document.settingFrontmatterValue(value, forKey: key)
        case .setList(let key, let items):
            try document.settingFrontmatterList(items, forKey: key)
        case .setEntry(let key, let entry, let value):
            try document.settingFrontmatterEntry(value, forKey: entry, inMapping: key)
        case .removeEntry(let key, let entry):
            try document.removingFrontmatterEntry(forKey: entry, inMapping: key)
        case .removeField(let key):
            try document.removingFrontmatterField(forKey: key)
        }
    }

    var description: String {
        switch self {
        case .setValue(let key, let value): "set-value \(key.debugDescription) \(value)"
        case .setList(let key, let items): "set-list \(key.debugDescription) \(items)"
        case .setEntry(let key, let entry, let value):
            "set-entry \(key.debugDescription) \(entry.debugDescription) \(value)"
        case .removeEntry(let key, let entry): "remove-entry \(key.debugDescription) \(entry.debugDescription)"
        case .removeField(let key): "remove-field \(key.debugDescription)"
        }
    }
}

extension EditError {
    /// The name the `write` fixtures use for the error.
    var fixtureName: String {
        switch self {
        case .readOnlyDocument: "read-only-document"
        case .invalidLineRange: "invalid-line-range"
        case .lineBreakInContent: "line-break-in-content"
        case .unreadableFrontmatter: "unreadable-frontmatter"
        case .rawField: "raw-field"
        case .notAMapping: "not-a-mapping"
        case .invalidKey: "invalid-key"
        case .invalidValue: "invalid-value"
        }
    }
}
