import VaultFormat

public struct RecurrenceParse: Sendable, Equatable {
    public let byteRange: Range<Int>
    public let recurrence: TaskRecurrence
    public let remainder: String
}

/// Small explicit tr/en dictionary; shares date recognition's Markdown exclusions.
public enum RecurrenceExpressionParser {
    public static func parse(_ text: String, language: [Language]) -> RecurrenceParse? {
        let source = DateTokens(text)
        let task = RawDocument(bytes: ("- [ ] " + text).utf8).bodyLines.tasks.first
        guard task?.recurrenceSource == nil else { return nil }
        for start in source.tokens.indices {
            let lower = source.tokens[start].range.lowerBound
            if lower > 0 && ![UInt8(32), 9, 10, 13, 40, 44, 59].contains(source.bytes[lower - 1]) { continue }
            for preference in language {
                let first = preference == .turkish ? "her" : "every"
                guard source.phrase([first], at: start, language: preference) != nil else { continue }
                let weekdays =
                    preference == .turkish
                    ? ["pazartesi", "salı", "çarşamba", "perşembe", "cuma", "cumartesi", "pazar"]
                    : TaskRecurrence.weekdays
                let units = preference == .turkish ? ["gün", "hafta", "ay", "yıl"] : ["day", "week", "month", "year"]
                var match: (end: Int, frequency: TaskRecurrence.Frequency)?
                for day in weekdays.indices {
                    if let end = source.phrase([first, weekdays[day]], at: start, language: preference) {
                        match = (end, .weekday(day))
                    }
                    if preference == .english,
                        let end = source.phrase([first, "week", "on", weekdays[day]], at: start, language: preference)
                    {
                        match = (end, .weekday(day))
                    }
                }
                for (index, unit) in TaskRecurrence.Unit.allUnits.enumerated() {
                    if match == nil, let end = source.phrase([first, units[index]], at: start, language: preference) {
                        // Do not reinterpret unsupported 'every week on ...' as a plain interval.
                        if end < source.tokens.count, source.tokens[end].key(preference) == "on" { continue }
                        match = (end, .interval(1, unit))
                    }
                    if start + 2 < source.tokens.count, let count = Int(source.tokens[start + 1].text), count > 0,
                        let end = source.phrase(
                            [first, source.tokens[start + 1].text, units[index] + (preference == .english ? "s" : "")],
                            at: start, language: preference)
                    {
                        if end < source.tokens.count, source.tokens[end].key(preference) == "on" { continue }
                        match = (end, .interval(count, unit))
                    }
                }
                guard let match else { continue }
                let suffix = preference == .turkish ? ["tamamlanınca"] : ["when", "done"]
                let end = source.phrase(suffix, at: match.end, language: preference) ?? match.end
                guard let recurrence = TaskRecurrence(frequency: match.frequency, whenDone: end != match.end) else {
                    continue
                }
                let range = source.tokens[start].range.lowerBound..<source.tokens[end - 1].range.upperBound
                return RecurrenceParse(
                    byteRange: range, recurrence: recurrence,
                    remainder: DateExpressionParser.remainder(source.bytes, removing: range))
            }
        }
        return nil
    }
}

extension TaskRecurrence.Unit {
    fileprivate static var allUnits: [Self] { [.day, .week, .month, .year] }
}
