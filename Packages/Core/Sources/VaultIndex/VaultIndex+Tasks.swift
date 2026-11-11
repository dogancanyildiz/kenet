import Foundation
import GRDB
import VaultFormat

extension VaultIndex {
    /// All tasks due on a day, including closed tasks.
    public func tasks(dueOn date: CalendarDate) throws -> [IndexedBlock] {
        try taskQuery("dueDate=?", arguments: [date.description])
    }

    /// Open tasks whose due day precedes the supplied local day.
    public func overdueTasks(asOf date: CalendarDate) throws -> [IndexedBlock] {
        try taskQuery("dueDate<? AND status NOT IN ('done','cancelled')", arguments: [date.description])
    }

    /// Completed tasks, newest completion day first; dates absent in imported tasks sort last.
    public func completedTasks(limit: Int = 100) throws -> [IndexedBlock] {
        guard limit > 0 else { return [] }
        return try taskQuery("status='done'", order: "doneDate DESC,file,ordinal", limit: limit)
    }

    public static func projectKey(_ name: String) -> String {
        name.precomposedStringWithCanonicalMapping.lowercased()
    }

    public static func projectNames(_ names: [String]) -> [String] {
        var seen: Set<String> = []
        return names.sorted().filter { seen.insert(projectKey($0)).inserted }
    }

    private func taskQuery(
        _ predicate: String, arguments: StatementArguments = [],
        order: String = "dueDate,CASE priority WHEN '⏫' THEN 0 WHEN '🔼' THEN 1 WHEN '🔽' THEN 3 ELSE 2 END,file,ordinal",
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
