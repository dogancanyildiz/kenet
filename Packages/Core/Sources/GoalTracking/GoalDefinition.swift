import VaultFormat

public enum GoalPeriod: String, Sendable { case day, week, year }
public enum GoalKind: String, Sendable { case boolean, number }

public struct GoalDefinition: Sendable, Equatable {
    public let id: String
    public let key: String
    public let name: String
    public let period: GoalPeriod
    public let kind: GoalKind
    public let target: Double
    public let unit: String?
    /// The target of the optional place wikilink, without brackets.
    public let place: String?

    public init?(
        id: String, key: String, name: String, period: GoalPeriod, kind: GoalKind,
        target: Double, unit: String? = nil, place: String? = nil
    ) {
        guard key.contains(where: { !$0.isWhitespace }), target.isFinite, target > 0 else { return nil }
        self.id = id
        self.key = key
        self.name = name
        self.period = period
        self.kind = kind
        self.target = target
        self.unit = unit
        self.place = place
    }
}

public enum GoalValue: Sendable, Equatable {
    case boolean(Bool)
    case number(Double)

    public var isValid: Bool {
        switch self {
        case .boolean: true
        case .number(let value): value.isFinite && value >= 0
        }
    }
}

public struct GoalLog: Sendable, Equatable {
    public let day: CalendarDate
    public let value: GoalValue
    public init(day: CalendarDate, value: GoalValue) {
        self.day = day
        self.value = value
    }
}
