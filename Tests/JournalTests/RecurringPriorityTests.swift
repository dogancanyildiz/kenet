import Foundation
import Testing
import VaultFormat

@testable import Journal

@MainActor struct RecurringPriorityTests {
    @Test func quickEntryExtractsRecurrenceBeforeDateAndSetsPriority() async throws {
        for (input, priority, rule, due) in [
            ("!! Call tomorrow every week", TaskPriority.high, "every week", "2026-10-04"),
            ("Ara her pazartesi !", .medium, "every monday", nil),
            ("! Ara her 3 gün tamamlanınca", .medium, "every 3 days when done", nil),
        ] {
            let context = try TaskTestContext()
            defer { context.clean() }
            await context.start()
            let model = context.model()
            model.mode = .task
            model.text = input
            #expect(model.recurrenceExpression?.recurrence.rule == rule)
            #expect(model.dueDate?.description == due)
            #expect(await model.submit(time: nil))
            let task = try #require(context.document().bodyLines.tasks.first)
            #expect(task.priority == priority)
            #expect(task.recurrence?.rule == rule)
            #expect(task.dueDate?.description == due)
            #expect(!task.text.contains("!") && !task.text.contains("every") && !task.text.contains("her"))
            #expect(model.taskPriority == nil && model.taskRecurrence == nil)
        }
    }
    @Test func explicitPriorityAndLiteralMarksSurviveAndEventIsUnchanged() async throws {
        let context = try TaskTestContext()
        defer { context.clean() }
        await context.start()
        let model = context.model()
        model.mode = .task
        model.text = "!! Plan 🔽"
        #expect(await model.submit(time: nil))
        #expect(try context.document().bodyLines.tasks.first?.priority == .low)
        model.text = "Plan !!!"
        #expect(await model.submit(time: nil))
        #expect(context.store.content.tasks.last?.sourceText == "Plan !!!")
        model.mode = .event
        model.text = "! Note every week"
        #expect(await model.submit(time: nil))
        let eventFile = context.root.appendingPathComponent("journal/\(LocalDay.today()).md")
        let document = RawDocument(bytes: try Data(contentsOf: eventFile))
        #expect(document.bodyLines.events.last?.block.text == "! Note every week")
    }
    @Test func writtenRecurrenceSurvivesDateExtraction() async throws {
        let context = try TaskTestContext()
        defer { context.clean() }
        await context.start()
        let model = context.model()
        model.mode = .task
        model.text = "!! Plan 🔁 every monday 📅 2026-10-05"
        #expect(model.dateExpression == nil)
        #expect(await model.submit(time: nil))
        let task = try #require(context.document().bodyLines.tasks.first)
        #expect(task.recurrence?.rule == "every monday")
        #expect(task.dueDate == CalendarDate("2026-10-05"))
        #expect(task.priority == .high && task.text == "Plan")
    }

    @Test func completingFromTasksPublishesFreshRowAndEditorChangesRecurrence() async throws {
        let context = try TaskTestContext()
        defer { context.clean() }
        await context.start()
        #expect(
            await context.store.addTask(on: context.today, text: "Plan 🔁 every week #project/demo", due: context.today))
        let tasks = TasksModel(store: context.store, today: { context.today })
        let old = try #require(tasks.agenda.first?.rows.first)
        #expect(await tasks.toggle(old))
        #expect(tasks.completed.count == 1)
        let next = try #require(context.store.content.tasks.first { !$0.isClosed })
        #expect(next.id != old.id)
        #expect(next.due == context.today.addingDays(7))
        #expect(next.recurrence?.rule == "every week")
        let editor = TaskEditorModel(store: context.store, row: next)
        await editor.load()
        #expect(await editor.setRecurrence(TaskRecurrence("every month when done")))
        let changed = try #require(context.store.content.tasks.first { $0.id == next.id })
        #expect(changed.recurrence?.rule == "every month when done")
        let removal = TaskEditorModel(store: context.store, row: changed)
        await removal.load()
        #expect(await removal.setRecurrence(nil))
        #expect(context.store.content.tasks.first { $0.id == next.id }?.recurrenceSource == nil)
    }
    @Test func allOpenListsUsePriorityWithinDay() async throws {
        let context = try TaskTestContext(sample: true)
        defer { context.clean() }
        await context.start()
        try """
        ## Tasks
        - [ ] [[Deniz Arıkan]] Normal 📅 2026-10-03 #project/order ^normal
        - [ ] [[Deniz Arıkan]] Low 📅 2026-10-03 🔽 #project/order ^low
        - [ ] [[Deniz Arıkan]] Medium 📅 2026-10-03 🔼 #project/order ^medium
        - [ ] [[Deniz Arıkan]] High 📅 2026-10-03 ⏫ #project/order ^high
        """.write(to: context.file, atomically: true, encoding: .utf8)
        await context.store.refresh()
        let tasks = TasksModel(store: context.store, today: { context.today })
        tasks.projectFilter = "order"
        let expected = ["high", "medium", "normal", "low"]
        #expect(tasks.agenda.first?.rows.compactMap(\.sourceIdentifier) == expected)
        #expect(
            TaskGroups(rows: context.store.content.tasks, on: context.today, isToday: true).dated.compactMap(
                \.sourceIdentifier) == expected)
        #expect(
            ProjectModel(store: context.store, name: "order").openGroups.first?.rows.compactMap(\.sourceIdentifier)
                == expected)
        let entity = TasksModel.openTasks(in: context.store, linkedTo: "people/Deniz Arıkan.md").filter {
            $0.project == "order"
        }
        #expect(entity.compactMap(\.sourceIdentifier) == expected)
    }
    @Test func changedDiskRuleIsStaleEvenWhenTextAndDatesMatch() async throws {
        let context = try TaskTestContext()
        defer { context.clean() }
        await context.start()
        #expect(await context.store.addTask(on: context.today, text: "Plan 🔁 every week", due: context.today))
        let row = try #require(context.store.content.tasks.first)
        let source = try String(contentsOf: context.file, encoding: .utf8)
        try source.replacingOccurrences(of: "every week", with: "every day").write(
            to: context.file, atomically: true, encoding: .utf8)
        let editor = TaskEditorModel(store: context.store, row: row)
        await editor.load()
        #expect(editor.target == nil && editor.errorText != nil)
    }

    @Test func unrecognizedRecurrenceIsNotEditableWhileKnownRuleIs() async throws {
        let context = try TaskTestContext()
        defer { context.clean() }
        await context.start()
        try Data(
            """
            ## Tasks
            - [ ] Su ver 🔁 every week bahçedeki çiçeklere 📅 2026-10-10 ^unknown
            - [ ] Plan 🔁 every week 📅 2026-10-03 ^known

            """.utf8
        ).write(to: context.file)
        await context.store.refresh()
        let unknown = try #require(context.store.content.tasks.first { $0.sourceIdentifier == "unknown" })
        let known = try #require(context.store.content.tasks.first { $0.sourceIdentifier == "known" })
        #expect(unknown.recurrenceSource != nil && unknown.recurrence == nil)
        #expect(known.recurrence?.rule == "every week")
        let blocked = TaskEditorModel(store: context.store, row: unknown)
        let allowed = TaskEditorModel(store: context.store, row: known)
        #expect(!blocked.canEditRecurrence)
        #expect(allowed.canEditRecurrence)
        await blocked.load()
        #expect(await !blocked.setRecurrence(TaskRecurrence("every week")))
        #expect(
            String(decoding: try Data(contentsOf: context.file), as: UTF8.self)
                .contains("every week bahçedeki"))
    }
}
