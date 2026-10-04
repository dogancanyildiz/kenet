/// A supported, portable subset of Obsidian Tasks recurrence rules.
public struct TaskRecurrence: Sendable, Hashable {
    public enum Unit: String, Sendable { case day, week, month, year }
    public enum Frequency: Sendable, Hashable {
        case interval(Int, Unit)
        case weekday(Int)
    }
    public let frequency: Frequency
    public let whenDone: Bool
    public static let weekdays = ["monday", "tuesday", "wednesday", "thursday", "friday", "saturday", "sunday"]

    public init?(frequency: Frequency, whenDone: Bool = false) {
        switch frequency {
        case .interval(let count, _): guard count > 0 else { return nil }
        case .weekday(let day): guard (0...6).contains(day) else { return nil }
        }
        self.frequency = frequency
        self.whenDone = whenDone
    }
    public init?(_ source: String) {
        var words = source.lowercased().split(whereSeparator: { $0 == " " || $0 == "\t" }).map(String.init)
        let done = words.suffix(2) == ["when", "done"]
        if done { words.removeLast(2) }
        guard words.first == "every" else { return nil }
        let frequency: Frequency
        if words.count == 2, let day = Self.weekdays.firstIndex(of: words[1]) {
            frequency = .weekday(day)
        } else if words.count == 4, words[1...2] == ["week", "on"], let day = Self.weekdays.firstIndex(of: words[3]) {
            frequency = .weekday(day)
        } else if words.count == 2, let unit = Unit(rawValue: words[1]) {
            frequency = .interval(1, unit)
        } else if words.count == 3, words[1].allSatisfy({ $0.isASCII && $0.isNumber }),
            let count = Int(words[1]), count > 0, words[2].hasSuffix("s"),
            let unit = Unit(rawValue: String(words[2].dropLast()))
        {
            frequency = .interval(count, unit)
        } else {
            return nil
        }
        self.init(frequency: frequency, whenDone: done)
    }
    public var rule: String {
        let text: String
        switch frequency {
        case .weekday(let day): text = "every " + Self.weekdays[day]
        case .interval(let count, let unit):
            text = count == 1 ? "every " + unit.rawValue : "every \(count) " + unit.rawValue + "s"
        }
        return text + (whenDone ? " when done" : "")
    }
    public func nextOccurrence(after reference: CalendarDate, completedOn: CalendarDate) -> CalendarDate? {
        let base = whenDone ? completedOn : reference
        switch frequency {
        case .weekday(let day): return base.addingDays((day - base.weekday + 6) % 7 + 1)
        case .interval(let count, let unit):
            switch unit {
            case .day: return base.addingDays(count)
            case .week: return count <= 521_775 ? base.addingDays(count * 7) : nil
            case .month: return base.addingMonths(count)
            case .year: return count <= 9999 ? base.addingMonths(count * 12) : nil
            }
        }
    }
}
