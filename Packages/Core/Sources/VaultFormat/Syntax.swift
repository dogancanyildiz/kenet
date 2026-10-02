/// The ASCII bytes that carry meaning in the supported YAML subset.
///
/// Frontmatter is scanned as UTF-8 bytes. Every indicator is ASCII and no multi-byte sequence
/// contains an ASCII byte, so byte comparisons are exact and Unicode normalization never makes
/// two different spellings look alike.
enum Syntax {
    static let tab: UInt8 = 0x09
    static let space: UInt8 = 0x20
    static let doubleQuote = UInt8(ascii: "\"")
    static let hash = UInt8(ascii: "#")
    static let singleQuote = UInt8(ascii: "'")
    static let comma = UInt8(ascii: ",")
    static let dash = UInt8(ascii: "-")
    static let colon = UInt8(ascii: ":")
    static let questionMark = UInt8(ascii: "?")
    static let openBracket = UInt8(ascii: "[")
    static let backslash = UInt8(ascii: "\\")
    static let closeBracket = UInt8(ascii: "]")
    static let openBrace = UInt8(ascii: "{")
    static let closeBrace = UInt8(ascii: "}")

    /// The line that opens and closes a frontmatter block.
    static let delimiter: [UInt8] = Array("---".utf8)

    /// The key that merges another mapping into the one it stands in. It is never read or written.
    static let mergeKey: [UInt8] = Array("<<".utf8)

    /// Bytes that can never start a plain (unquoted) scalar.
    static let indicators: Set<UInt8> = Set("[]{},#&*!|>'\"%@`".utf8)

    /// Bytes that structure an inline list and so cannot appear in a plain item of one.
    static let flowIndicators: Set<UInt8> = Set("[]{},".utf8)

    static func isBlank(_ byte: UInt8) -> Bool {
        byte == space || byte == tab
    }

    /// Whether a line holds a character that a YAML stream must not contain unescaped, or that
    /// readers treat differently: C0 controls other than tab, DEL, C1 controls (U+0085 among
    /// them), U+2028, U+2029, U+FEFF, U+FFFE and U+FFFF. The line must be valid UTF-8.
    static func containsUnreadableCharacter(_ line: [UInt8]) -> Bool {
        for (index, byte) in line.enumerated() {
            switch byte {
            case 0x00...0x08, 0x0A...0x1F, 0x7F:
                return true
            case 0xC2:
                if index + 1 < line.count, (0x80...0x9F).contains(line[index + 1]) { return true }
            case 0xE2:
                let isSeparator = index + 2 < line.count && line[index + 1] == 0x80
                if isSeparator, line[index + 2] == 0xA8 || line[index + 2] == 0xA9 { return true }
            case 0xEF:
                guard index + 2 < line.count else { break }
                let isNoncharacter = line[index + 1] == 0xBF && (line[index + 2] == 0xBE || line[index + 2] == 0xBF)
                let isByteOrderMark = line[index + 1] == 0xBB && line[index + 2] == 0xBF
                if isNoncharacter || isByteOrderMark { return true }
            default:
                break
            }
        }
        return false
    }

    static func isAnchorCharacter(_ byte: UInt8) -> Bool {
        let isLetter = (byte | 0x20) >= UInt8(ascii: "a") && (byte | 0x20) <= UInt8(ascii: "z")
        return isLetter || isDigit(byte) || byte == dash || byte == UInt8(ascii: "_")
    }

    static func isDigit(_ byte: UInt8) -> Bool {
        byte >= UInt8(ascii: "0") && byte <= UInt8(ascii: "9")
    }

    /// Text for bytes cut out of a line that is known to be valid UTF-8 at ASCII boundaries.
    static func string(_ bytes: some Sequence<UInt8>) -> String {
        String(decoding: Array(bytes), as: UTF8.self)
    }

    /// Whether two strings have the same bytes. `==` would also accept canonically equivalent text.
    static func exactlyEqual(_ first: String, _ second: String) -> Bool {
        first.utf8.elementsEqual(second.utf8)
    }
}
