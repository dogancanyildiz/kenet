import VaultFormat

/// Task expressions with nonoverlapping ranges in the caller's original UTF-8 text.
public struct QuickEntryAnalysis: Sendable, Equatable {
    public struct Token: Sendable, Equatable {
        public enum Value: Sendable, Equatable {
            case recurrence(TaskRecurrence)
            case priority(TaskPriority)
            case date(CalendarDate)
        }

        public enum Kind: Sendable { case recurrence, priority, date }

        public let byteRange: Range<Int>
        public let value: Value
        public let confidence: DateParse.Confidence

        public var kind: Kind {
            switch value {
            case .recurrence: .recurrence
            case .priority: .priority
            case .date: .date
            }
        }
    }

    /// Tokens are ordered by their position in the original text.
    public let tokens: [Token]
    public let remainder: String

    /// Suppression ranges use original UTF-8 offsets; overlapping expressions stay literal.
    public static func analyze(
        _ text: String, today: CalendarDate, language: [Language],
        suppressedRanges: [Range<Int>] = [], weekStartsOnMonday: Bool = true
    ) -> Self {
        var source = MappedText(text)
        var tokens: [Token] = []
        if let recurrence = RecurrenceExpressionParser.parse(
            source.text, language: language, excluding: source.exclusions(suppressedRanges))
        {
            tokens += source.originalRanges(recurrence.byteRange).map {
                Token(byteRange: $0, value: .recurrence(recurrence.recurrence), confidence: .exact)
            }
            source.remove(recurrence.byteRange)
        }
        if let priority = PriorityExpressionParser.parse(source.text, excluding: source.exclusions(suppressedRanges)) {
            for range in priority.byteRanges {
                tokens += source.originalRanges(range).map {
                    Token(byteRange: $0, value: .priority(range.count == 2 ? .high : .medium), confidence: .exact)
                }
            }
            for range in priority.byteRanges.sorted(by: { $0.lowerBound > $1.lowerBound }) { source.remove(range) }
        }
        if let date = DateExpressionParser.parse(
            source.text, today: today, language: language, weekStartsOnMonday: weekStartsOnMonday,
            excluding: source.exclusions(suppressedRanges))
        {
            tokens += source.originalRanges(date.byteRange).map {
                Token(byteRange: $0, value: .date(date.date), confidence: date.confidence)
            }
            source.remove(date.byteRange)
        }
        return Self(tokens: tokens.sorted { $0.byteRange.lowerBound < $1.byteRange.lowerBound }, remainder: source.text)
    }
}

/// Carries original byte positions through the parsers' whitespace joining policy.
private struct MappedText {
    var bytes: [UInt8]
    var offsets: [Int]
    var text: String { String(decoding: bytes, as: UTF8.self) }

    init(_ text: String) {
        bytes = Array(text.utf8)
        offsets = Array(bytes.indices)
    }

    // An earlier removal can join two words into a later expression. Keep its
    // original fragments separate rather than enclosing an already consumed token.
    func originalRanges(_ range: Range<Int>) -> [Range<Int>] {
        var ranges: [Range<Int>] = []
        var start = offsets[range.lowerBound]
        var end = start + 1
        for index in (range.lowerBound + 1)..<range.upperBound {
            if offsets[index] != end {
                ranges.append(start..<end)
                start = offsets[index]
            }
            end = offsets[index] + 1
        }
        ranges.append(start..<end)
        return ranges.compactMap { fragment in
            let indices = range.filter { fragment.contains(offsets[$0]) && ![UInt8(32), 9].contains(bytes[$0]) }
            guard let first = indices.first, let last = indices.last else { return nil }
            return offsets[first]..<(offsets[last] + 1)
        }
    }

    func exclusions(_ ranges: [Range<Int>]) -> [Range<Int>] {
        offsets.indices.compactMap { index in
            ranges.contains { $0.contains(offsets[index]) } ? index..<(index + 1) : nil
        }
    }

    mutating func remove(_ range: Range<Int>) {
        var lower = range.lowerBound
        var upper = range.upperBound
        while lower > 0 && [UInt8(32), 9].contains(bytes[lower - 1]) { lower -= 1 }
        while upper < bytes.count && [UInt8(32), 9].contains(bytes[upper]) { upper += 1 }
        var positions = Array(offsets[..<lower])
        if lower > 0 && upper < bytes.count && ![UInt8(10), 13].contains(bytes[lower - 1])
            && ![UInt8(10), 13].contains(bytes[upper])
            && (lower < range.lowerBound || upper > range.upperBound)
        {
            positions.append(offsets[lower < range.lowerBound ? lower : range.upperBound])
        }
        positions.append(contentsOf: offsets[upper...])
        bytes = Array(DateExpressionParser.remainder(bytes, removing: range).utf8)
        offsets = positions
    }
}
