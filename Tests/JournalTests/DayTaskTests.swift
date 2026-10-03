import Foundation
import Testing
import VaultFormat
import VaultStore

@testable import Journal

@MainActor
struct DayTaskTests {
    @Test func todayGroupsUseSampleCopyAndExcludeClosedOrOldUndated() async throws {
        let context = try TaskTestContext(sample: true)
        defer { context.clean() }
        await context.start()
        try Data(
            "## Tasks\n- [ ] late 📅 2026-10-02 ^late\n- [ ] today 📅 2026-10-03 ^today\n- [ ] created ^created\n- [x] closed 📅 2026-10-03 ✅ 2026-10-03 ^closed\n- [-] cancelled 📅 2026-10-02 ^cancel\n"
                .utf8
        ).write(to: context.file)
        await context.store.refresh()
        let groups = TaskGroups(rows: context.store.content.tasks, on: context.today, isToday: true)
        #expect(groups.overdue.contains { $0.sourceText == "late" })
        #expect(groups.dated.map(\.sourceText) == ["today"])
        #expect(groups.created.map(\.sourceText) == ["created"])
        #expect(groups.overdue.allSatisfy { !$0.isClosed && $0.due! < context.today })
        let past = TaskGroups(rows: context.store.content.tasks, on: CalendarDate("2026-10-02")!, isToday: false)
        #expect(past.overdue.isEmpty)
        #expect(past.dated.map(\.sourceText) == ["late", "cancelled"])
    }

    @Test func completionWritesLocalDateFadesAndThenLeavesToday() async throws {
        let context = try TaskTestContext()
        defer { context.clean() }
        await context.start()
        #expect(await context.store.addTask(on: context.today, text: "finish", due: context.today))
        let row = try context.row("finish")
        let model = DayTasksModel(store: context.store, day: context.today, isToday: true)
        let completing = Task { await model.complete(row, today: context.today) }
        for _ in 0..<100 {
            if model.completed.contains(row.id) { break }
            try await Task.sleep(for: .milliseconds(5))
        }
        #expect(model.completed.contains(row.id))
        #expect(model.groups.dated.contains { $0.id == row.id })
        #expect(await completing.value)
        let task = try #require(context.document().bodyLines.tasks.first)
        #expect(task.rawStatus == "x" && task.doneDate == context.today)
        #expect(
            String(decoding: try Data(contentsOf: context.file), as: UTF8.self).contains(
                "- [x] finish 📅 2026-10-03 ✅ 2026-10-03 ^"))
        #expect(model.groups.isEmpty)
    }

    @Test func dateAndPriorityEditsPreserveOtherBytesAndUpdateGroups() async throws {
        let context = try TaskTestContext()
        defer { context.clean() }
        await context.start()
        let source = "\u{FEFF}## Tasks\r\n- [ ] call 📅 2026-10-03 x ^task\r\n  keep\r\n"
        try Data(source.utf8).write(to: context.file)
        await context.store.refresh()
        let editor = TaskEditorModel(store: context.store, row: try context.row("call x"))
        await editor.load()
        #expect(await editor.setDue(CalendarDate("2026-10-05")))
        #expect(
            try Data(contentsOf: context.file)
                == Data(source.replacingOccurrences(of: "2026-10-03", with: "2026-10-05").utf8))
        let remove = TaskEditorModel(store: context.store, row: try context.row("call x"))
        await remove.load()
        #expect(await remove.setDue(nil))
        #expect(
            try Data(contentsOf: context.file) == Data(source.replacingOccurrences(of: " 📅 2026-10-03", with: "").utf8))
        #expect(TaskGroups(rows: context.store.content.tasks, on: context.today, isToday: true).created.count == 1)
        let priority = TaskEditorModel(store: context.store, row: try context.row("call x"))
        await priority.load()
        #expect(await priority.setPriority(.high))
        #expect(try context.row("call x").priority == .high)
    }

    @Test func staleTargetRefreshesWithoutOverwritingExternalEdit() async throws {
        let context = try TaskTestContext()
        defer { context.clean() }
        await context.start()
        #expect(await context.store.addTask(on: context.today, text: "old", due: nil))
        let row = try context.row("old")
        let editor = TaskEditorModel(store: context.store, row: row)
        await editor.load()
        let external = try Data(contentsOf: context.file)
        let changed = Data(String(decoding: external, as: UTF8.self).replacingOccurrences(of: "old", with: "new").utf8)
        try changed.write(to: context.file)
        #expect(await !editor.setDue(context.today))
        #expect(editor.target == nil && editor.errorText == DayEditError.message(for: VaultStoreError.staleTarget))
        #expect(try Data(contentsOf: context.file) == changed)
        #expect(context.store.content.tasks.contains { $0.sourceText == "new" })
        await #expect(throws: VaultStoreError.staleTarget) {
            try await context.store.completeTask(row, on: context.today)
        }
    }

    @Test func textEditingAndDeleteTargetOnlyOneTask() async throws {
        let context = try TaskTestContext()
        defer { context.clean() }
        await context.start()
        #expect(await context.store.addTask(on: context.today, text: "old", due: context.today))
        #expect(await context.store.addTask(on: context.today, text: "keep", due: nil))
        let editor = TaskEditorModel(store: context.store, row: try context.row("old"))
        await editor.load()
        editor.text = "new"
        #expect(await editor.save())
        #expect(try context.row("new").due == context.today)
        let delete = TaskEditorModel(store: context.store, row: try context.row("new"))
        await delete.load()
        #expect(await delete.delete())
        #expect(context.store.content.tasks.map(\.sourceText) == ["keep"])
    }
}
