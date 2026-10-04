import Foundation
import VaultFormat

/// Byte ranges for lossless settings edits; JSONDecoder remains the semantic decoder.
public struct JSONSource: Sendable {
    public let range: Range<Int>
    public let members: [String: JSONSource]
    public let elements: [JSONSource]

    public static func parse(_ data: Data) throws -> Self {
        _ = try JSONSerialization.jsonObject(with: data)
        var parser = Parser(bytes: Array(data))
        let value = try parser.value(depth: 0)
        parser.whitespace()
        guard parser.offset == parser.bytes.count else { throw EntityTypeError.invalidFile }
        return value
    }

    private struct Parser {
        let bytes: [UInt8]
        var offset = 0
        mutating func whitespace() {
            while offset < bytes.count && [9, 10, 13, 32].contains(bytes[offset]) { offset += 1 }
        }
        mutating func string() throws -> String {
            let start = offset
            guard offset < bytes.count, bytes[offset] == 34 else { throw EntityTypeError.invalidFile }
            offset += 1
            while offset < bytes.count {
                let byte = bytes[offset]
                offset += 1
                if byte == 92 {
                    offset += 1
                } else if byte == 34 {
                    return try JSONDecoder().decode(String.self, from: Data(bytes[start..<offset]))
                }
            }
            throw EntityTypeError.invalidFile
        }
        mutating func value(depth: Int) throws -> JSONSource {
            guard depth < 128 else { throw EntityTypeError.invalidFile }
            whitespace()
            let start = offset
            guard offset < bytes.count else { throw EntityTypeError.invalidFile }
            var members: [String: JSONSource] = [:]
            var elements: [JSONSource] = []
            switch bytes[offset] {
            case 123, 91:
                let object = bytes[offset] == 123
                let close: UInt8 = object ? 125 : 93
                offset += 1
                whitespace()
                while offset < bytes.count && bytes[offset] != close {
                    if object {
                        let key = try string()
                        whitespace()
                        guard offset < bytes.count, bytes[offset] == 58, members[key] == nil else {
                            throw EntityTypeError.invalidFile
                        }
                        offset += 1
                        members[key] = try value(depth: depth + 1)
                    } else {
                        elements.append(try value(depth: depth + 1))
                    }
                    whitespace()
                    if offset < bytes.count, bytes[offset] == 44 {
                        offset += 1
                        whitespace()
                    } else {
                        break
                    }
                }
                guard offset < bytes.count, bytes[offset] == close else { throw EntityTypeError.invalidFile }
                offset += 1
            case 34: _ = try string()
            default:
                while offset < bytes.count && ![9, 10, 13, 32, 44, 93, 125].contains(bytes[offset]) { offset += 1 }
            }
            return JSONSource(range: start..<offset, members: members, elements: elements)
        }
    }
}
