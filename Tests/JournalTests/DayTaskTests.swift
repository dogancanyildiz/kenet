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
        let groups = TaskGroups(rows: try await context.store.allTasks(), on: context.today, isToday: true)
        #expect(groups.overdue.contains { $0.sourceText == "late" })
        #expect(groups.dated.map(\.sourceText) == ["today"])
        #expect(groups.created.map(\.sourceText) == ["created"])
        #expect(groups.overdue.allSatisfy { !$0.isClosed && $0.due! < context.today })
        let past = TaskGroups(
            rows: try await context.store.allTasks(), on: CalendarDate("2026-10-02")!, isToday: false)
        #expect(past.overdue.isEmpty)
        #expect(past.dated.map(\.sourceText) == ["late", "cancelled"])
    }

    /// Decision 82: an open task written today stays on Today whatever its due day, once.
    @Test func todayKeepsOpenTasksWrittenTodayWhateverTheirDueDay() async throws {
        let context = try TaskTestContext()
        defer { context.clean() }
        await context.start()
        try Data(
            ("## Tasks\n- [ ] later 📅 2026-10-10 ^later\n- [ ] today 📅 2026-10-03 ^today\n"
                + "- [ ] late 📅 2026-10-01 ^late\n- [ ] undated ^undated\n"
                + "- [x] later done 📅 2026-10-10 ✅ 2026-10-02 ^ldone\n- [-] later cancelled 📅 2026-10-10 ^lcancel\n")
                .utf8
        ).write(to: context.file)
        try Data(
            "## Tasks\n- [ ] yesterday later 📅 2026-10-10 ^ylater\n- [x] yesterday done 📅 2026-10-10 ✅ 2026-10-03 ^ydone\n"
                .utf8
        ).write(
            to: context.root.appendingPathComponent("journal/2026-10-02.md"))
        await context.store.refresh()
        let groups = await DayTasksModel.loaded(store: context.store, day: context.today, isToday: true).groups
        #expect(groups.overdue.map(\.sourceText) == ["late"])
        #expect(groups.dated.map(\.sourceText) == ["today"])
        #expect(groups.created.map(\.sourceText) == ["later", "undated"])
        let ids = (groups.overdue + groups.dated + groups.created).map(\.id)
        #expect(Set(ids).count == ids.count)
        // A past day page keeps the open task written that day and due later too, not a closed one
        // (the query leaves it out; the groups agree when given every row).
        let yesterday = CalendarDate("2026-10-02")!
        let past = await DayTasksModel.loaded(store: context.store, day: yesterday, isToday: false).groups
        #expect(past.created.map(\.sourceText) == ["yesterday later"])
        let all = TaskGroups(rows: try await context.store.allTasks(), on: yesterday, isToday: false)
        #expect(all.created.map(\.sourceText) == ["yesterday later"])
    }

    @Test func completionWritesLocalDateFadesAndThenLeavesToday() async throws {
        let context = try TaskTestContext()
        defer { context.clean() }
        await context.start()
        #expect(await context.store.addTask(on: context.today, text: "finish", due: context.today))
        let row = try await context.row("finish")
        let model = await DayTasksModel.loaded(store: context.store, day: context.today, isToday: true)
        let completing = Task { await model.complete(row, today: context.today) }
        await waitUntil { model.completed.contains(row.id) }
        #expect(model.completed.contains(row.id))
        #expect(model.groups.dated.contains { $0.id == row.id })
        #expect(await completing.value)
        let task = try #require(context.document().bodyLines.tasks.first)
        #expect(task.rawStatus == "x" && task.doneDate == context.today)
        #expect(
            String(decoding: try Data(contentsOf: context.file), as: UTF8.self).contains(
                "- [x] finish 📅 2026-10-03 ✅ 2026-10-03 ^"))
        await model.load()
        #expect(model.groups.isEmpty)
    }

    @Test func dateAndPriorityEditsPreserveOtherBytesAndUpdateGroups() async throws {
        let context = try TaskTestContext()
        defer { context.clean() }
        await context.start()
        let source = "\u{FEFF}## Tasks\r\n- [ ] call 📅 2026-10-03 x ^task\r\n  keep\r\n"
        try Data(source.utf8).write(to: context.file)
        await context.store.refresh()
        let editor = TaskEditorModel(store: context.store, row: try await context.row("call x"))
        await editor.load()
        #expect(await editor.setDue(CalendarDate("2026-10-05")))
        #expect(
            try Data(contentsOf: context.file)
                == Data(source.replacingOccurrences(of: "2026-10-03", with: "2026-10-05").utf8))
        let remove = TaskEditorModel(store: context.store, row: try await context.row("call x"))
        await remove.load()
        #expect(await remove.setDue(nil))
        #expect(
            try Data(contentsOf: context.file) == Data(source.replacingOccurrences(of: " 📅 2026-10-03", with: "").utf8))
        let created = TaskGroups(rows: try await context.store.allTasks(), on: context.today, isToday: true).created
        #expect(created.count == 1)
        let priority = TaskEditorModel(store: context.store, row: try await context.row("call x"))
        await priority.load()
        #expect(await priority.setPriority(.high))
        #expect(try await context.row("call x").priority == .high)
    }

    @Test func staleTargetRefreshesWithoutOverwritingExternalEdit() async throws {
        let context = try TaskTestContext()
        defer { context.clean() }
        await context.start()
        #expect(await context.store.addTask(on: context.today, text: "old", due: nil))
        let row = try await context.row("old")
        let editor = TaskEditorModel(store: context.store, row: row)
        await editor.load()
        let external = try Data(contentsOf: context.file)
        let changed = Data(String(decoding: external, as: UTF8.self).replacingOccurrences(of: "old", with: "new").utf8)
        try changed.write(to: context.file)
        #expect(await !editor.setDue(context.today))
        #expect(editor.target == nil && editor.errorText == DayEditError.message(for: VaultStoreError.staleTarget))
        #expect(try Data(contentsOf: context.file) == changed)
        #expect(try await context.store.allTasks().contains { $0.sourceText == "new" })
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
        let editor = TaskEditorModel(store: context.store, row: try await context.row("old"))
        await editor.load()
        editor.text = "new"
        #expect(await editor.save())
        #expect(try await context.row("new").due == context.today)
        let delete = TaskEditorModel(store: context.store, row: try await context.row("new"))
        await delete.load()
        #expect(await delete.delete())
        #expect(try await context.store.allTasks().map(\.sourceText) == ["keep"])
    }
}
