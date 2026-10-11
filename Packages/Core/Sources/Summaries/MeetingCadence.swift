import VaultFormat

/// One indexed scalar that might describe a person's meeting cadence.
public struct PersonCadenceField: Sendable, Equatable {
    public let key: String
    public let kind: String
    public let value: String

    public init(key: String, kind: String, value: String) {
        self.key = key
        self.kind = kind
        self.value = value
    }
}

/// Optional meeting rhythm stored on a person file. Absent and invalid values are "no cadence".
public struct PersonCadence: Sendable, Equatable {
    public static let dayKey = "cadence_days"
    public static let snoozeKey = "cadence_snoozed_until"
    public static let pauseKey = "cadence_paused"
    public static let keys = [dayKey, snoozeKey, pauseKey]

    /// Positive whole number of days, or nil when the field is missing or not a positive integer.
    public var days: Int?
    /// Inclusive snooze day. A nil date means the field is missing or not a calendar day.
    public var snoozedUntil: CalendarDate?
    /// True only for a boolean true spelling. Anything else, including false, is not paused.
    public var isPaused: Bool

    public static let none = PersonCadence(days: nil, snoozedUntil: nil, isPaused: false)

    public init(days: Int?, snoozedUntil: CalendarDate?, isPaused: Bool) {
        self.days = days
        self.snoozedUntil = snoozedUntil
        self.isPaused = isPaused
    }

    /// Reads the three cadence keys. Other keys, and values of the wrong kind, are ignored.
    public static func parse(_ fields: [PersonCadenceField]) -> PersonCadence {
        var days: Int?
        var snoozed: CalendarDate?
        var paused = false
        for field in fields {
            switch field.key {
            case dayKey where field.kind == "number":
                days = positiveDays(spelling: field.value)
            case snoozeKey where field.kind == "date":
                snoozed = CalendarDate(field.value)
            case pauseKey where field.kind == "boolean":
                paused = isTrue(field.value)
            default:
                break
            }
        }
        return PersonCadence(days: days, snoozedUntil: snoozed, isPaused: paused)
    }

    /// `30` and `+30` are 30. Zero, a leading zero, a fraction, a sign-only minus and text are nil.
    public static func positiveDays(spelling: String) -> Int? {
        let bytes = Array(spelling.utf8)
        guard !bytes.isEmpty else { return nil }
        var index = 0
        if bytes[0] == UInt8(ascii: "+") {
            index = 1
            guard index < bytes.count else { return nil }
        }
        if bytes[index] == UInt8(ascii: "0"), bytes.count - index > 1 { return nil }
        var value = 0
        var sawDigit = false
        while index < bytes.count {
            let byte = bytes[index]
            guard byte >= UInt8(ascii: "0"), byte <= UInt8(ascii: "9") else { return nil }
            let digit = Int(byte - UInt8(ascii: "0"))
            guard value <= (Int.max - digit) / 10 else { return nil }
            value = value * 10 + digit
            sawDigit = true
            index += 1
        }
        guard sawDigit, value >= 1 else { return nil }
        return value
    }

    private static func isTrue(_ spelling: String) -> Bool {
        let bytes = Array(spelling.utf8)
        return bytes == Array("true".utf8) || bytes == Array("True".utf8) || bytes == Array("TRUE".utf8)
    }
}

/// A person plus the last recorded encounter, already limited to today or earlier.
public struct CadencePerson: Sendable, Equatable {
    public var id: String
    public var name: String
    public var lastDay: CalendarDate?
    public var cadence: PersonCadence

    public init(id: String, name: String, lastDay: CalendarDate?, cadence: PersonCadence) {
        self.id = id
        self.name = name
        self.lastDay = lastDay
        self.cadence = cadence
    }
}

/// Who is due for a conversation, and who has never been mentioned.
public struct CadenceList: Sendable, Equatable {
    public struct Row: Sendable, Equatable {
        public var id: String
        public var elapsedDays: Int?
        /// Days past the person's cadence, or past the fallback threshold. Nil for the never-met group.
        public var overdueDays: Int?

        public init(id: String, elapsedDays: Int?, overdueDays: Int?) {
            self.id = id
            self.elapsedDays = elapsedDays
            self.overdueDays = overdueDays
        }
    }

    public var overdue: [Row]
    public var never: [Row]

    public init(overdue: [Row], never: [Row]) {
        self.overdue = overdue
        self.never = never
    }
}

/// Pure overdue list. No clock and no index types.
///
/// Paused people are omitted. A snooze date hides the person through that day, inclusive;
/// the next day they return, and the stored date is left for the caller to keep. A person
/// with `days` is measured against that rhythm; everyone else uses `fallbackThreshold`.
/// Overdue rows are the furthest past their limit first, then by id. Never-met rows are by name, then id.
public enum MeetingCadence {
    public static func list(people: [CadencePerson], today: CalendarDate, fallbackThreshold: Int) -> CadenceList {
        var overdue: [CadenceList.Row] = []
        var never: [(name: String, row: CadenceList.Row)] = []
        for person in people {
            if person.cadence.isPaused { continue }
            if let until = person.cadence.snoozedUntil, today <= until { continue }
            if let last = person.lastDay {
                let elapsed = today.ordinal - last.ordinal
                let limit = person.cadence.days ?? fallbackThreshold
                guard elapsed >= limit else { continue }
                overdue.append(
                    CadenceList.Row(id: person.id, elapsedDays: elapsed, overdueDays: elapsed - limit))
            } else {
                never.append(
                    (person.name, CadenceList.Row(id: person.id, elapsedDays: nil, overdueDays: nil)))
            }
        }
        overdue.sort { lhs, rhs in
            if lhs.overdueDays != rhs.overdueDays { return (lhs.overdueDays ?? 0) > (rhs.overdueDays ?? 0) }
            return lhs.id < rhs.id
        }
        never.sort { lhs, rhs in
            if lhs.name != rhs.name { return lhs.name < rhs.name }
            return lhs.row.id < rhs.row.id
        }
        return CadenceList(overdue: overdue, never: never.map(\.row))
    }
}
