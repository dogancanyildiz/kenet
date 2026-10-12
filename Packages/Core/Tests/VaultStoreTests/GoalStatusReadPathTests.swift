import Foundation
import GRDB
import GoalTracking
import Testing
import VaultFormat

@testable import VaultIndex

/// The goal-status query reads only the columns a log is made of. Its logs and its rows stay equal
/// to the whole-record read (`IndexedGoalLog` through `GoalLog(indexed:)`) and to the read model's
/// construction, on a long many-goal history and on values the log reader rejects.
struct GoalStatusReadPathTests {
    @Test func manyGoalHistoryMatchesTheRecordRead() throws {
        let vault = try GoalHistoryVault(years: 2, goals: 20)
        defer { vault.remove() }
        let today = GoalHistoryVault.end
        for day in [today, try #require(today.addingDays(-200)), try #require(today.addingDays(-800))] {
            let comment = Comment(rawValue: day.description)
            #expect(
                try vault.index.goalStatuses(today: day) == (try readModelGoalStatuses(vault.index, today: day)),
                comment)
            let logs = try vault.index.database.read { try VaultIndex.goalLogs($0, through: day, key: nil) }
            #expect(logs == (try recordRead(vault.index, through: day, key: nil)), comment)
        }
        let rows = try vault.index.goalStatuses(today: today)
        #expect(rows.count == 20)
        #expect(Set(rows.map(\.definition.kind)) == [.boolean, .number, .milestone])
        let logCount = try vault.index.database.read { try Int.fetchOne($0, sql: "SELECT COUNT(*) FROM goal_logs") }
        #expect((logCount ?? 0) > 10_000)
        for key in ["g00", "g07", "g19", "yok"] {
            #expect(
                try vault.index.database.read { try VaultIndex.goalLogs($0, through: today, key: key) }
                    == (try recordRead(vault.index, through: today, key: key)), Comment(rawValue: key))
        }
    }

    /// Values `GoalLog(indexed:)` rejects (a raw spelling, a negative or non-finite amount, a
    /// boolean spelled otherwise, an impossible date) are skipped the same way; a later file on the
    /// same day still wins; a day after `today` is not read.
    @Test func rejectedValuesAndFileOrderMatchTheRecordRead() throws {
        let vault = try GoalHistoryVault(years: 0, goals: 0)
        defer { vault.remove() }
        try vault.write(
            "goals/Su.md", "---\ntype: goal\nname: Su\nkey: su\nperiod: day\nkind: number\ntarget: 8\n---\n")
        try vault.write(
            "goals/Koşu.md", "---\ntype: goal\nname: Koşu\nkey: kosu\nperiod: day\nkind: boolean\ntarget: 1\n---\n")
        try vault.index.rebuild(vaultRoot: vault.root)
        let today = try #require(CalendarDate("2026-10-12"))
        let rows: [(String, String, String, String, String)] = [
            ("journal/2026-10-01.md", "su", "2026-10-01", "number", "8"),
            ("journal/2026-10-01.md", "kosu", "2026-10-01", "boolean", "true"),
            ("journal/2026-10-02.md", "su", "2026-10-02", "number", "-2"),
            ("journal/2026-10-02.md", "kosu", "2026-10-02", "raw", "evet"),
            ("journal/2026-10-03.md", "su", "2026-10-03", "number", "nan"),
            ("journal/2026-10-03.md", "kosu", "2026-10-03", "boolean", "TRUE"),
            ("journal/2026-10-04.md", "su", "2026-10-04", "number", "1e400"),
            ("journal/2026-10-04.md", "kosu", "2026-10-04", "boolean", "true"),
            ("journal/2026-10-04b.md", "kosu", "2026-10-04", "boolean", "false"),
            ("journal/2026-10-05.md", "su", "2026-10-05", "raw", "8"),
            ("journal/2026-10-06.md", "su", "2026-02-30", "number", "8"),
            ("journal/2026-10-07.md", "su", "2026-10-07", "number", "9.5"),
            ("journal/2026-10-07.md", "kosu", "2026-10-07", "boolean", "true"),
            ("journal/2026-10-13.md", "su", "2026-10-13", "number", "8"),
        ]
        // Inserted last file first: the table's own row order is not file order.
        try vault.index.database.write { db in
            for (file, key, date, kind, value) in rows.reversed() {
                try db.execute(
                    sql: "INSERT OR IGNORE INTO files VALUES (?,?,?,?,?,?,?)",
                    arguments: [file, "journal", date, 0.0, 0, "00", true])
                try db.execute(
                    sql: "INSERT INTO goal_logs VALUES (?,?,?,?,?)", arguments: [file, key, date, kind, value])
            }
        }
        let logs = try vault.index.database.read { try VaultIndex.goalLogs($0, through: today, key: nil) }
        #expect(logs == (try recordRead(vault.index, through: today, key: nil)))
        // Hand-counted: 8, 9.5 for su; true, true, false (the later file), true for kosu.
        #expect(logs["su"]?.map(\.value) == [.number(8), .number(9.5)])
        #expect(logs["kosu"]?.map(\.value) == [.boolean(true), .boolean(true), .boolean(false), .boolean(true)])
        #expect(logs["kosu"]?.map(\.day.description) == ["2026-10-01", "2026-10-04", "2026-10-04", "2026-10-07"])
        #expect(try vault.index.goalStatuses(today: today) == (try readModelGoalStatuses(vault.index, today: today)))
    }

    /// Opt-in timing (`MEASURE_GOAL_QUERY=1`): ten years of twenty goals. The whole-record read is the
    /// read the query made before; the printed medians are the measurement.
    @Test(.enabled(if: ProcessInfo.processInfo.environment["MEASURE_GOAL_QUERY"] == "1"))
    func tenYearTwentyGoalTiming() throws {
        let vault = try GoalHistoryVault(years: 10, goals: 20)
        defer { vault.remove() }
        let today = GoalHistoryVault.end
        let logCount =
            try vault.index.database.read { try Int.fetchOne($0, sql: "SELECT COUNT(*) FROM goal_logs") } ?? 0
        func median(_ run: () throws -> Void) rethrows -> Double {
            var samples: [Double] = []
            for _ in 0..<7 {
                let start = DispatchTime.now().uptimeNanoseconds
                try run()
                samples.append(Double(DispatchTime.now().uptimeNanoseconds - start) / 1_000_000)
            }
            return samples.sorted()[samples.count / 2]
        }
        let recordMs = try median { _ = try recordRead(vault.index, through: today, key: nil) }
        let columnMs = try median {
            _ = try vault.index.database.read { try VaultIndex.goalLogs($0, through: today, key: nil) }
        }
        let rows = try vault.index.goalStatuses(today: today)
        let logs = try vault.index.database.read { try VaultIndex.goalLogs($0, through: today, key: nil) }
        let computeMs = median {
            for row in rows {
                let entries = logs[row.definition.key] ?? []
                _ = GoalProgress.compute(definition: row.definition, logs: entries, today: today)
                _ = GoalProgress.score(definition: row.definition, logs: entries, through: today)
            }
        }
        let queryMs = try median { _ = try vault.index.goalStatuses(today: today) }
        print(
            String(
                format:
                    "MEASURE_GOAL_QUERY goals=%d logs=%d record_read_ms=%.1f column_read_ms=%.1f compute_ms=%.1f query_ms=%.1f",
                rows.count, logCount, recordMs, columnMs, computeMs, queryMs))
        #expect(logs == (try recordRead(vault.index, through: today, key: nil)))
    }
}

/// The read the status query made before: whole `IndexedGoalLog` records, grouped, then converted.
private func recordRead(_ index: VaultIndex, through today: CalendarDate, key: String?) throws -> [String: [GoalLog]] {
    let logs = try index.database.read { db in
        try IndexedGoalLog.fetchAll(
            db,
            sql: "SELECT * FROM goal_logs WHERE date<=? AND (? IS NULL OR key=?) ORDER BY file, key",
            arguments: [today.description, key, key])
    }
    return Dictionary(grouping: logs, by: \.key).mapValues { $0.compactMap(GoalLog.init(indexed:)) }
}

/// A fictional goals-only vault: `goals` definitions of every kind and period, and `years` of day
/// files ending on `end`, each goal logged on most days. Deterministic.
private struct GoalHistoryVault {
    static let end = CalendarDate("2026-10-12")!
    let root: URL
    let index: VaultIndex

    init(years: Int, goals: Int) throws {
        root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        // Kind, period and target by position: daily boolean and number, weekly, yearly, milestone.
        let shapes: [(period: String, kind: String, target: String?)] = [
            ("day", "boolean", "1"), ("day", "number", "8"), ("week", "boolean", "3"), ("day", "boolean", "1"),
            ("year", "number", "300"), ("day", "number", "20"), ("year", "milestone", nil), ("week", "number", "50"),
        ]
        var definitions: [(key: String, kind: String, target: Double)] = []
        for number in 0..<goals {
            let shape = shapes[number % shapes.count]
            let key = String(format: "g%02d", number)
            var text =
                "---\ntype: goal\nname: Hedef \(key)\nkey: \(key)\nperiod: \(shape.period)\nkind: \(shape.kind)\n"
            if let target = shape.target { text += "target: \(target)\n" }
            try Self.write(root, "goals/Hedef \(key).md", text + "---\n")
            definitions.append((key, shape.kind, Double(shape.target ?? "1") ?? 1))
        }
        var state: UInt64 = 0x5EED_2026
        func next() -> UInt64 {
            state = state &* 6_364_136_223_846_793_005 &+ 1_442_695_040_888_963_407
            return state >> 33
        }
        let days = years * 365 + years / 4
        if days > 0, let start = Self.end.addingDays(-(days - 1)) {
            for offset in 0..<days {
                guard let day = start.addingDays(offset) else { continue }
                var lines: [String] = []
                for goal in definitions {
                    switch goal.kind {
                    case "milestone":
                        if day.month == 6 && day.day == 1 { lines.append("  \(goal.key): true") }
                    case "boolean":
                        if next() % 100 < 70 { lines.append("  \(goal.key): \(next() % 10 != 0)") }
                    default:
                        if next() % 100 < 85 {
                            lines.append("  \(goal.key): \(next() % UInt64(goal.target * 1.5 + 1))")
                        }
                    }
                }
                guard !lines.isEmpty else { continue }
                try Self.write(
                    root, "journal/\(day).md",
                    "---\ntype: journal\ndate: \(day)\ngoals:\n" + lines.joined(separator: "\n") + "\n---\n")
            }
        }
        index = try VaultIndex()
        try index.rebuild(vaultRoot: root)
    }

    func write(_ path: String, _ text: String) throws { try Self.write(root, path, text) }

    func remove() { try? FileManager.default.removeItem(at: root) }

    private static func write(_ root: URL, _ path: String, _ text: String) throws {
        let url = root.appendingPathComponent(path)
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data(text.utf8).write(to: url)
    }
}
