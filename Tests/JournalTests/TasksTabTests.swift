import Foundation
import Testing
import VaultFormat

@testable import Journal

@MainActor struct TasksTabTests {
    @Test func sampleAgendaGroupsAndOverdueOrder() async throws {
        let context = try TaskTestContext(sample: true)
        defer { context.clean() }
        await context.start()
        let day = CalendarDate("2026-09-20")!
        let model = TasksModel(store: context.store, today: { day })
        #expect(
            model.agenda.map(\.date) == [
                nil, day, CalendarDate("2026-09-22"), CalendarDate("2026-09-24"), CalendarDate("2026-09-25"),
                CalendarDate("2026-09-26"), CalendarDate("2026-09-28"),
            ])
        #expect(
            model.agenda.first?.rows.map { $0.due!.description } == [
                "2026-09-14", "2026-09-15", "2026-09-17", "2026-09-18", "2026-09-18",
            ])
        #expect(model.agenda.flatMap(\.rows).allSatisfy { !$0.isClosed })
    }

    @Test func sampleUndatedAndCompleted() async throws {
        let context = try TaskTestContext(sample: true)
        defer { context.clean() }
        await context.start()
        let model = TasksModel(store: context.store)
        #expect(model.undated.count == 3)
        #expect(model.undated.allSatisfy { !$0.isClosed && $0.due == nil })
        #expect(model.undated.first?.createdDate == CalendarDate("2026-09-19"))
        #expect(
            model.completed.map { $0.done!.description } == [
                "2026-09-27", "2026-09-25", "2026-09-24", "2026-09-23", "2026-09-20", "2026-09-19", "2026-09-18",
                "2026-09-15", "2026-09-14",
            ])
    }

    @Test func personPlaceAndProjectFilters() async throws {
        let context = try TaskTestContext(sample: true)
        defer { context.clean() }
        await context.start()
        let model = TasksModel(store: context.store)
        model.entityFilter = "people/Deniz Arıkan.md"
        #expect(model.undated.count == 1)
        #expect(model.agenda.isEmpty)
        model.entityFilter = "places/Liman Ofis.md"
        #expect(model.undated.count == 1)
        #expect(model.completed.count == 1)
        model.clearFilters()
        model.projectFilter = "tedarik"
        #expect(model.agenda.flatMap(\.rows).count == 1)
        #expect(model.projects.contains("tedarik"))
        model.entityFilter = "people/Deniz Arıkan.md"
        #expect(model.agenda.isEmpty)
        model.clearFilters()
        #expect(!model.hasFilters)
    }

    @Test func entityOpenTasksIncludeNoteTasks() async throws {
        let context = try TaskTestContext(sample: true)
        defer { context.clean() }
        await context.start()
        let rows = TasksModel.openTasks(in: context.store, linkedTo: "people/Deniz Arıkan.md")
        #expect(rows.count == 1)
        #expect(rows.first?.file == "notes/Proje Fikirleri.md")
        #expect(TasksModel.openTasks(in: context.store, linkedTo: "people/Missing.md").isEmpty)
    }

    @Test func reopenPreservesOtherBytesAndRemovesCompletion() async throws {
        let context = try TaskTestContext(sample: true)
        defer { context.clean() }
        await context.start()
        let model = TasksModel(store: context.store)
        let row = try #require(model.completed.first)
        let file = context.root.appendingPathComponent(row.file)
        let before = try String(contentsOf: file, encoding: .utf8)
        #expect(await model.toggle(row))
        let after = try String(contentsOf: file, encoding: .utf8)
        #expect(
            after
                == before.replacingOccurrences(
                    of: "- [x] Yeni hafta hazırlıklarını tamamla ✅ 2026-09-27",
                    with: "- [ ] Yeni hafta hazırlıklarını tamamla"))
        #expect(!model.completed.contains { $0.id == row.id })
        #expect(model.undated.contains { $0.id == row.id })
    }

    @Test func completedLimitAndUnlimitedAgenda() async throws {
        let context = try TaskTestContext()
        defer { context.clean() }
        await context.start()
        let lines = (0..<55).map { "- [x] Finished \($0) ✅ 2026-10-03 ^done\($0)" }.joined(separator: "\n")
        try ("## Tasks\n" + lines + "\n- [ ] Distant 📅 2099-12-31 ^distant\n").write(
            to: context.file, atomically: true, encoding: .utf8)
        await context.store.refresh()
        let model = TasksModel(store: context.store)
        #expect(model.completed.count == 50)
        #expect(model.agenda.last?.date == CalendarDate("2099-12-31"))
    }

    @Test func continuationResolvedLinksAndProjectEntry() async throws {
        let context = try TaskTestContext(sample: true)
        defer { context.clean() }
        await context.start()
        #expect(await context.store.addTask(on: context.today, text: "Plan #project/mobile", due: nil))
        let file = context.root.appendingPathComponent("notes/Linked Task.md")
        try "- [ ] Body link\n  [[Deniz Arıkan]]\n".write(to: file, atomically: true, encoding: .utf8)
        await context.store.refresh()
        let model = TasksModel(store: context.store)
        #expect(model.projects.contains("mobile"))
        #expect(try String(contentsOf: context.file, encoding: .utf8).contains("Plan #project/mobile"))
        #expect(TasksModel.openTasks(in: context.store, linkedTo: "people/Deniz Arıkan.md").count == 2)
    }
}
