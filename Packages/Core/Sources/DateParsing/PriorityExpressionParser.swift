import VaultFormat

public struct PriorityParse: Sendable, Equatable {
    public let priority: TaskPriority
    public let remainder: String
}

public enum PriorityExpressionParser {
    /// Only standalone leading/trailing ! or !! outside Markdown code/links.
    public static func parse(_ text: String) -> PriorityParse? {
        let bytes = Array(text.utf8)
        guard !bytes.contains(10), !bytes.contains(13) else { return nil }
        var scanner = RecognitionScanner(document: RawDocument(bytes: bytes))
        let mask = scanner.excludedBytes(bytes)
        let blanks: (UInt8) -> Bool = { $0 == 32 || $0 == 9 }
        let lower = bytes.prefix(while: blanks).count
        let upper = bytes.count - bytes.reversed().prefix(while: blanks).count
        guard lower < upper else { return nil }
        var ranges: [Range<Int>] = []
        var end = lower
        while end < upper, bytes[end] == 33 { end += 1 }
        if (1...2).contains(end - lower), end == upper || blanks(bytes[end]), !mask[lower..<end].contains(true) {
            ranges.append(lower..<end)
        }
        var start = upper
        while start > lower, bytes[start - 1] == 33 { start -= 1 }
        if (1...2).contains(upper - start), start == lower || blanks(bytes[start - 1]),
            !mask[start..<upper].contains(true), !ranges.contains(start..<upper)
        {
            ranges.append(start..<upper)
        }
        guard !ranges.isEmpty else { return nil }
        let high = ranges.contains { $0.count == 2 }
        var result = text
        for range in ranges.sorted(by: { $0.lowerBound > $1.lowerBound }) {
            result = DateExpressionParser.remainder(Array(result.utf8), removing: range)
        }
        return PriorityParse(priority: high ? .high : .medium, remainder: result)
    }
}
