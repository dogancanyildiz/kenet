import Foundation
import GRDB
import GoalTracking
import Testing
import VaultFormat
import VaultIndex

@testable import VaultIndex
@testable import VaultStore

/// The goal-status query against the read model's construction: valid definitions, name order,
/// and `GoalProgress` over the 400-day log window (399 days back through 6 days ahead).
struct GoalStatusQueryTests {
    @Test func sampleVaultMatchesReadModelConstruction() throws {
        let vault = try StoreVault(sample: true)
        defer { vault.remove() }
        let today = CalendarDate("2026-09-27")!
        try expectOneGoalLogSelect(vault.index, today: today)
        let rows = try vault.index.goalStatuses(today: today)
        let expected = try readModelGoalStatuses(vault.index, today: today)
        #expect(rows == expected)
        #expect(rows.map(\.definition.key) == ["kitap", "spor", "su"])
        let spor = try #require(rows.first { $0.definition.key == "spor" })
        #expect(spor.definition.place == "Tepe Spor Salonu")
        #expect(spor.status.periodStart == CalendarDate("2026-09-21"))
        #expect(spor.status.streak == 2 && spor.status.longestStreak == 2 && spor.status.yearDone == 6)
        #expect(spor.score == nil && spor.status.score == nil)
        for (key, streak, longest, amount) in [("kitap", 8, 8, 320.0), ("su", 10, 10, 104.0)] {
            let row = try #require(rows.first { $0.definition.key == key })
            #expect(row.status.streak == streak && row.status.longestStreak == longest)
            #expect(row.status.yearDone == amount)
        }
        let su = try #require(rows.first { $0.definition.key == "su" })
        #expect(try vault.index.goalStatus(key: "su", today: today) == su)
        #expect(try vault.index.goalStatus(key: "yok", today: today) == nil)
    }

    @Test func syntheticVaultMatchesReadModelConstruction() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let manifest = try SyntheticVault.generate(at: root, configuration: .compact)
        let index = try VaultIndex()
        try index.rebuild(vaultRoot: root)
        let today = manifest.endDate
        let rows = try index.goalStatuses(today: today)
        let expected = try readModelGoalStatuses(index, today: today)
        #expect(rows == expected)
        #expect(rows.count == 6)
        #expect(rows.map(\.definition.key) == ["kitap", "meditasyon", "spor", "su", "yazi", "yuruyus"])
    }

    /// Query time on the five-year vault, after the index is built. The ceiling is loose; the
    /// printed duration is the measurement.
    @Test func fiveYearVaultQueryMatchesReadModel() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let manifest = try SyntheticVault.generate(at: root, configuration: .fiveYears)
        let index = try VaultIndex()
        try index.rebuild(vaultRoot: root)
        let today = manifest.endDate
        let clock = ContinuousClock()
        let start = clock.now
        let rows = try index.goalStatuses(today: today)
        let elapsed = start.duration(to: clock.now)
        let milliseconds =
            Double(elapsed.components.seconds) * 1000 + Double(elapsed.components.attoseconds) / 1e15
        print(String(format: "GOAL_STATUS_QUERY rows=%d elapsed_ms=%.2f", rows.count, milliseconds))
        let expected = try readModelGoalStatuses(index, today: today)
        #expect(rows == expected)
        #expect(rows.count == 6)
        #expect(elapsed < .seconds(2), "goal status query exceeded 2s: \(elapsed)")
    }

    /// Hand-counted window edges. `su` is true on every day from 400 days before `today` through
    /// `today`. The day 400 back is outside the window. The day 10 back has a second, later file
    /// whose value is false, so that day misses and is forgiven.
    @Test func edgeCasesAreHandCounted() throws {
        let vault = try StoreVault()
        defer { vault.remove() }
        let today = CalendarDate("2026-10-12")!
        let boundary = try #require(today.addingDays(-399))
        let outside = try #require(today.addingDays(-400))
        let missed = try #require(today.addingDays(-10))
        #expect(boundary == CalendarDate("2025-09-08"))
        #expect(outside == CalendarDate("2025-09-07"))
        #expect(missed == CalendarDate("2026-10-02"))
        #expect(today.addingDays(-29) == CalendarDate("2026-09-13"))

        try vault.write("places/Koru.md", "---\ntype: place\nname: Koru\n---\n")
        try vault.write(
            "goals/Su.md",
            "---\ntype: goal\nname: Su\nkey: su\nperiod: day\nkind: boolean\ntarget: 1\nplace: \"[[Koru]]\"\n---\n")
        try vault.write(
            "goals/Ara.md",
            "---\ntype: goal\nname: Ara\nkey: ara\nperiod: day\nkind: boolean\ntarget: 1\n---\n")
        try vault.write(
            "goals/Bos.md",
            "---\ntype: goal\nname: Bos\nkey: bos\nperiod: day\nkind: boolean\ntarget: 1\n---\n")
        try vault.write(
            "goals/Site.md",
            "---\ntype: goal\nname: Site\nkey: site\nperiod: year\nkind: milestone\n---\n")
        try vault.write(
            "goals/Portfolyo.md",
            "---\ntype: goal\nname: Portfolyo\nkey: portfolyo\nperiod: year\nkind: milestone\n---\n")
        try vault.write(
            "goals/Bozuk.md",
            "---\ntype: goal\nname: Bozuk\nkey: bozuk\nperiod: month\nkind: boolean\ntarget: 1\n---\n")
        let completed = CalendarDate("2026-03-15")!
        let yesterday = try #require(today.addingDays(-1))
        let dayBefore = try #require(today.addingDays(-2))
        let siteFalse = try #require(today.addingDays(-11))
        var cursor = outside
        while cursor <= today {
            var lines = ["  su: true"]
            if cursor == yesterday || cursor == dayBefore { lines.append("  ara: true") }
            if cursor == completed { lines.append("  site: true") }
            if cursor == siteFalse { lines.append("  site: false") }
            if cursor == today { lines.append("  yok: true") }
            try vault.write(
                "journal/\(cursor).md",
                "---\ntype: journal\ndate: \(cursor)\ngoals:\n" + lines.joined(separator: "\n") + "\n---\n")
            cursor = try #require(cursor.addingDays(1))
        }
        try vault.index.rebuild(vaultRoot: vault.root)
        let duplicate = "journal/\(missed)b.md"
        try vault.index.database.write { db in
            try db.execute(
                sql: "INSERT INTO files VALUES (?,?,?,?,?,?,?)",
                arguments: [duplicate, "note", missed.description, 0.0, 0, "00", true])
            try db.execute(
                sql: "INSERT INTO goal_logs VALUES (?,?,?,?,?)",
                arguments: [duplicate, "su", missed.description, "boolean", "false"])
        }

        let rows = try vault.index.goalStatuses(today: today)
        let expected = try readModelGoalStatuses(vault.index, today: today)
        #expect(rows == expected)
        #expect(rows.map(\.definition.key) == ["ara", "bos", "portfolyo", "site", "su"])

        let indexed = try vault.index.goalLogs(key: "su")
        #expect(indexed.filter { $0.date == missed.description }.map(\.value) == ["true", "false"])
        let suLogs = indexed.compactMap(GoalLog.init(indexed:))
        let inWindow = suLogs.filter { $0.day >= boundary && $0.day <= today }
        // 400 days, one forgiven miss: 399. The outside day would make 400; dropping the boundary day
        // or today leaves 398. Reversing file order lets the earlier `true` win, so the miss disappears.
        #expect(inWindow.count == 401)
        let suDefinition = try #require(rows.first { $0.definition.key == "su" }?.definition)
        #expect(GoalProgress.compute(definition: suDefinition, logs: inWindow, today: today).streak == 399)
        let opened = inWindow + [GoalLog(day: outside, value: .boolean(true))]
        #expect(GoalProgress.compute(definition: suDefinition, logs: opened, today: today).streak == 400)
        let narrower = inWindow.filter { $0.day >= today.addingDays(-398)! }
        #expect(GoalProgress.compute(definition: suDefinition, logs: narrower, today: today).streak == 398)
        let withoutToday = inWindow.filter { $0.day < today }
        let excluded = GoalProgress.compute(definition: suDefinition, logs: withoutToday, today: today)
        #expect(excluded.streak == 398 && excluded.isPendingToday)
        let reversed = GoalProgress.compute(definition: suDefinition, logs: inWindow.reversed(), today: today)
        #expect(reversed.streak == 400 && reversed.yearDone == 285)

        let su = try #require(rows.first { $0.definition.key == "su" })
        #expect(su.definition.place == "Koru")
        #expect(su.status.streak == 399 && su.status.longestStreak == 399 && su.status.yearDone == 284)
        #expect(su.status.progress.done == 1 && su.status.isPendingToday == false)
        #expect(su.status.score == 96 && su.score == 96)
        #expect(try vault.index.goalStatus(key: "su", today: today) == su)

        // Logged yesterday and the day before, not today: the chain waits and the two scores differ.
        let ara = try #require(rows.first { $0.definition.key == "ara" })
        #expect(ara.status.streak == 2 && ara.status.longestStreak == 2 && ara.status.yearDone == 2)
        #expect(ara.status.isPendingToday && ara.status.progress.done == 0)
        #expect(ara.status.score == 100 && ara.score == 66)

        let site = try #require(rows.first { $0.definition.key == "site" })
        #expect(site.status.completionDate == completed && site.status.progress.done == 1)
        #expect(site.status.isPendingToday == false && site.status.streak == 0 && site.status.yearDone == 1)
        #expect(site.score == nil && site.status.score == nil)

        let paused = try #require(rows.first { $0.definition.key == "portfolyo" })
        #expect(paused.status.completionDate == nil && paused.status.isPendingToday)
        #expect(paused.status.progress.done == 0 && paused.score == nil && paused.status.yearDone == 0)

        let empty = try #require(rows.first { $0.definition.key == "bos" })
        #expect(empty.status.streak == 0 && empty.status.longestStreak == 0 && empty.status.yearDone == 0)
        #expect(empty.status.isPendingToday && empty.status.score == nil && empty.score == nil)
        #expect(try vault.index.goalStatus(key: "bozuk", today: today) == nil)
        #expect(try vault.index.goalStatus(key: "yok", today: today) == nil)
    }

    /// A replaced value and a new definition stay equal to a rebuild and to the read-model construction.
    @Test func storeEditsMatchAFreshIndex() async throws {
        let vault = try StoreVault()
        defer { vault.remove() }
        let today = CalendarDate("2026-10-12")!
        try vault.write(
            "goals/Su.md",
            "---\ntype: goal\nname: Su\nkey: su\nperiod: day\nkind: number\ntarget: 8\nunit: bardak\n---\n")
        try vault.index.rebuild(vaultRoot: vault.root)
        try await vault.store.settingGoalValue(on: today, key: "su", value: .number(3))
        try await vault.store.settingGoalValue(on: today, key: "su", value: .number(8))
        _ = try await vault.store.creatingGoal(
            name: "Yürüyüş", period: .day, kind: .number, target: 6000, unit: "adım")
        let live = try vault.index.goalStatuses(today: today)
        let rebuiltIndex = try VaultIndex()
        try rebuiltIndex.rebuild(vaultRoot: vault.root)
        let rebuilt = try rebuiltIndex.goalStatuses(today: today)
        let expected = try readModelGoalStatuses(vault.index, today: today)
        #expect(live == rebuilt)
        #expect(live == expected)
        #expect(try vault.index.goalLogs(key: "su").map(\.value) == ["8"])
        let su = try #require(live.first { $0.definition.key == "su" })
        #expect(su.status.progress.done == 8 && su.status.progress.isComplete && su.status.streak == 1)
        #expect(su.score == 100 && su.status.score == 100)
        let walk = try #require(live.first { $0.definition.name == "Yürüyüş" })
        #expect(walk.definition.key == "yuruyus" && walk.definition.unit == "adım")
        #expect(walk.status.streak == 0 && walk.status.score == nil && walk.score == nil)
        #expect(try vault.index.goalStatus(key: "su", today: today) == su)
    }
}

/// `VaultReadModel.rederive` for goals, with logs limited to its `goalLogs` window before
/// `GoalProgress`. The app's stored `goalStatuses` still folds every log; this is the window the
/// query and `goalLogs` share.
private func readModelGoalStatuses(_ index: VaultIndex, today: CalendarDate) throws -> [GoalStatusRow] {
    let start = today.addingDays(-399) ?? today
    let end = today.addingDays(6) ?? today
    let snapshot = try index.snapshot()
    let places = Dictionary(grouping: snapshot.links.filter { $0.key == "place" }, by: \.file)
    let goals =
        snapshot.entities.compactMap { GoalDefinition(entity: $0, place: places[$0.file]?.first?.target) }
        .sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
    let logs = Dictionary(grouping: snapshot.goalLogs, by: \.key).mapValues {
        $0.compactMap(GoalLog.init(indexed:)).filter { $0.day >= start && $0.day <= end }
    }
    return goals.map { goal in
        let entries = logs[goal.key] ?? []
        return GoalStatusRow(
            definition: goal,
            status: GoalProgress.compute(definition: goal, logs: entries, today: today),
            score: GoalProgress.score(definition: goal, logs: entries, through: today))
    }
}

private func expectOneGoalLogSelect(_ index: VaultIndex, today: CalendarDate) throws {
    let log = StatementLog()
    try index.database.read { db in db.trace { log.append($0.description) } }
    _ = try index.goalStatuses(today: today)
    try index.database.read { $0.trace(nil) }
    let selects = log.all.filter {
        let sql = $0.uppercased()
        return sql.contains("SELECT") && sql.contains("GOAL_LOGS")
    }
    #expect(selects.count == 1)
}
