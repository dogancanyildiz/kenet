import Foundation
import GRDB
import VaultFormat

/// Open tasks grouped by their ISO due day, in ascending day order.
public struct TaskDay: Sendable, Equatable {
    public let date: CalendarDate
    public let tasks: [IndexedBlock]
}

extension VaultIndex {
    /// All tasks due on a day, including closed tasks.
    public func tasks(dueOn date: CalendarDate) throws -> [IndexedBlock] {
        try taskQuery("dueDate=?", arguments: [date.description])
    }

    /// Open tasks whose due day precedes the supplied local day.
    public func overdueTasks(asOf date: CalendarDate) throws -> [IndexedBlock] {
        try taskQuery("dueDate<? AND status NOT IN ('done','cancelled')", arguments: [date.description])
    }

    /// Open tasks due on or after the supplied day; start dates do not hide due work.
    public func upcomingTasks(from date: CalendarDate) throws -> [TaskDay] {
        let rows = try taskQuery("dueDate>=? AND status NOT IN ('done','cancelled')", arguments: [date.description])
        let groups = Dictionary(grouping: rows, by: { $0.dueDate! })
        return groups.keys.sorted().map { TaskDay(date: CalendarDate($0)!, tasks: groups[$0]!) }
    }

    /// All open tasks without a valid due day, regardless of file kind.
    public func undatedOpenTasks() throws -> [IndexedBlock] {
        try taskQuery("dueDate IS NULL AND status NOT IN ('done','cancelled')")
    }

    /// Undated tasks physically stored in this day file, including closed tasks.
    public func tasksCreated(on date: CalendarDate) throws -> [IndexedBlock] {
        try taskQuery("dueDate IS NULL AND file=?", arguments: ["journal/" + date.description + ".md"])
    }

    /// Completed tasks, newest completion day first; dates absent in imported tasks sort last.
    public func completedTasks(limit: Int = 100) throws -> [IndexedBlock] {
        guard limit > 0 else { return [] }
        return try taskQuery("status='done'", order: "doneDate DESC,file,ordinal", limit: limit)
    }

    /// Open tasks with at least one body link resolved to the supplied vault-relative file.
    public func openTasks(linkedTo file: String) throws -> [IndexedBlock] {
        try taskQuery(
            """
            status NOT IN ('done','cancelled') AND EXISTS (
                SELECT 1 FROM links l WHERE l.file=blocks.file AND l.block=blocks.ordinal AND l.resolvedFile=?)
            """, arguments: [file.precomposedStringWithCanonicalMapping])
    }

    /// Source project spellings across all tasks, unique and ordered by Unicode code point.
    public func projects() throws -> [String] {
        let names = try database.read {
            try String.fetchAll(
                $0,
                sql: "SELECT DISTINCT project FROM blocks WHERE kind='task' AND project IS NOT NULL ORDER BY project")
        }
        return Self.projectNames(names)
    }

    public static func projectKey(_ name: String) -> String {
        name.precomposedStringWithCanonicalMapping.lowercased()
    }

    public static func projectNames(_ names: [String]) -> [String] {
        var seen: Set<String> = []
        return names.sorted().filter { seen.insert(projectKey($0)).inserted }
    }

    private func taskQuery(
        _ predicate: String, arguments: StatementArguments = [], order: String = "dueDate,file,ordinal",
        limit: Int? = nil
    ) throws -> [IndexedBlock] {
        try database.read {
            try IndexedBlock.fetchAll(
                $0,
                sql: "SELECT * FROM blocks WHERE kind='task' AND " + predicate + " ORDER BY " + order
                    + (limit.map { " LIMIT " + String($0) } ?? ""), arguments: arguments)
        }
    }
}
