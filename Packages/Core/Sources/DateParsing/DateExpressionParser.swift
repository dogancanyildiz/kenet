import VaultFormat

/// Finds one natural-language day using caller-supplied local context.
public enum DateExpressionParser {
    public static func parse(
        _ text: String, today: CalendarDate, language: [Language], weekStartsOnMonday: Bool = true
    ) -> DateParse? {
        let source = DateTokens(text)
        for start in source.tokens.indices {
            var best: DateMatch?
            for preference in language {
                let matches =
                    source.relative(at: start, today: today, language: preference, monday: weekStartsOnMonday)
                    + source.weekday(at: start, today: today, language: preference)
                    + source.absolute(at: start, today: today, language: preference)
                for match in matches where best == nil || match.end > best!.end { best = match }
            }
            if let best {
                let range = source.tokens[start].range.lowerBound..<source.tokens[best.end - 1].range.upperBound
                return DateParse(
                    byteRange: range, date: best.date, remainder: remainder(source.bytes, removing: range),
                    confidence: best.confidence)
            }
        }
        return nil
    }

    static func remainder(_ bytes: [UInt8], removing range: Range<Int>) -> String {
        var lower = range.lowerBound
        var upper = range.upperBound
        while lower > 0 && (bytes[lower - 1] == 32 || bytes[lower - 1] == 9) { lower -= 1 }
        while upper < bytes.count && (bytes[upper] == 32 || bytes[upper] == 9) { upper += 1 }
        var result = Array(bytes[..<lower])
        if lower > 0 && upper < bytes.count && ![UInt8(10), 13].contains(bytes[lower - 1])
            && ![UInt8(10), 13].contains(bytes[upper])
            && (lower < range.lowerBound || upper > range.upperBound)
        {
            result.append(32)
        }
        result.append(contentsOf: bytes[upper...])
        return String(decoding: result, as: UTF8.self)
    }
}
