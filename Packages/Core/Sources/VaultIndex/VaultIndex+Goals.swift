import GRDB
import GoalTracking
import VaultFormat

/// One valid goal definition and the file its place link resolves to.
public struct GoalDefinitionRow: Sendable, Equatable {
    public let definition: GoalDefinition
    /// The file the definition's first `place` link resolves to; nil without a place link or when
    /// the link does not resolve. The place text itself is `definition.place`.
    public let placeFile: String?

    public init(definition: GoalDefinition, placeFile: String?) {
        self.definition = definition
        self.placeFile = placeFile
    }
}

/// What the daily goal reminder reads for the days it plans: the valid daily definitions, in name
/// order, and their logs on those days by goal key, in file order.
public struct NotificationGoals: Sendable, Equatable {
    public var definitions: [GoalDefinition]
    public var logs: [String: [GoalLog]]

    public init(definitions: [GoalDefinition] = [], logs: [String: [GoalLog]] = [:]) {
        self.definitions = definitions
        self.logs = logs
    }
}

extension VaultIndex {
    /// Valid definitions in name order (`localizedStandardCompare`, then file order for equal
    /// names): the order of the goal list and of `goalStatuses(today:)`. Each row carries the file
    /// its place link resolves to.
    public func goalDefinitionsByName() throws -> [GoalDefinitionRow] {
        try database.read { db in try Self.goalDefinitionRows(db, key: nil) }
    }

    /// Every goal key a definition holds, valid or not, as `VaultStore.creatingGoal` reserves them:
    /// a key left by a deleted goal is free, and a day record's key alone reserves nothing.
    public func reservedGoalKeys() throws -> Set<String> {
        try database.read { db in
            Set(try String.fetchAll(db, sql: "SELECT DISTINCT goalKey FROM entities WHERE goalKey IS NOT NULL"))
        }
    }

    /// Logs dated `from` through `through` by goal key, in file order; of `keys` only, when given.
    /// A row `GoalLog(indexed:)` rejects is skipped; a key with no log in the days has no entry.
    public func goalLogsByKey(
        from: CalendarDate, through: CalendarDate, keys: Set<String>? = nil
    ) throws -> [String: [GoalLog]] {
        try database.read { db in try Self.goalLogs(db, from: from, through: through, keys: keys) }
    }

    /// The daily goal reminder's input for the days `first` through `last`, read in one transaction.
    /// A daily goal's progress on a day is that day's own value, so no earlier log is read.
    public func notificationGoals(from first: CalendarDate, through last: CalendarDate) throws -> NotificationGoals {
        try database.read { db in
            let daily = try Self.goalDefinitionRows(db, key: nil).map(\.definition).filter { $0.period == .day }
            let logs = try Self.goalLogs(db, from: first, through: last, keys: Set(daily.map(\.key)))
            return NotificationGoals(definitions: daily, logs: logs)
        }
    }

    /// Valid definitions (of `key` only, when given) in name order, with their place links. The
    /// first `place` link of a file counts, as `GoalDefinition(entity:place:)` takes it.
    static func goalDefinitionRows(_ db: Database, key: String?) throws -> [GoalDefinitionRow] {
        let entitySQL =
            key == nil
            ? "SELECT * FROM entities WHERE kind='goal' ORDER BY file"
            : "SELECT * FROM entities WHERE kind='goal' AND goalKey=? ORDER BY file"
        let arguments = StatementArguments(key.map { [$0] } ?? [])
        let entities = try IndexedEntity.fetchAll(db, sql: entitySQL, arguments: arguments)
        let links = try IndexedLink.fetchAll(
            db,
            sql: """
                SELECT l.* FROM links l
                JOIN entities e ON e.file=l.file AND e.kind='goal'
                WHERE l.key='place' ORDER BY l.file, l.ordinal
                """)
        let places = Dictionary(grouping: links, by: \.file).compactMapValues(\.first)
        var rows = entities.compactMap { entity -> GoalDefinitionRow? in
            let place = places[entity.file]
            guard let definition = GoalDefinition(entity: entity, place: place?.target) else { return nil }
            return GoalDefinitionRow(definition: definition, placeFile: place?.resolvedFile)
        }
        // `sort` is stable: equal names keep file order.
        rows.sort { $0.definition.name.localizedStandardCompare($1.definition.name) == .orderedAscending }
        return rows
    }

    /// Logs dated `from` through `through` (of `keys` only, when given) by goal key, in file order.
    /// Only the columns a log is made of are read, by position, as `goalLogs(_:through:key:)` reads them.
    static func goalLogs(
        _ db: Database, from: CalendarDate, through: CalendarDate, keys: Set<String>?
    ) throws -> [String: [GoalLog]] {
        if let keys, keys.isEmpty { return [:] }
        var sql = "SELECT key, date, kind, value FROM goal_logs WHERE date>=? AND date<=?"
        var arguments: [String] = [from.description, through.description]
        if let keys {
            let sorted = keys.sorted()
            sql += " AND key IN (" + Array(repeating: "?", count: sorted.count).joined(separator: ",") + ")"
            arguments += sorted
        }
        sql += " ORDER BY file, key"
        return try groupedGoalLogs(Row.fetchCursor(db, sql: sql, arguments: StatementArguments(arguments)))
    }

    static func groupedGoalLogs(_ rows: RowCursor) throws -> [String: [GoalLog]] {
        var grouped: [String: [GoalLog]] = [:]
        while let row = try rows.next() {
            let log = IndexedGoalLog(file: "", key: row[0], date: row[1], kind: row[2], value: row[3])
            guard let entry = GoalLog(indexed: log) else { continue }
            grouped[log.key, default: []].append(entry)
        }
        return grouped
    }

    /// Valid definitions only; invalid source fields remain intact in the index and Markdown.
    public func goalDefinitions() throws -> [GoalDefinition] {
        try database.read { db in
            let entities = try IndexedEntity.fetchAll(db, sql: "SELECT * FROM entities WHERE kind='goal' ORDER BY file")
            let links = try IndexedLink.fetchAll(db, sql: "SELECT * FROM links WHERE key='place' ORDER BY file,ordinal")
            let places = Dictionary(grouping: links, by: \.file)
            return entities.compactMap { GoalDefinition(entity: $0, place: places[$0.file]?.first?.target) }
        }
    }

    /// Source paths of indexed goal entities, including definitions the UI may not yet accept.
    public func goalFiles() throws -> [String] {
        try database.read { db in
            try String.fetchAll(db, sql: "SELECT file FROM entities WHERE kind='goal' ORDER BY file")
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
