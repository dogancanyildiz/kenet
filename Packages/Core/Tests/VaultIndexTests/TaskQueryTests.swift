import Foundation
import GRDB
import Testing
import VaultFormat

@testable import VaultIndex

struct TaskQueryTests {
    @Test func overdueTodayUpcomingAndUndatedQueriesRespectStatusAndDay() throws {
        try withVault { root in
            try write(
                root, "journal/2026-10-01.md",
                """
                ## Tasks
                - [ ] late 📅 2026-10-01 ^late
                - [x] closed 📅 2026-10-01 ✅ 2026-10-02 ^closed
                - [-] cancelled 📅 2026-10-01 ^cancel
                - [/] today 📅 2026-10-03 ^today
                - [?] later 📅 2026-10-05 ^later
                - [ ] undated ^undated
                - [ ] invalid 📅 2026-13-40 ^invalid
                - [x] finished undated ✅ 2026-10-02 ^finished
                """)
            try write(root, "notes/Work.md", "- [ ] note undated ^note\n- [ ] also later 📅 2026-10-05 ^other")
            let index = try VaultIndex()
            try index.rebuild(vaultRoot: root)
            let day = CalendarDate("2026-10-03")!
            #expect(try index.overdueTasks(asOf: day).map(\.identifier) == ["late"])
            #expect(try index.tasks(dueOn: day).map(\.identifier) == ["today"])
            #expect(try index.tasks(dueOn: CalendarDate("2026-10-01")!).count == 3)
            let groups = try index.upcomingTasks(from: day)
            #expect(groups.map(\.date.description) == ["2026-10-03", "2026-10-05"])
            #expect(groups.map { $0.tasks.map(\.identifier) } == [["today"], ["later", "other"]])
            #expect(try index.undatedOpenTasks().map(\.identifier) == ["undated", "invalid", "note"])
            #expect(
                try index.tasksCreated(on: CalendarDate("2026-10-01")!).map(\.identifier) == [
                    "undated", "invalid", "finished",
                ])
            #expect(try index.tasksCreated(on: day).isEmpty)
            #expect(try index.search("2026-13-40").contains { $0.file.hasPrefix("journal/") })
        }
    }

    @Test func completedOrderLimitAndMissingDateAreDeterministic() throws {
        try withVault { root in
            try write(
                root, "notes/Tasks.md",
                """
                - [x] old ✅ 2026-10-01 ^old
                - [X] newest ✅ 2026-10-03 ^new
                - [x] no date ^unknown
                - [-] cancel ✅ 2026-10-05 ^cancel
                - [x] tied ✅ 2026-10-03 ^tie
                """)
            let index = try VaultIndex()
            try index.rebuild(vaultRoot: root)
            #expect(try index.completedTasks().map(\.identifier) == ["new", "tie", "old", "unknown"])
            #expect(try index.completedTasks(limit: 2).map(\.identifier) == ["new", "tie"])
            #expect(try index.completedTasks(limit: 0).isEmpty)
            #expect(try index.completedTasks(limit: -1).isEmpty)
        }
    }

    @Test func resolvedBodyLinksDeduplicateAndProjectsUseTheFirstTag() throws {
        try withVault { root in
            try write(root, "people/Deniz.md", "---\ntype: person\nname: Deniz\n---")
            try write(
                root, "notes/Tasks.md",
                """
                ---
                owner: "[[Deniz]]"
                ---
                - [ ] [[Deniz]] and [[Deniz]] #project/ilk #project/son ^open
                - [x] [[Deniz]] #project/closed ^closed
                - [ ] [[Missing]] #project/ilk ^unresolved
                - [ ] parent
                  - [ ] [[Deniz]] #project/nested ^child
                """)
            let index = try VaultIndex()
            try index.rebuild(vaultRoot: root)
            #expect(try index.openTasks(linkedTo: "people/Deniz.md").map(\.identifier) == ["open", "child"])
            #expect(try index.openTasks(linkedTo: "people/Missing.md").isEmpty)
            #expect(try index.projects() == ["closed", "ilk", "nested"])
        }
    }

    @Test func projectsCompareCaseAndCanonicalUnicode() throws {
        try withVault { root in
            try write(
                root, "notes/Projects.md",
                "- [ ] A #project/Café\n- [x] B #project/café\n- [ ] C #project/CAFÉ\n- [ ] D #project/Café/mobile")
            let index = try VaultIndex()
            try index.rebuild(vaultRoot: root)
            #expect(try index.projects() == ["CAFÉ", "Café/mobile"])
        }
    }

    @Test func sampleTasksExposeFieldsAndOpenEntityLinks() throws {
        let index = try VaultIndex()
        try index.rebuild(vaultRoot: Fixtures.root().appendingPathComponent("vaults/sample"))
        #expect(try index.tasks(dueOn: CalendarDate("2026-09-14")!).contains { $0.priority == "⏫" })
        #expect(try index.completedTasks().first?.doneDate == "2026-09-27")
        #expect(
            try index.overdueTasks(asOf: CalendarDate("2026-09-27")!).allSatisfy {
                !["done", "cancelled"].contains($0.status)
            })
        #expect(try !index.openTasks(linkedTo: "people/Deniz Arıkan.md").isEmpty)
        #expect(try !index.projects().isEmpty)
    }

    @Test func schemaThreeIsErasedAndTaskIndexesExist() throws {
        try withVault { root in
            let url = root.appendingPathComponent("index.sqlite")
            let old = try DatabaseQueue(path: url.path)
            try old.write { try $0.execute(sql: "CREATE TABLE old_data (value TEXT); PRAGMA user_version=3") }
            let index = try VaultIndex(databaseURL: url)
            #expect(try index.files().isEmpty)
            #expect(try index.database.read { try Int.fetchOne($0, sql: "PRAGMA user_version") } == 6)
            #expect(try index.database.read { try $0.tableExists("old_data") } == false)
            #expect(
                try index.database.read {
                    try String.fetchAll(
                        $0,
                        sql:
                            "SELECT name FROM sqlite_master WHERE name IN ('task_due_dates','task_done_dates') ORDER BY name"
                    )
                } == ["task_done_dates", "task_due_dates"])
        }
    }

    @Test func recurrenceRefreshAndPriorityQueryOrder() throws {
        try withVault { root in
            let path = "notes/Recurring.md"
            try write(
                root, path,
                "- [ ] Normal 📅 2026-10-04 🔁 every day ^normal\n- [ ] High 📅 2026-10-04 ⏫ 🔁 every weekday ^high\n- [ ] Low 📅 2026-10-04 🔽 ^low\n- [ ] Medium 📅 2026-10-04 🔼 ^medium"
            )
            let index = try VaultIndex()
            try index.rebuild(vaultRoot: root)
            #expect(
                try index.tasks(dueOn: CalendarDate("2026-10-04")!).map(\.identifier) == [
                    "high", "medium", "normal", "low",
                ])
            #expect(try index.tasks(dueOn: CalendarDate("2026-10-04")!).first?.recurrence == "every weekday")
            try write(root, path, "- [ ] Normal 📅 2026-10-04 🔁 every 2 weeks ^normal")
            try index.update(paths: [path], vaultRoot: root)
            #expect(try index.tasks(dueOn: CalendarDate("2026-10-04")!).first?.recurrence == "every 2 weeks")
            try equivalent(index, root)
        }
    }

    @Test func taskFieldChangesRefreshToTheSameSnapshotAsRebuild() throws {
        try withVault { root in
            let path = "journal/2026-10-01.md"
            try write(root, path, "- [ ] x 📅 2026-10-05 #project/old ^task")
            let index = try VaultIndex()
            try index.rebuild(vaultRoot: root)
            try write(root, path, "- [X] new 🛫 2026-10-02 📅 2026-10-07 ✅ 2026-10-03 🔽 #project/new ^task")
            try index.update(paths: [path], vaultRoot: root)
            try equivalent(index, root)
            #expect(try index.completedTasks().first?.project == "new")
            #expect(try index.tasks(dueOn: CalendarDate("2026-10-05")!).isEmpty)
            #expect(try index.tasks(dueOn: CalendarDate("2026-10-07")!).first?.startDate == "2026-10-02")
        }
    }
}
