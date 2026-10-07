import Foundation
import Testing
import VaultFormat

@testable import Journal

@MainActor struct KanbanTests {
    @Test func statusColumnsHideCancelledAndLimitDoneToThirtyDays() async throws {
        let context = try TaskTestContext()
        defer { context.clean() }
        await context.start()
        try """
        ## Tasks
        - [ ] Todo ^todo
        - [?] Custom ^custom
        - [/] Started ^started
        - [x] Today ✅ 2026-10-03 ^today
        - [X] Boundary ✅ 2026-09-04 ^boundary
        - [x] Old ✅ 2026-09-03 ^old
        - [x] Future ✅ 2026-10-04 ^future
        - [x] No date ^nodate
        - [-] Cancel ^cancel
        """.write(to: context.file, atomically: true, encoding: .utf8)
        await context.store.refresh()
        let model = board(context)
        #expect(model.columns.map { $0.rows.count } == [2, 1, 2])
        #expect(model.columns.map(\.destination) == [.status(.todo), .status(.inProgress), .status(.done)])
        model.showsCancelled = true
        #expect(model.columns.map { $0.rows.count } == [2, 1, 2, 1])
        #expect(model.columns.last?.destination == .status(.cancelled))
    }

    @Test func projectColumnsNormalizeNamesAndKeepUnassignedTarget() async throws {
        let context = try TaskTestContext()
        defer { context.clean() }
        await context.start()
        try """
        ## Tasks
        - [ ] One #project/Café ^one
        - [/] Two #project/café ^two
        - [ ] Child #project/Café/mobile ^child
        - [ ] Free ^free
        - [-] Cancel #project/empty ^cancel
        """.write(to: context.file, atomically: true, encoding: .utf8)
        await context.store.refresh()
        let model = board(context)
        model.grouping = .project
        #expect(model.columns.count == 4)
        #expect(model.columns.first { $0.rows.count == 2 }?.rows.compactMap(\.sourceIdentifier) == ["one", "two"])
        #expect(model.columns.last?.rows.compactMap(\.sourceIdentifier) == ["free"])
        #expect(model.columns.first { $0.name == "empty" }?.rows.isEmpty == true)
        model.tasks.projectFilter = "CAFÉ"
        #expect(model.columns.flatMap(\.rows).count == 2)
    }

    @Test func multiplePeopleDuplicateCardsAndPlaceOrUnresolvedLinkDoesNotBecomePerson() async throws {
        let context = try TaskTestContext(sample: true)
        defer { context.clean() }
        await context.start()
        try """
        ## Tasks
        - [ ] [[Deniz Arıkan]] [[Ece Yalın]] Shared #project/board ^shared
        - [ ] [[Liman Ofis]] Place #project/board ^place
        - [ ] [[Unknown Person]] Unresolved #project/board ^unresolved
        """.write(to: context.file, atomically: true, encoding: .utf8)
        await context.store.refresh()
        let model = board(context)
        model.tasks.projectFilter = "board"
        model.grouping = .person
        #expect(model.columns.count == 3)
        #expect(model.columns.dropLast().map { $0.rows.compactMap(\.sourceIdentifier) } == [["shared"], ["shared"]])
        #expect(Set(model.columns.last!.rows.compactMap(\.sourceIdentifier)) == ["place", "unresolved"])
        model.tasks.entityFilter = "people/Deniz Arıkan.md"
        #expect(model.columns.dropLast().flatMap(\.rows).count == 2)
        #expect(model.columns.last?.rows.isEmpty == true)
        model.tasks.entityFilter = "places/Liman Ofis.md"
        #expect(model.columns.count == 1 && model.columns.first?.rows.first?.sourceIdentifier == "place")
    }

    @Test func columnsSortByDuePriorityTextWithoutReorderingFile() async throws {
        let context = try TaskTestContext()
        defer { context.clean() }
        await context.start()
        let source = """
            ## Tasks
            - [ ] Undated ⏫ ^undated
            - [ ] Zebra 📅 2026-10-03 ^zebra
            - [ ] Low 📅 2026-10-03 🔽 ^low
            - [ ] Alpha 📅 2026-10-03 ^alpha
            - [ ] Medium 📅 2026-10-03 🔼 ^medium
            - [ ] High 📅 2026-10-03 ⏫ ^high
            - [ ] Early 📅 2026-10-02 ^early
            """
        try source.write(to: context.file, atomically: true, encoding: .utf8)
        await context.store.refresh()
        let model = board(context)
        #expect(
            model.columns.first?.rows.compactMap(\.sourceIdentifier) == [
                "early", "high", "medium", "alpha", "zebra", "low", "undated",
            ])
        model.grouping = .project
        #expect(try Data(contentsOf: context.file) == Data(source.utf8))
    }

    @Test func statusMovePreservesSurroundingBytesBOMAndCRLF() async throws {
        let context = try TaskTestContext()
        defer { context.clean() }
        await context.start()
        let source =
            "\u{feff}---\r\ntype: journal\r\ndate: 2026-10-03\r\ncustom: 'keep'\r\n---\r\n\r\n## Tasks\r\n- [ ] Plan 📅 2026-10-06 #project/Alpha ^task\r\n  Note untouched\r\n\r\n## Other\r\nCustom bytes  \r\n"
        try Data(source.utf8).write(to: context.file)
        await context.store.refresh()
        let model = board(context)
        let row = try #require(context.store.content.tasks.first)
        #expect(await model.move(row, to: try #require(model.columns.first { $0.destination == .status(.inProgress) })))
        #expect(try Data(contentsOf: context.file) == Data(source.replacingOccurrences(of: "[ ]", with: "[/]").utf8))
        #expect(context.store.content.tasks.first?.rawStatus == "/")
    }

    @Test func projectMoveChangesAndRemovesOnlyTargetTag() async throws {
        let context = try TaskTestContext()
        defer { context.clean() }
        await context.start()
        let source = "## Tasks\n- [ ] Plan 📅 2026-10-06 #project/Alpha ^task\n- [ ] Other #project/Beta ^other\n"
        try source.write(to: context.file, atomically: true, encoding: .utf8)
        await context.store.refresh()
        let model = board(context)
        model.grouping = .project
        let row = try #require(context.store.content.tasks.first { $0.sourceIdentifier == "task" })
        let beta = try #require(model.columns.first { $0.name == "Beta" })
        #expect(await model.move(row, to: beta))
        let moved = source.replacingOccurrences(of: "#project/Alpha", with: "#project/Beta")
        #expect(try Data(contentsOf: context.file) == Data(moved.utf8))
        let changed = try #require(context.store.content.tasks.first { $0.sourceIdentifier == "task" })
        #expect(await model.move(changed, to: try #require(model.columns.last)))
        #expect(
            try Data(contentsOf: context.file)
                == Data(moved.replacingOccurrences(of: " #project/Beta ^task", with: " ^task").utf8))
        #expect(context.store.content.tasks.first { $0.sourceIdentifier == "task" }?.project == nil)
    }

    @Test func doneDropCompletesRecurrenceAndReopeningDoesNotGenerateAnotherRow() async throws {
        let context = try TaskTestContext()
        defer { context.clean() }
        await context.start()
        let source = "## Tasks\n- [/] Plan 📅 2026-10-03 🔁 every week ^original\n"
        try source.write(to: context.file, atomically: true, encoding: .utf8)
        await context.store.refresh()
        let model = board(context)
        let row = try #require(context.store.content.tasks.first)
        let done = try #require(model.columns.first { $0.destination == .status(.done) })
        let token = model.beginDrag(row)
        #expect(model.acceptsDrop(token, into: done))
        #expect(await model.drop(token, into: done))
        let document = try context.document()
        #expect(document.bodyLines.tasks.count == 2)
        let next = try #require(document.bodyLines.tasks.first)
        #expect(next.status == .todo && next.doneDate == nil && next.dueDate == context.today.addingDays(7))
        #expect(next.block.id != "original" && next.block.id != nil)
        #expect(document.bodyLines.tasks.last?.block.id == "original")
        #expect(document.bodyLines.tasks.last?.doneDate == context.today)
        let completed = try #require(context.store.content.tasks.first { $0.sourceIdentifier == "original" })
        #expect(await model.move(completed, to: try #require(model.columns.first)))
        #expect(try context.document().bodyLines.tasks.count == 2)
        #expect(context.store.content.tasks.first { $0.sourceIdentifier == "original" }?.done == nil)
    }

    @Test func staleDragReportsErrorRefreshesAndLeavesEditedDiskUntouched() async throws {
        let context = try TaskTestContext()
        defer { context.clean() }
        await context.start()
        try "## Tasks\n- [ ] Plan ^task\n".write(to: context.file, atomically: true, encoding: .utf8)
        await context.store.refresh()
        let model = board(context)
        let token = model.beginDrag(try #require(context.store.content.tasks.first))
        let target = try #require(model.columns.first { $0.destination == .status(.inProgress) })
        let external = "## Tasks\n- [ ] Plan ⏫ ^task\n"
        try external.write(to: context.file, atomically: true, encoding: .utf8)
        #expect(await !model.drop(token, into: target))
        #expect(model.errorText != nil && model.busy.isEmpty)
        #expect(context.store.content.tasks.first?.priority == .high)
        #expect(try Data(contentsOf: context.file) == Data(external.utf8))
        #expect(await !model.drop(token, into: target))
        #expect(!model.acceptsDrop("untrusted text", into: target))
    }

    @Test func personGroupingRejectsMovesAndSameColumnIsNoOp() async throws {
        let context = try TaskTestContext()
        defer { context.clean() }
        await context.start()
        let source = "## Tasks\n- [?] Plan #project/demo ^task\n"
        try source.write(to: context.file, atomically: true, encoding: .utf8)
        await context.store.refresh()
        let model = board(context)
        let row = try #require(context.store.content.tasks.first)
        #expect(await !model.move(row, to: try #require(model.columns.first)))
        model.grouping = .person
        #expect(await !model.move(row, to: try #require(model.columns.first)))
        let token = model.beginDrag(row)
        #expect(!model.acceptsDrop(token, into: try #require(model.columns.first)))
        #expect(try Data(contentsOf: context.file) == Data(source.utf8))
    }

    private func board(_ context: TaskTestContext) -> KanbanModel {
        KanbanModel(tasks: TasksModel(store: context.store, today: { context.today }))
    }
}
