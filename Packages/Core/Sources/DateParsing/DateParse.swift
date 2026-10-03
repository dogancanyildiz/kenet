import VaultFormat

/// Ordered language preferences used to interpret words and ambiguous numeric dates.
public enum Language: String, Sendable, CaseIterable {
    case turkish = "tr"
    case english = "en"
}

/// One date expression in the original UTF-8 text.
public struct DateParse: Sendable, Equatable {
    public enum Confidence: String, Sendable { case exact, assumed }
    public let byteRange: Range<Int>
    public let date: CalendarDate
    public let remainder: String
    public let confidence: Confidence
}

struct DateMatch: Sendable {
    let end: Int
    let date: CalendarDate
    let confidence: DateParse.Confidence
}
