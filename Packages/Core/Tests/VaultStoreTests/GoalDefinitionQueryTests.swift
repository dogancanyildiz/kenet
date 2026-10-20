import Foundation
import GRDB
import GoalTracking
import Testing
import VaultFormat
import VaultIndex

@testable import VaultIndex
@testable import VaultStore

/// The goal definition, reserved key, goal log and notification queries against the read model's
/// construction they replace (`VaultReadModel.rederive`: `goals`, `goalPlaceFiles`,
/// `reservedGoalKeys`, `goalLogs` from 399 days before `today` through 6 days after it).
struct GoalDefinitionQueryTests {
    @Test func sampleVaultMatchesReadModelConstruction() throws {
        let vault = try StoreVault(sample: true)
        defer { vault.remove() }
        let today = CalendarDate("2026-09-27")!
        let expected = try readModelGoalFields(vault.index, today: today)

        let rows = try vault.index.goalDefinitionsByName()
        #expect(rows.map(\.definition) == expected.goals)
        #expect(rows.map(\.definition.key) == ["kitap", "spor", "su"])
        #expect(rows.map(\.definition) == (try vault.index.goalStatuses(today: today)).map(\.definition))
        #expect(placeFiles(rows) == expected.goalPlaceFiles)
        let spor = try #require(rows.first { $0.definition.key == "spor" })
        #expect(spor.definition.place == "Tepe Spor Salonu")
        #expect(spor.placeFile == "places/Tepe Spor Salonu.md")
        #expect(rows.filter { $0.placeFile != nil }.count == 1)

        #expect(try vault.index.reservedGoalKeys() == expected.reservedGoalKeys)
        #expect(try vault.index.reservedGoalKeys() == ["kitap", "spor", "su"])

        let window = try vault.index.goalLogsByKey(
            from: try #require(today.addingDays(-399)), through: try #require(today.addingDays(6)))
        #expect(window == expected.goalLogs)
        // 14–26 September: kitap on 12 days, su on 13, spor on 6.
        #expect(window.mapValues(\.count) == ["kitap": 12, "su": 13, "spor": 6])

        // Three hand-read days, both edges included.
        let days = try vault.index.goalLogsByKey(
            from: CalendarDate("2026-09-20")!, through: CalendarDate("2026-09-22")!)
        #expect(days["kitap"]?.map(\.value) == [.number(30), .number(20), .number(35)])
        #expect(days["su"]?.map(\.value) == [.number(8), .number(8), .number(9)])
        #expect(days["spor"] == [GoalLog(day: CalendarDate("2026-09-21")!, value: .boolean(true))])
        let onlySpor = try vault.index.goalLogsByKey(
            from: CalendarDate("2026-09-14")!, through: CalendarDate("2026-09-27")!, keys: ["spor"])
        #expect(Array(onlySpor.keys) == ["spor"])
        #expect(
            onlySpor["spor"]?.map(\.day.description) == [
                "2026-09-14", "2026-09-16", "2026-09-18", "2026-09-21", "2026-09-23", "2026-09-25",
            ])
        #expect(try vault.index.goalLogsByKey(from: today, through: today, keys: []).isEmpty)

        // The week from 21 September: the two daily goals and their six days each; weekly spor is out.
        let week = try vault.index.notificationGoals(
            from: CalendarDate("2026-09-21")!, through: CalendarDate("2026-09-27")!)
        #expect(week.definitions.map(\.key) == ["kitap", "su"])
        #expect(week.logs["kitap"]?.map(\.value) == [20, 35, 20, 20, 25, 50].map { GoalValue.number($0) })
        #expect(week.logs["su"]?.map(\.value) == [8, 9, 8, 7, 10, 8].map { GoalValue.number($0) })
        #expect(week.logs["spor"] == nil)
        // The read model's window and the planned days give the same reminder for every planned day.
        for offset in 0..<7 {
            let day = try #require(CalendarDate("2026-09-21")!.addingDays(offset))
            #expect(pendingDaily(week, on: day) == pendingDaily(readModel: expected, on: day))
        }
    }

    /// Hand-made definitions and logs: natural name order, equal names in file order, invalid
    /// definitions reserved but not listed, place links that resolve or not, the log window's
    /// edges and the logs `GoalLog(indexed:)` rejects.
    @Test func edgeCasesAreHandCounted() throws {
        let vault = try StoreVault()
        defer { vault.remove() }
        let today = CalendarDate("2026-10-12")!
        try vault.write("places/Koru.md", "---\ntype: place\nname: Koru\n---\n")
        let goals = [
            (
                "goals/Ara 10.md",
                "name: Ara 10\nkey: ara-10\nperiod: day\nkind: boolean\ntarget: 1\nplace: \"[[Koru]]\""
            ),
            ("goals/Ara 9.md", "name: Ara 9\nkey: ara-9\nperiod: week\nkind: number\ntarget: 3\nplace: \"[[Yok]]\""),
            ("goals/bisiklet.md", "name: bisiklet\nkey: bisiklet\nperiod: day\nkind: number\ntarget: 2"),
            ("goals/Kopya A.md", "name: Kopya\nkey: kopya-a\nperiod: day\nkind: boolean\ntarget: 1"),
            ("goals/Kopya B.md", "name: Kopya\nkey: kopya-b\nperiod: year\nkind: boolean\ntarget: 1"),
            ("goals/Site.md", "name: Site\nkey: site\nperiod: year\nkind: milestone"),
            ("goals/Bozuk.md", "name: Bozuk\nkey: bozuk\nperiod: month\nkind: boolean\ntarget: 1"),
        ]
        for (path, fields) in goals { try vault.write(path, "---\ntype: goal\n" + fields + "\n---\n") }
        let first = try #require(today.addingDays(-3))
        let last = try #require(today.addingDays(3))
        let before = try #require(first.addingDays(-1))
        let after = try #require(last.addingDays(1))
        let values: [(CalendarDate, String)] = [
            (before, "  ara-10: true\n  bisiklet: 5"),
            (first, "  ara-10: true\n  bisiklet: -1\n  kopya-a: text"),
            (today, "  ara-10: false\n  bisiklet: 2\n  ara-9: 1\n  yok: true\n  bozuk: true"),
            (last, "  bisiklet: 3\n  kopya-a: true"),
            (after, "  bisiklet: 4"),
        ]
        for (day, lines) in values {
            try vault.write("journal/\(day).md", "---\ntype: journal\ndate: \(day)\ngoals:\n\(lines)\n---\n")
        }
        try vault.index.rebuild(vaultRoot: vault.root)
        let expected = try readModelGoalFields(vault.index, today: today)

        let rows = try vault.index.goalDefinitionsByName()
        #expect(rows.map(\.definition) == expected.goals)
        #expect(
            rows.map(\.definition.id) == [
                "goals/Ara 9.md", "goals/Ara 10.md", "goals/bisiklet.md", "goals/Kopya A.md", "goals/Kopya B.md",
                "goals/Site.md",
            ])
        #expect(placeFiles(rows) == expected.goalPlaceFiles)
        #expect(placeFiles(rows) == ["goals/Ara 10.md": "places/Koru.md"])
        #expect(rows.first { $0.definition.key == "ara-9" }?.definition.place == "Yok")
        #expect(rows.first { $0.definition.key == "ara-9" }?.placeFile == nil)

        let reserved = try vault.index.reservedGoalKeys()
        #expect(reserved == expected.reservedGoalKeys)
        #expect(reserved == ["ara-10", "ara-9", "bisiklet", "kopya-a", "kopya-b", "site", "bozuk"])

        let window = try vault.index.goalLogsByKey(from: first, through: last)
        #expect(window["ara-10"]?.map(\.value) == [.boolean(true), .boolean(false)])
        #expect(window["bisiklet"]?.map(\.value) == [.number(2), .number(3)])
        #expect(window["kopya-a"] == [GoalLog(day: last, value: .boolean(true))])
        #expect(window["yok"] == [GoalLog(day: today, value: .boolean(true))])
        #expect(window.keys.sorted() == ["ara-10", "ara-9", "bisiklet", "bozuk", "kopya-a", "yok"])
        let wide = try vault.index.goalLogsByKey(
            from: try #require(today.addingDays(-399)), through: try #require(today.addingDays(6)))
        #expect(wide == expected.goalLogs)
        #expect(wide["bisiklet"]?.count == 4)

        let week = try vault.index.notificationGoals(from: first, through: last)
        #expect(week.definitions.map(\.key) == ["ara-10", "bisiklet", "kopya-a"])
        #expect(week.logs.keys.sorted() == ["ara-10", "bisiklet", "kopya-a"])
        #expect(week.logs["bisiklet"]?.map(\.day) == [today, last])
        for offset in 0...6 {
            let day = try #require(first.addingDays(offset))
            #expect(pendingDaily(week, on: day) == pendingDaily(readModel: expected, on: day))
        }
        #expect(pendingDaily(week, on: today) == ["goals/Ara 10.md", "goals/Kopya A.md"])
        #expect(pendingDaily(week, on: last) == ["goals/Ara 10.md"])

        try vault.write(
            "goals/Ara 10.md",
            "---\ntype: goal\nname: Ara 10\nkey: ara-10\nperiod: week\nkind: boolean\ntarget: 1\n---\n")
        try vault.write("goals/bisiklet.md", "---\ntype: note\n---\n")
        try vault.write("goals/Kopya A.md", "---\ntype: note\n---\n")
        try vault.index.rebuild(vaultRoot: vault.root)
        #expect(try vault.index.notificationGoals(from: first, through: last) == NotificationGoals())
    }

    @Test func syntheticVaultMatchesReadModelConstruction() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let manifest = try SyntheticVault.generate(at: root, configuration: .compact)
        let index = try VaultIndex()
        try index.rebuild(vaultRoot: root)
        let today = manifest.endDate
        let expected = try readModelGoalFields(index, today: today)
        let rows = try index.goalDefinitionsByName()
        #expect(rows.map(\.definition) == expected.goals)
        #expect(rows.count == 6)
        #expect(placeFiles(rows) == expected.goalPlaceFiles)
        #expect(try index.reservedGoalKeys() == expected.reservedGoalKeys)
        let window = try index.goalLogsByKey(
            from: try #require(today.addingDays(-399)), through: try #require(today.addingDays(6)))
        #expect(window == expected.goalLogs)
        #expect(!window.isEmpty)
        let week = try index.notificationGoals(from: today, through: try #require(today.addingDays(6)))
        for offset in 0..<7 {
            let day = try #require(today.addingDays(offset))
            #expect(pendingDaily(week, on: day) == pendingDaily(readModel: expected, on: day))
        }
    }

    /// A store write and a new definition stay equal to a rebuild and to the read-model construction.
    @Test func storeEditsMatchAFreshIndex() async throws {
        let vault = try StoreVault(sample: true)
        defer { vault.remove() }
        let today = CalendarDate("2026-09-27")!
        try await vault.store.settingGoalValue(on: today, key: "su", value: .number(4))
        let path = try await vault.store.creatingGoal(name: "Yürüyüş", period: .day, kind: .boolean, target: 1)
        let rebuilt = try VaultIndex()
        try rebuilt.rebuild(vaultRoot: vault.root)
        let expected = try readModelGoalFields(vault.index, today: today)
        let live = try vault.index.goalDefinitionsByName()
        #expect(live == (try rebuilt.goalDefinitionsByName()))
        #expect(live.map(\.definition) == expected.goals)
        #expect(try vault.index.reservedGoalKeys() == (try rebuilt.reservedGoalKeys()))
        #expect(try vault.index.reservedGoalKeys() == expected.reservedGoalKeys)
        let from = try #require(today.addingDays(-399))
        let through = try #require(today.addingDays(6))
        #expect(try vault.index.goalLogsByKey(from: from, through: through) == expected.goalLogs)
        #expect(
            try vault.index.goalLogsByKey(from: from, through: through)
                == (try rebuilt.goalLogsByKey(from: from, through: through)))
        #expect(try vault.index.goalLogsByKey(from: today, through: today)["su"]?.map(\.value) == [.number(4)])
        #expect(live.first { $0.definition.id == path }?.definition.key == "yuruyus")
        #expect(try vault.index.reservedGoalKeys().contains("yuruyus"))
    }
}

/// The goal fields of `VaultReadModel.rederive` before they moved to queries, built the way it
/// built them: from a snapshot in path order. A key whose logs all fall outside the window is
/// dropped, as a query has no entry for it (the read model kept it with an empty list).
struct ReadModelGoalFields {
    let goals: [GoalDefinition]
    let goalPlaceFiles: [String: String]
    let reservedGoalKeys: Set<String>
    let goalLogs: [String: [GoalLog]]
}

func readModelGoalFields(_ index: VaultIndex, today: CalendarDate) throws -> ReadModelGoalFields {
    let snapshot = try index.snapshot()
    var places: [String: IndexedLink] = [:]
    for link in snapshot.links where link.key == "place" && places[link.file] == nil { places[link.file] = link }
    let goals = snapshot.entities.compactMap { GoalDefinition(entity: $0, place: places[$0.file]?.target) }
        .sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
    let goalIDs = Set(goals.map(\.id))
    let start = today.addingDays(-399) ?? today
    let end = today.addingDays(6) ?? today
    let logs = Dictionary(grouping: snapshot.goalLogs, by: \.key)
        .mapValues { $0.compactMap(GoalLog.init(indexed:)).filter { $0.day >= start && $0.day <= end } }
        .filter { !$0.value.isEmpty }
    return ReadModelGoalFields(
        goals: goals,
        goalPlaceFiles: places.compactMapValues(\.resolvedFile).filter { goalIDs.contains($0.key) },
        reservedGoalKeys: Set(snapshot.entities.compactMap(\.goalKey)), goalLogs: logs)
}

/// Each listed goal's resolved place file by goal file.
private func placeFiles(_ rows: [GoalDefinitionRow]) -> [String: String] {
    Dictionary(uniqueKeysWithValues: rows.compactMap { row in row.placeFile.map { (row.definition.id, $0) } })
}

/// The daily goals the reminder names on `day`, as the notification planner picks them.
private func pendingDaily(_ week: NotificationGoals, on day: CalendarDate) -> [String] {
    pendingDaily(goals: week.definitions, logs: week.logs, on: day)
}

private func pendingDaily(readModel fields: ReadModelGoalFields, on day: CalendarDate) -> [String] {
    pendingDaily(goals: fields.goals, logs: fields.goalLogs, on: day)
}

private func pendingDaily(goals: [GoalDefinition], logs: [String: [GoalLog]], on day: CalendarDate) -> [String] {
    goals.filter {
        $0.period == .day
            && !GoalProgress.compute(definition: $0, logs: logs[$0.key] ?? [], today: day).progress.isComplete
    }.map(\.id).sorted()
}
