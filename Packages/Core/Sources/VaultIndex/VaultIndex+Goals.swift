import GRDB
import GoalTracking
import VaultFormat

extension VaultIndex {
    /// Valid definitions only; invalid source fields remain intact in the index and Markdown.
    public func goalDefinitions() throws -> [GoalDefinition] {
        try database.read { db in
            let entities = try IndexedEntity.fetchAll(db, sql: "SELECT * FROM entities WHERE kind='goal' ORDER BY file")
            let links = try IndexedLink.fetchAll(db, sql: "SELECT * FROM links WHERE key='place' ORDER BY file,ordinal")
            let places = Dictionary(grouping: links, by: \.file)
            return entities.compactMap { GoalDefinition(entity: $0, place: places[$0.file]?.first?.target) }
        }
    }
}

extension GoalDefinition {
    public init?(entity: IndexedEntity, place: String? = nil) {
        guard entity.kind == "goal", let key = entity.goalKey,
            let period = entity.period.flatMap(GoalPeriod.init(rawValue:)),
            let kind = entity.goalKind.flatMap(GoalKind.init(rawValue:))
        else { return nil }
        guard kind != .milestone || entity.target == nil else { return nil }
        guard let target = kind == .milestone ? 1 : entity.target.flatMap(Double.init) else { return nil }
        self.init(
            id: entity.file, key: key, name: entity.name, period: period, kind: kind,
            target: target, unit: entity.unit, place: place)
    }
}

extension GoalLog {
    public init?(indexed: IndexedGoalLog) {
        guard let day = CalendarDate(indexed.date) else { return nil }
        let value: GoalValue
        switch indexed.kind {
        case "boolean" where indexed.value == "true" || indexed.value == "false":
            value = .boolean(indexed.value == "true")
        case "number":
            guard let amount = Double(indexed.value), amount.isFinite, amount >= 0 else { return nil }
            value = .number(amount)
        default: return nil
        }
        self.init(day: day, value: value)
    }
}
