import Foundation
import GRDB
import VaultFormat

/// A task block with its own links in source order: what a task row draws (text and link spans,
/// fields) and what the task writers find it again by (file, lines, identifier, source text).
public struct TaskEntry: Sendable, Equatable {
    public let block: IndexedBlock
    /// Links of `block` only, resolved or not, by ordinal.
    public let links: [IndexedLink]

    public init(block: IndexedBlock, links: [IndexedLink]) {
        self.block = block
        self.links = links
    }
}

/// The filters the task screens share. Empty fields do not filter.
public struct TaskScope: Sendable, Hashable {
    /// Only tasks with a body link resolved to this vault-relative file.
    public var linkedTo: String?
    /// Only tasks of this project, compared by ``VaultIndex/projectKey(_:)`` whatever the spelling.
    public var project: String?

    public init(linkedTo: String? = nil, project: String? = nil) {
        self.linkedTo = linkedTo
        self.project = project
    }

    public static let all = TaskScope()
}

/// One project spelling's tasks: open (neither done nor cancelled) and done; cancelled ones
/// are left out.
public struct ProjectTaskCount: Sendable, Equatable {
    public var open: Int
    public var done: Int

    public init(open: Int, done: Int) {
        self.open = open
        self.done = done
    }
}

/// A period's task progress, whatever the screens' filters: tasks done in it (by done day) and
/// open tasks due in it.
public struct PeriodTaskCount: Sendable, Equatable {
    public var done: Int
    public var openDue: Int

    public init(done: Int, openDue: Int) {
        self.done = done
        self.openDue = openDue
    }
}

/// Open tasks (neither done nor cancelled) split by due day around `today`.
public struct TaskGroupEntries: Sendable, Equatable {
    /// Due before today.
    public let overdue: [TaskEntry]
    /// Due today.
    public let today: [TaskEntry]
    /// Due after today.
    public let upcoming: [TaskEntry]
    /// Without a due day.
    public let undated: [TaskEntry]

    public init(overdue: [TaskEntry], today: [TaskEntry], upcoming: [TaskEntry], undated: [TaskEntry]) {
        self.overdue = overdue
        self.today = today
        self.upcoming = upcoming
        self.undated = undated
    }
}

extension VaultIndex {
    /// Open tasks in `scope`, each group by due day, priority, file and line.
    public func taskGroups(today: CalendarDate, scope: TaskScope = .all) throws -> TaskGroupEntries {
        let entries = try taskEntries("status NOT IN ('done','cancelled')", scope: scope, order: Self.taskOrder)
        let day = today.description
        var overdue: [TaskEntry] = []
        var dueToday: [TaskEntry] = []
        var upcoming: [TaskEntry] = []
        var undated: [TaskEntry] = []
        // Stored days are written as `YYYY-MM-DD`, so text order is date order.
        for entry in entries {
            guard let due = entry.block.dueDate else {
                undated.append(entry)
                continue
            }
            if due < day {
                overdue.append(entry)
            } else if due == day {
                dueToday.append(entry)
            } else {
                upcoming.append(entry)
            }
        }
        return TaskGroupEntries(overdue: overdue, today: dueToday, upcoming: upcoming, undated: undated)
    }

    /// Done tasks in `scope`, newest completion day first (no day last), then priority, file and
    /// line; at most `limit`.
    public func completedTasks(limit: Int, scope: TaskScope) throws -> [TaskEntry] {
        guard limit > 0 else { return [] }
        return try taskEntries(
            "status='done'", scope: scope, order: "doneDate IS NULL,doneDate DESC,\(Self.priorityRank),file,ordinal",
            limit: limit)
    }

    /// Every task a day page may list for `day`: open tasks due before it, tasks due on it, tasks
    /// written in its file (open ones whatever their due day, closed ones when undated), and tasks
    /// done on it. By file and line.
    public func dayTasks(on day: CalendarDate) throws -> [TaskEntry] {
        try taskEntries(
            """
            (dueDate<? AND status NOT IN ('done','cancelled')) OR dueDate=?
                OR (file IN (?,?) AND (dueDate IS NULL OR status NOT IN ('done','cancelled')))
                OR (status='done' AND doneDate=?)
            """,
            arguments: [
                day.description, day.description, VaultLayout.dayPath(day), VaultLayout.legacyDayPath(day),
                day.description,
            ],
            scope: .all, order: "file,ordinal")
    }

    /// The board's tasks in `scope`: every open task, tasks done from `from` through `to`, and
    /// cancelled tasks when asked. By due day (none last), priority, file and line.
    public func boardTasks(
        doneFrom from: CalendarDate, to: CalendarDate, includeCancelled: Bool, scope: TaskScope = .all
    ) throws -> [TaskEntry] {
        try taskEntries(
            """
            status NOT IN ('done','cancelled') OR (status='done' AND doneDate>=? AND doneDate<=?)
                \(includeCancelled ? "OR status='cancelled'" : "")
            """,
            arguments: [from.description, to.description], scope: scope, order: Self.taskOrder)
    }

    /// The timeline's tasks in `scope`, cancelled ones left out: tasks with neither a start nor a
    /// due day, and tasks whose span meets `from` through `to`. A span runs from the earlier to the
    /// later of its first day (start, else due) and its last day (due, else the later of the first
    /// day and `today`). By due day (none last), priority, file and line.
    public func timelineTasks(
        from: CalendarDate, to: CalendarDate, today: CalendarDate, scope: TaskScope = .all
    ) throws -> [TaskEntry] {
        let first = "COALESCE(startDate,dueDate)"
        let last = "COALESCE(dueDate,MAX(\(first),?))"
        return try taskEntries(
            """
            status<>'cancelled' AND ((startDate IS NULL AND dueDate IS NULL)
                OR (MIN(\(first),\(last))<=? AND MAX(\(first),\(last))>=?))
            """,
            arguments: [today.description, to.description, today.description, from.description],
            scope: scope, order: Self.taskOrder)
    }

    /// Every task of the project `name` (compared by ``projectKey(_:)``), by file and line.
    public func tasks(inProject name: String) throws -> [TaskEntry] {
        try taskEntries("1", scope: TaskScope(project: name), order: "file,ordinal")
    }

    /// Open tasks due by `last`, and open undated tasks written in a day file from `first` through
    /// `last`. By due day (none last), priority, file and line.
    public func openTasks(dueBy last: CalendarDate, orWrittenFrom first: CalendarDate) throws -> [TaskEntry] {
        var files: [String] = []
        var cursor: CalendarDate? = first
        while let day = cursor, day <= last {
            // A day file not yet migrated is still the day's file (`LegacyVaultNames`).
            files += [VaultLayout.dayPath(day), VaultLayout.legacyDayPath(day)]
            cursor = day.addingDays(1)
        }
        let written = files.isEmpty ? "0" : "file IN (\(files.map { _ in "?" }.joined(separator: ",")))"
        return try taskEntries(
            "status NOT IN ('done','cancelled') AND (dueDate<=? OR (dueDate IS NULL AND \(written)))",
            arguments: [last.description] + files, scope: .all, order: Self.taskOrder)
    }

    /// The task a screen names by its row identifier: the file, then `^` and the block identifier
    /// the task owns, or `#` and its first line.
    public func task(id: String) throws -> TaskEntry? {
        try taskEntries(
            """
            file || CASE WHEN ownsIdentifier=1 AND identifier IS NOT NULL THEN '^' || identifier
                ELSE '#' || firstLine END = ?
            """, arguments: [id], scope: .all, order: "file,ordinal", limit: 1
        ).first
    }

    /// Open tasks per project spelling; tasks without a project are not counted.
    public func openTaskCounts() throws -> [String: Int] {
        try database.read { db in
            let rows = try Row.fetchAll(
                db,
                sql: """
                    SELECT project, COUNT(*) AS count FROM blocks
                    WHERE kind='task' AND project IS NOT NULL AND status NOT IN ('done','cancelled')
                    GROUP BY project
                    """)
            return Dictionary(rows.map { ($0["project"] as String, $0["count"] as Int) }, uniquingKeysWith: +)
        }
    }

    /// Open and done tasks per project spelling, in one read; tasks without a project are not
    /// counted.
    public func projectTaskCounts() throws -> [String: ProjectTaskCount] {
        try database.read { db in
            let rows = try Row.fetchAll(
                db,
                sql: """
                    SELECT project,
                        SUM(CASE WHEN status NOT IN ('done','cancelled') THEN 1 ELSE 0 END) AS open,
                        SUM(CASE WHEN status='done' THEN 1 ELSE 0 END) AS done
                    FROM blocks
                    WHERE kind='task' AND project IS NOT NULL
                    GROUP BY project
                    """)
            var counts: [String: ProjectTaskCount] = [:]
            for row in rows {
                let project: String = row["project"]
                let open: Int = row["open"]
                let done: Int = row["done"]
                // Swift keys compare canonically: spellings SQLite keeps apart may meet here.
                counts[project, default: ProjectTaskCount(open: 0, done: 0)].open += open
                counts[project, default: ProjectTaskCount(open: 0, done: 0)].done += done
            }
            return counts.filter { $0.value.open + $0.value.done > 0 }
        }
    }

    /// Tasks done from `from` through `to` (by done day) and open tasks due in it; no scope.
    public func periodTaskCount(from: CalendarDate, through to: CalendarDate) throws -> PeriodTaskCount {
        try database.read { db in
            let row = try Row.fetchOne(
                db,
                sql: """
                    SELECT
                        SUM(CASE WHEN status='done' AND doneDate>=? AND doneDate<=? THEN 1 ELSE 0 END) AS done,
                        SUM(CASE WHEN status NOT IN ('done','cancelled') AND dueDate>=? AND dueDate<=?
                            THEN 1 ELSE 0 END) AS openDue
                    FROM blocks WHERE kind='task'
                    """,
                arguments: [from.description, to.description, from.description, to.description])
            let done: Int? = row?["done"]
            let openDue: Int? = row?["openDue"]
            return PeriodTaskCount(done: done ?? 0, openDue: openDue ?? 0)
        }
    }

    private static let priorityRank = "CASE priority WHEN '⏫' THEN 0 WHEN '🔼' THEN 1 WHEN '🔽' THEN 3 ELSE 2 END"
    private static let taskOrder = "dueDate IS NULL,dueDate,\(priorityRank),file,ordinal"

    /// Task blocks matching `predicate` within `scope`, with their links, in one read.
    private func taskEntries(
        _ predicate: String, arguments: [String] = [], scope: TaskScope, order: String, limit: Int? = nil
    ) throws -> [TaskEntry] {
        try database.read { db in
            var condition = "kind='task' AND (\(predicate))"
            var values = arguments
            if let file = scope.linkedTo {
                condition += """
                     AND EXISTS (SELECT 1 FROM links l
                        WHERE l.file=blocks.file AND l.block=blocks.ordinal AND l.resolvedFile=?)
                    """
                values.append(file)
            }
            if let project = scope.project {
                let key = Self.projectKey(project)
                let spellings = try String.fetchAll(
                    db, sql: "SELECT DISTINCT project FROM blocks WHERE kind='task' AND project IS NOT NULL"
                ).filter { Self.projectKey($0) == key }
                guard !spellings.isEmpty else { return [] }
                condition += " AND project IN (\(spellings.map { _ in "?" }.joined(separator: ",")))"
                values += spellings
            }
            let selected = """
                SELECT * FROM blocks WHERE \(condition) ORDER BY \(order)\(limit.map { " LIMIT \($0)" } ?? "")
                """
            let blocks = try IndexedBlock.fetchAll(db, sql: selected, arguments: StatementArguments(values))
            guard !blocks.isEmpty else { return [] }
            let links = try IndexedLink.fetchAll(
                db,
                sql: """
                    WITH t AS (\(selected)) SELECT l.* FROM t JOIN links l ON l.file=t.file AND l.block=t.ordinal
                    ORDER BY l.file, l.block, l.ordinal
                    """, arguments: StatementArguments(values))
            var byBlock: [String: [Int: [IndexedLink]]] = [:]
            for link in links {
                guard let block = link.block else { continue }
                byBlock[link.file, default: [:]][block, default: []].append(link)
            }
            return blocks.map { TaskEntry(block: $0, links: byBlock[$0.file]?[$0.ordinal] ?? []) }
        }
    }
}
