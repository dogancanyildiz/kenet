/// A single value to write into the frontmatter.
public enum FrontmatterLiteral: Hashable, Sendable {
    /// Text. It is quoted when it would mean something else to YAML unquoted.
    case text(String)
    /// `true` or `false`.
    case boolean(Bool)
    /// A whole number.
    case integer(Int)
    /// A number in the spelling to write: an optional sign, digits, and optionally a point and
    /// more digits (`11.25`, `-3`, `20.0290`). The spelling is written as given, so it never
    /// depends on how a platform prints floating point numbers.
    case number(String)
    /// A day, written as `YYYY-MM-DD`.
    case date(CalendarDate)
}

extension FrontmatterLiteral {
    /// How the value is written. Inside an inline list, text that contains list syntax is quoted too.
    func spelling(inFlow: Bool) throws(EditError) -> String {
        switch self {
        case .text(let text):
            return PlainScalar.isSafe(text, inFlow: inFlow) ? text : QuotedScalar.encode(text)
        case .boolean(let value):
            return value ? "true" : "false"
        case .integer(let value):
            return String(value)
        case .number(let spelling):
            guard PlainScalar.isNumber(Array(spelling.utf8)) else { throw .invalidValue }
            return spelling
        case .date(let date):
            return date.description
        }
    }

    /// Whether a value in the file already means this value, however it is spelled.
    ///
    /// Text is compared byte for byte and only with text. Numbers are compared by their digits,
    /// ignoring a plus sign and trailing zeros of the fraction, so `20.029` matches `20.0290`.
    func matches(_ scalar: FrontmatterScalar) -> Bool {
        switch self {
        case .text(let text):
            return scalar.kind == .text && Syntax.exactlyEqual(scalar.text, text)
        case .boolean(let value):
            return scalar.kind == .boolean(value)
        case .integer(let value):
            return scalar.kind == .number
                && PlainScalar.numbersAreEqual(Array(scalar.raw.utf8), Array(String(value).utf8))
        case .number(let spelling):
            let bytes = Array(spelling.utf8)
            guard scalar.kind == .number, PlainScalar.isNumber(bytes) else { return false }
            return PlainScalar.numbersAreEqual(Array(scalar.raw.utf8), bytes)
        case .date(let date):
            return scalar.kind == .date(date)
        }
    }

    /// The spelling to write for the value: the spelling of an existing value that means the
    /// same when there is one, so that unchanged values are not produced again.
    func spelling(reusing existing: [FrontmatterScalar], inFlow: Bool) throws(EditError) -> String {
        if let match = existing.first(where: matches), !inFlow || FrontmatterWriter.isValidInFlow(match.raw) {
            return match.raw
        }
        return try spelling(inFlow: inFlow)
    }
}
