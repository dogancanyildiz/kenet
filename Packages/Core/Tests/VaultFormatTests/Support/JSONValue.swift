import Foundation

/// A JSON document as plain values, used to compare fixture files without tying them to Swift types.
///
/// Comparison is strict: objects must have exactly the same keys, and strings must have the
/// same bytes (Swift's `==` would also accept canonically equivalent text).
indirect enum JSONValue: Decodable, Equatable, CustomStringConvertible, Sendable {
    case null
    case bool(Bool)
    case integer(Int)
    case number(Double)
    case string(String)
    case array([JSONValue])
    case object([Member])

    struct Member: Equatable, Sendable {
        var key: String
        var value: JSONValue

        static func == (lhs: Member, rhs: Member) -> Bool {
            Array(lhs.key.utf8) == Array(rhs.key.utf8) && lhs.value == rhs.value
        }
    }

    /// An object with its members in the given order. The order matters for printing only.
    static func object(_ members: KeyValuePairs<String, JSONValue>) -> JSONValue {
        .object(members.map { Member(key: $0.key, value: $0.value) })
    }

    init(parsing bytes: [UInt8]) throws {
        self = try JSONDecoder().decode(JSONValue.self, from: Data(bytes))
    }

    private struct Key: CodingKey {
        var stringValue: String
        var intValue: Int? { nil }

        init?(stringValue: String) { self.stringValue = stringValue }
        init?(intValue: Int) { nil }
    }

    init(from decoder: Decoder) throws {
        if let container = try? decoder.container(keyedBy: Key.self) {
            self = .object(
                try container.allKeys.map {
                    Member(key: $0.stringValue, value: try container.decode(JSONValue.self, forKey: $0))
                }
            )
        } else if var container = try? decoder.unkeyedContainer() {
            var elements: [JSONValue] = []
            while !container.isAtEnd {
                elements.append(try container.decode(JSONValue.self))
            }
            self = .array(elements)
        } else {
            let container = try decoder.singleValueContainer()
            if container.decodeNil() {
                self = .null
            } else if let value = try? container.decode(Bool.self) {
                self = .bool(value)
            } else if let value = try? container.decode(Int.self) {
                self = .integer(value)
            } else if let value = try? container.decode(Double.self) {
                self = .number(value)
            } else {
                self = .string(try container.decode(String.self))
            }
        }
    }

    static func == (lhs: JSONValue, rhs: JSONValue) -> Bool {
        switch (lhs, rhs) {
        case (.null, .null): true
        case (.bool(let first), .bool(let second)): first == second
        case (.integer(let first), .integer(let second)): first == second
        case (.number(let first), .number(let second)): first == second
        case (.string(let first), .string(let second)): Array(first.utf8) == Array(second.utf8)
        case (.array(let first), .array(let second)): first == second
        case (.object(let first), .object(let second)):
            first.count == second.count && first.allSatisfy { second.contains($0) }
        default: false
        }
    }

    subscript(key: String) -> JSONValue? {
        guard case .object(let members) = self else { return nil }
        return members.first { Array($0.key.utf8) == Array(key.utf8) }?.value
    }

    var keys: [String] {
        guard case .object(let members) = self else { return [] }
        return members.map(\.key)
    }

    var stringValue: String? {
        if case .string(let value) = self { return value }
        return nil
    }

    var arrayValue: [JSONValue]? {
        if case .array(let value) = self { return value }
        return nil
    }

    /// The value as JSON text, with small objects and arrays on one line.
    var description: String { rendered(indent: 0) }

    private var isPrimitive: Bool {
        switch self {
        case .array, .object: false
        default: true
        }
    }

    private func rendered(indent: Int) -> String {
        let inner = String(repeating: "  ", count: indent + 1)
        let outer = String(repeating: "  ", count: indent)
        switch self {
        case .null: return "null"
        case .bool(let value): return value ? "true" : "false"
        case .integer(let value): return String(value)
        case .number(let value): return String(value)
        case .string(let value): return Self.quoted(value)
        case .array(let elements):
            if elements.isEmpty { return "[]" }
            if elements.allSatisfy(\.isPrimitive) {
                return "[" + elements.map { $0.rendered(indent: 0) }.joined(separator: ", ") + "]"
            }
            return "[\n" + elements.map { inner + $0.rendered(indent: indent + 1) }.joined(separator: ",\n") + "\n"
                + outer + "]"
        case .object(let members):
            if members.isEmpty { return "{}" }
            if members.allSatisfy(\.value.isPrimitive) {
                let parts = members.map { Self.quoted($0.key) + ": " + $0.value.rendered(indent: 0) }
                return "{ " + parts.joined(separator: ", ") + " }"
            }
            let parts = members.map { inner + Self.quoted($0.key) + ": " + $0.value.rendered(indent: indent + 1) }
            return "{\n" + parts.joined(separator: ",\n") + "\n" + outer + "}"
        }
    }

    private static func quoted(_ text: String) -> String {
        var output = "\""
        for scalar in text.unicodeScalars {
            switch scalar {
            case "\"": output += "\\\""
            case "\\": output += "\\\\"
            case "\n": output += "\\n"
            case "\r": output += "\\r"
            case "\t": output += "\\t"
            default:
                if scalar.value < 0x20 || (0x7F...0x9F).contains(scalar.value) || scalar.value == 0x2028
                    || scalar.value == 0x2029 || scalar.value == 0xFEFF
                {
                    let digits = String(scalar.value, radix: 16, uppercase: true)
                    output += "\\u" + String(repeating: "0", count: 4 - digits.count) + digits
                } else {
                    output.unicodeScalars.append(scalar)
                }
            }
        }
        return output + "\""
    }
}
