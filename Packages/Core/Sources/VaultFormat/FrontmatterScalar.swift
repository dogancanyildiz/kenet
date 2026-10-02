/// A single value as it is written in the frontmatter.
///
/// The spelling found in the file is kept next to its meaning, so a value that is not changed
/// is never produced again from its meaning: `29.0290` stays `29.0290`.
public struct FrontmatterScalar: Hashable, Sendable {
    /// What a scalar means.
    public enum Kind: Hashable, Sendable {
        /// Text: every quoted value, and every unquoted value that is none of the other kinds.
        case text
        /// `true` or `false`, in the spellings YAML 1.2 accepts (`true`, `True`, `TRUE`).
        case boolean(Bool)
        /// A decimal number such as `25`, `-3`, `+5` or `29.0290`, without an exponent.
        case number
        /// A day written as `YYYY-MM-DD`.
        case date(CalendarDate)
        /// No value: nothing after the key, `null` or `~`.
        case empty
    }

    /// The value exactly as spelled in the file, including quotes, without surrounding blanks.
    public let raw: String

    /// The value as text: unquoted and unescaped. Empty for an empty value.
    public let text: String

    /// What the value means.
    public let kind: Kind

    /// The value as an integer, when it is a number written without fraction or exponent.
    public var integerValue: Int? {
        guard kind == .number, PlainScalar.isInteger(Array(raw.utf8)) else { return nil }
        return Int(raw)
    }

    /// The value as a floating point number, when it is a number.
    public var doubleValue: Double? {
        kind == .number ? Double(raw) : nil
    }
}

extension FrontmatterScalar {
    /// The scalar an unquoted spelling stands for.
    static func plain(_ bytes: some Collection<UInt8>) -> FrontmatterScalar {
        let bytes = Array(bytes)
        let raw = Syntax.string(bytes)
        let kind = PlainScalar.kind(of: bytes)
        return FrontmatterScalar(raw: raw, text: kind == .empty ? "" : raw, kind: kind)
    }
}
