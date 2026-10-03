import Foundation
import GoalTracking
import Testing
import VaultFormat
import VaultIndex

struct GoalQueryTests {
    @Test func sampleDefinitionsLogsAndSuccessfulWeeks() throws {
        let root = try Fixtures.root().appendingPathComponent("vaults/sample")
        let index = try VaultIndex()
        try index.rebuild(vaultRoot: root)
        let definitions = try index.goalDefinitions()
        #expect(definitions.map(\.key) == ["kitap", "spor", "su"])
        #expect(try index.goalLogs().count == 31)
        let sport = try #require(definitions.first { $0.key == "spor" })
        #expect(sport.place == "Tepe Spor Salonu")
        #expect(sport.period == .week && sport.kind == .boolean && sport.target == 3)
        let logs = try index.goalLogs(key: "spor").compactMap { GoalLog(indexed: $0) }
        #expect(logs.count == 6)
        let first = GoalProgress.compute(definition: sport, logs: logs, today: CalendarDate("2026-09-20")!)
        #expect(first.periodStart == CalendarDate("2026-09-14"))
        #expect(first.progress.done == 3 && first.streak == 1)
        let second = GoalProgress.compute(definition: sport, logs: logs, today: CalendarDate("2026-09-27")!)
        #expect(second.periodStart == CalendarDate("2026-09-21"))
        #expect(second.progress.done == 3 && second.streak == 2 && second.longestStreak == 2)
        let later = GoalProgress.compute(definition: sport, logs: logs, today: CalendarDate("2026-09-28")!)
        #expect(later.isPendingToday && later.streak == 2 && later.yearDone == 6)
        let filtered = try index.goalLogs(key: "spor", from: CalendarDate("2026-09-21"), to: CalendarDate("2026-09-25"))
        #expect(filtered.map(\.date) == ["2026-09-21", "2026-09-23", "2026-09-25"])
        #expect(try index.goalLogs(from: CalendarDate("2026-09-27"), to: CalendarDate("2026-09-14")).isEmpty)
        for (key, streak, longest, amount) in [("kitap", 8, 8, 320.0), ("su", 2, 4, 104.0)] {
            let definition = try #require(definitions.first { $0.key == key })
            let entries = try index.goalLogs(key: key).compactMap { GoalLog(indexed: $0) }
            let status = GoalProgress.compute(definition: definition, logs: entries, today: CalendarDate("2026-09-27")!)
            #expect(status.streak == streak && status.longestStreak == longest && status.yearDone == amount)
            #expect(definition.unit == (key == "su" ? "bardak" : "sayfa"))
        }
    }

    @Test func invalidSourceDefinitionsAndLogsRemainIndexed() throws {
        try withVault { root in
            try write(
                root, "goals/Spor.md", "---\ntype: goal\nkey: spor\nperiod: month\nkind: boolean\ntarget: 3\n---\n")
            try write(root, "goals/Su.md", "---\ntype: goal\nkey: su\nperiod: day\nkind: number\ntarget: 0\n---\n")
            try write(root, "journal/2026-10-04.md", "---\ngoals:\n  spor: text\n  su: -1\n---\n")
            let index = try VaultIndex()
            try index.rebuild(vaultRoot: root)
            #expect(try index.goalDefinitions().isEmpty)
            #expect(try index.snapshot().entities.count == 2)
            #expect(try index.goalLogs().count == 2)
            #expect(try index.goalLogs().compactMap { GoalLog(indexed: $0) }.isEmpty)
        }
    }
}
