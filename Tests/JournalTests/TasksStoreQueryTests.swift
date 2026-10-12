import Foundation
import Testing
import VaultFormat
import VaultIndex
import VaultStore

@testable import Journal

/// The task screens' queries through `IndexStore` and the screen models, held to the construction
/// they replaced (``LegacyTaskViews`` over the old `tasks` rows of a fresh rebuild) and to a
/// fresh rebuild of the vault, on the sample vault, a hand-written edge-case vault and after edits.
/// The project names and an entity page's open tasks are held to their old constructions too.
@MainActor struct TasksStoreQueryTests {
    @Test func sampleVaultScreensMatchTheReadModelConstruction() async throws {
        let context = try TaskTestContext(sample: true)
        defer { context.clean() }
        await context.start()
        try await expectScreens(
            context, days: ["2026-09-14", "2026-09-20", "2026-09-27", "2026-10-03"],
            projects: ["mobil", "TEDARİK", "yok"])
    }

    @Test func edgeCaseVaultScreensMatchTheReadModelConstruction() async throws {
        let context = try TaskTestContext(sample: true)
        defer { context.clean() }
        await context.start()
        try Self.writeEdgeCases(context)
        await context.store.refresh()
        try await expectScreens(
            context, days: ["2026-09-20", "2026-10-02", "2026-10-03", "2026-10-04"], projects: ["CAFÉ", "Cafe\u{301}"])

        // By hand: the list on the sample's last day plus the edge file.
        let model = TasksModel(store: context.store, today: { context.today })
        model.projectFilter = "café"
        await model.loadList()
        #expect(model.agenda.map(\.id) == ["overdue", "2026-10-03", "2026-10-09"])
        #expect(model.agenda.flatMap(\.rows).compactMap(\.sourceIdentifier) == ["past", "note", "today", "later"])
        #expect(model.openCount(ofProject: "CAFE\u{301}") == 4)
        model.projectFilter = nil
        await model.loadList()
        #expect(model.undated.compactMap(\.sourceIdentifier).contains("crlf"))
        let today = try await CloseDayModel.opened(store: context.store, today: context.today)
        let ids = today.tasks.compactMap(\.sourceIdentifier)
        #expect(ids.contains("past") && ids.contains("note"))
        #expect(Array(ids.suffix(4)) == ["today", "weekly", "undated", "running"])
    }

    /// After each edit the screens answer like the published construction and like a fresh rebuild.
    @Test func editsKeepTheScreensEqualToTheConstructionAndARebuild() async throws {
        let context = try TaskTestContext(sample: true)
        defer { context.clean() }
        await context.start()
        try Self.writeEdgeCases(context)
        await context.store.refresh()
        let days = ["2026-10-02", "2026-10-03"]
        let projects = ["café"]
        let tasks = TasksModel(store: context.store, today: { context.today })
        await tasks.loadList()

        // Completion from the list.
        let past = try #require(tasks.agenda.first?.rows.first { $0.sourceIdentifier == "past" })
        #expect(await tasks.toggle(past))
        try await expectScreens(context, days: days, projects: projects)
        try await expectRebuild(context, days: days)
        // Move to tomorrow.
        let moving = try #require(try await context.store.allTasks().first { $0.sourceIdentifier == "today" })
        let move = await TaskMove.apply([moving], to: CalendarDate("2026-10-04")!, in: context.store)
        #expect(move.moved == 1)
        try await expectScreens(context, days: days, projects: projects)
        try await expectRebuild(context, days: days)
        // Addition.
        #expect(
            await context.store.addTask(
                on: context.today, text: "added [[Ece Yalın]] #project/Café", due: context.today))
        try await expectScreens(context, days: days, projects: projects)
        try await expectRebuild(context, days: days)
        // Reopening.
        let done = try #require(try await context.store.computeCompletedTasks(limit: 1).first)
        #expect(await tasks.toggle(done))
        try await expectScreens(context, days: days, projects: projects)
        // A file deleted outside the app.
        try FileManager.default.removeItem(at: context.root.appendingPathComponent("notes/Edge.md"))
        await context.store.refresh()
        try await expectScreens(context, days: days, projects: projects)
        try await expectRebuild(context, days: days)
        await tasks.loadList()
        #expect(tasks.agenda.flatMap(\.rows).allSatisfy { $0.file != "notes/Edge.md" })
    }

    /// A screen's request replaced while its query runs (`.task(id:)` cancels it) gets no answer.
    @Test func aCancelledRequestGetsNoAnswer() async throws {
        let context = try TaskTestContext(sample: true)
        defer { context.clean() }
        await context.start()
        let store = context.store
        let gate = TaskQueryGate(store: store)
        gate.hold()
        let day = CalendarDate("2026-09-20")!
        let groups = Task { try await store.computeTaskGroups(today: day) }
        let rows = Task { try await store.computeDayTasks(on: day) }
        await gate.waitUntilHolding(2)
        groups.cancel()
        rows.cancel()
        let newer = Task { try await store.computeTaskGroups(today: day) }
        await gate.waitUntilHolding(3)
        gate.release()
        await #expect(throws: CancellationError.self) { try await groups.value }
        await #expect(throws: CancellationError.self) { try await rows.value }
        #expect(try await newer.value.open.count == Self.legacyTasks(context).filter { !$0.isClosed }.count)
    }

    @Test func aQueryThatOutlivesItsVaultIsNotAppliedToTheNext() async throws {
        let context = try TaskTestContext(sample: true)
        defer { context.clean() }
        await context.start()
        let store = context.store
        let other = context.directory.appendingPathComponent("Other")
        try FileManager.default.createDirectory(at: other, withIntermediateDirectories: true)
        let day = CalendarDate("2026-09-20")!
        func switchVaultWhenTheQueryReturns() {
            store.testingTaskQueryDidFinish = {
                store.testingTaskQueryDidFinish = nil
                await store.select(other)
            }
        }
        let queries: [(String, () async throws -> Int)] = [
            ("groups", { try await store.computeTaskGroups(today: day).open.count }),
            ("completed", { try await store.computeCompletedTasks(limit: 50).count }),
            ("day", { try await store.computeDayTasks(on: day).count }),
            ("board", { try await store.computeBoardTasks(doneFrom: day, to: day, includeCancelled: true).count }),
            ("timeline", { try await store.computeTimelineTasks(from: day, to: day, today: day).count }),
            ("project", { try await store.computeProjectTasks("mobil").count }),
            ("week", { try await store.computeOpenTasks(dueBy: day, orWrittenFrom: day).count }),
            ("task", { try await store.computeTask(id: "journal/2026-09-14.md^g8f1cb") == nil ? 0 : 1 }),
            ("counts", { try await store.computeOpenTaskCounts().count }),
        ]
        for (name, query) in queries {
            switchVaultWhenTheQueryReturns()
            await #expect(throws: VaultStoreError.staleTarget, "\(name)") { _ = try await query() }
            #expect(store.vaultURL?.lastPathComponent == "Other")
            await store.select(context.root)
            #expect(try await query() > 0, "\(name)")
        }
    }

    /// A detail shows the selected task as the index has it now: the tapped row until the first
    /// answer, the written row after a write, nothing once the task is gone.
    @Test func selectionFollowsTheTaskAndClearsWhenItIsGone() async throws {
        let context = try TaskTestContext(sample: true)
        defer { context.clean() }
        await context.start()
        try Self.writeEdgeCases(context)
        await context.store.refresh()
        let store = context.store
        let tapped = try #require(try await store.allTasks().first { $0.sourceIdentifier == "note" })
        var answer = TaskSelectionAnswer()
        #expect(answer.row(for: tapped.id, listed: tapped)?.queryKey == tapped.queryKey)
        #expect(answer.row(for: tapped.id, listed: nil) == nil)
        #expect(answer.row(for: nil, listed: tapped) == nil)

        let tasks = TasksModel(store: store, today: { context.today })
        #expect(await tasks.toggle(tapped))
        answer = try #require(
            await TaskSelectionAnswer.load(
                TaskSelectionRequest(id: tapped.id, updated: store.lastUpdated), store: store))
        #expect(answer.row(for: tapped.id, listed: tapped)?.rawStatus == "x")
        // Another selection is not answered by this one.
        #expect(answer.row(for: "notes/Edge.md^noteundated", listed: nil) == nil)

        try FileManager.default.removeItem(at: context.root.appendingPathComponent("notes/Edge.md"))
        await store.refresh()
        answer = try #require(
            await TaskSelectionAnswer.load(
                TaskSelectionRequest(id: tapped.id, updated: store.lastUpdated), store: store))
        #expect(answer.row(for: tapped.id, listed: tapped) == nil)
    }

    // MARK: - Construction

    /// Every screen's rows for each day, filter and project equal the construction over the
    /// published rows; every task is found by its id.
    private func expectScreens(_ context: TaskTestContext, days: [String], projects: [String]) async throws {
        let store = context.store
        let all = try Self.legacyTasks(context)
        #expect(!all.isEmpty)
        #expect(try await store.allTasks().queryKeys == all.queryKeys)
        let entities = Set(all.flatMap(\.linkedFiles)).sorted()
        // The project names: the old field over the rows, scalar for scalar.
        let legacyProjects = TaskRow.legacyProjects(all)
        #expect(!legacyProjects.isEmpty)
        #expect(
            try await store.computeProjects().map { Array($0.unicodeScalars) }
                == legacyProjects.map { Array($0.unicodeScalars) })
        // An entity page's open tasks: the old filter of the rows, in the list's order.
        for entity in entities + ["people/Yok.md"] {
            let open = try await store.computeTaskGroups(today: context.today, scope: TaskScope(linkedTo: entity)).open
            let legacy = all.filter { !$0.isClosed && $0.linkedFiles.contains(entity) }.sorted(by: TasksModel.order)
            #expect(open.queryKeys == legacy.queryKeys, "\(entity)")
        }
        let names = legacyProjects + projects
        var filters: [(String?, String?)] = [(nil, nil)]
        filters += entities.map { ($0, nil) } + names.map { (nil, $0) }
        filters += entities.prefix(3).flatMap { entity in names.prefix(3).map { (entity, $0) } }
        for value in days {
            let day = try #require(CalendarDate(value))
            for (entity, project) in filters {
                let label = "\(day) \(entity ?? "-") \(project ?? "-")"
                let rows = LegacyTaskViews.filtered(all, entity: entity, project: project)
                let model = TasksModel(store: store, today: { day })
                model.entityFilter = entity
                model.projectFilter = project
                await model.loadList()
                #expect(model.agenda.queryKeys == LegacyTaskViews.agenda(rows, day: day).queryKeys, "\(label)")
                #expect(model.undated.queryKeys == LegacyTaskViews.undated(rows).queryKeys, "\(label)")
                #expect(model.completed.queryKeys == LegacyTaskViews.completed(rows).queryKeys, "\(label)")
                for name in names {
                    #expect(model.openCount(ofProject: name) == LegacyTaskViews.projectOpenCount(all, project: name))
                }

                let board = KanbanModel(tasks: model)
                for cancelled in [false, true] {
                    board.showsCancelled = cancelled
                    await board.load()
                    let expected = LegacyTaskViews.board(rows, day: day, showsCancelled: cancelled)
                    #expect(
                        board.columns.map(\.rows.queryKeys)
                            == board.columns.map { column in
                                guard case .status(let status) = column.destination else { return [] }
                                return expected.filter { KanbanModel.status(of: $0) == status }.queryKeys
                            }, "\(label)")
                }

                let timeline = TimelineModel(tasks: model)
                timeline.grouping = .none
                await timeline.load()
                for window in [timeline.visibleRange, timeline.bounds] {
                    timeline.setVisibleRange(window)
                    let dated = LegacyTaskViews.timelineDated(rows, today: day, window: timeline.visibleRange)
                    #expect(timeline.groups.flatMap(\.rows).queryKeys == dated.queryKeys, "\(label)")
                }
                #expect(timeline.undated.queryKeys == LegacyTaskViews.timelineUndated(rows).queryKeys, "\(label)")
            }

            for isToday in [true, false] {
                let tasks = await DayTasksModel.loaded(store: store, day: day, isToday: isToday)
                let legacy = TaskGroups(rows: all, on: day, isToday: isToday)
                #expect(tasks.groups.overdue.queryKeys == legacy.overdue.queryKeys)
                #expect(tasks.groups.dated.queryKeys == legacy.dated.queryKeys)
                #expect(tasks.groups.created.queryKeys == legacy.created.queryKeys)
                let closed = all.filter { $0.isClosed }
                #expect(
                    Self.presentation(day, groups: tasks.groups, closed: tasks.completedTasksForPresentation)
                        == Self.presentation(day, groups: legacy, closed: closed), "\(day) \(isToday)")
            }
            let close = try await CloseDayModel.opened(store: store, today: day)
            #expect(close.tasks.queryKeys == LegacyTaskViews.closeDay(all, today: day).queryKeys)

            let monday = try #require(day.addingDays(-13))
            let range = monday...day
            let input = try await store.weeklyReviewInput(from: monday, to: day)
            let open = try await store.computeOpenTasks(dueBy: day, orWrittenFrom: monday)
            for week in [range, (day.addingDays(-6) ?? day)...day] {
                let queried = WeeklyReviewContent.compute(
                    range: week, today: day, input: input, tasks: open, unseen: [])
                let legacy = WeeklyReviewContent.compute(range: week, today: day, input: input, tasks: all, unseen: [])
                #expect(queried == legacy, "\(week)")
            }
        }
        for name in names {
            let project = try await ProjectModel.loaded(store: store, name: name)
            let legacy = LegacyTaskViews.project(all, name: name)
            #expect(project.tasks.queryKeys == legacy.queryKeys, "\(name)")
            let old = ProjectModel(store: store, name: name, tasks: legacy)
            #expect(project.openGroups.queryKeys == old.openGroups.queryKeys)
            #expect(project.completed.queryKeys == old.completed.queryKeys)
            #expect(project.entities == old.entities && project.lastActivity == old.lastActivity)
        }
        for row in all {
            #expect(try await store.computeTask(id: row.id)?.queryKey == row.queryKey)
        }
        #expect(try await store.computeTask(id: "journal/2026-01-01.md#1") == nil)
    }

    /// The day-page groups after a fresh rebuild of the vault equal the store's answers.
    private func expectRebuild(_ context: TaskTestContext, days: [String]) async throws {
        let index = try VaultIndex()
        try index.rebuild(vaultRoot: context.root)
        let rebuilt = TaskRow.legacy(snapshot: try index.snapshot())
        #expect(rebuilt.queryKeys == (try await context.store.allTasks()).queryKeys)
        for value in days {
            let day = try #require(CalendarDate(value))
            let model = TasksModel(store: context.store, today: { day })
            await model.loadList()
            #expect(model.agenda.queryKeys == LegacyTaskViews.agenda(rebuilt, day: day).queryKeys)
            #expect(model.completed.queryKeys == LegacyTaskViews.completed(rebuilt).queryKeys)
            let tasks = await DayTasksModel.loaded(store: context.store, day: day, isToday: true)
            #expect(
                tasks.groups.overdue.queryKeys == TaskGroups(rows: rebuilt, on: day, isToday: true).overdue.queryKeys)
        }
    }

    /// What a day page draws of its tasks: open, completed and cancelled rows and the count.
    private static func presentation(_ day: CalendarDate, groups: TaskGroups, closed: [TaskRow]) -> [String] {
        let shown = TodayPresentation(
            day: DaySummary(empty: day), groups: groups, goals: [], goalStatuses: [:], goalStatusesDay: day,
            today: day, locale: Locale(identifier: "en_US"), calendar: Calendar(identifier: .gregorian),
            completedTasks: closed, isCarriedOverExpanded: true, isCompletedExpanded: true)
        return shown.taskRows.queryKeys + ["|"] + shown.completedTaskRows.queryKeys + ["|"]
            + shown.representedTaskIDs.sorted() + ["\(shown.remainingTaskCount) \(shown.completedTaskCount)"]
    }

    /// Fictional tasks around the sample's last day (`TaskTestContext.today`, 2026-10-03): every
    /// status, past, today and future days, start and due, priorities, recurrence, several people,
    /// project spellings and a CRLF file.
    /// The old `tasks` rows: every task of a fresh rebuild of the vault, by file and line.
    static func legacyTasks(_ context: TaskTestContext) throws -> [TaskRow] {
        let index = try VaultIndex()
        try index.rebuild(vaultRoot: context.root)
        return TaskRow.legacy(snapshot: try index.snapshot())
    }

    static func writeEdgeCases(_ context: TaskTestContext) throws {
        let files = [
            "journal/2026-10-03.md": """
            ## Tasks
            - [ ] undated here ^undated
            - [ ] past [[Deniz Arıkan]] 📅 2026-09-30 ⏫ #project/Café ^past
            - [ ] today [[Deniz Arıkan]] 📅 2026-10-03 🔼 #project/café ^today
            - [x] done today 📅 2026-10-03 ✅ 2026-10-03 ^donetoday
            - [ ] later [[Ece Yalın]] [[Deniz Arıkan]] 🛫 2026-10-05 📅 2026-10-09 🔽 #project/CAFÉ ^later
            - [/] running 🛫 2026-09-28 ^running
            - [-] cancelled 📅 2026-10-03 ^cancelled
            - [?] unknown 📅 2026-10-04 ^unknown
            - [ ] weekly 🔁 every week 📅 2026-10-03 ^weekly
            - [x] undated done ^undateddone
            - [ ] reversed 🛫 2026-10-08 📅 2026-10-05 ^reversed
            - [ ] no identifier 📅 2026-10-02

            """,
            "journal/2026-10-02.md":
                "## Tasks\r\n- [ ] crlf undated ^crlf\r\n- [x] crlf done ✅ 2026-10-02 ^crlfdone\r\n",
            "notes/Edge.md":
                "- [ ] note [[Ece Yalın]] 📅 2026-10-01 #project/Cafe\u{301} ^note\n- [ ] note undated ^noteundated\n",
        ]
        for (path, text) in files {
            let url = context.root.appendingPathComponent(path)
            try FileManager.default.createDirectory(
                at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            try Data(text.utf8).write(to: url)
        }
    }
}

/// Holds the store's task queries after they return, so a test can look at a screen, or cancel a
/// request, while the answer is on its way.
@MainActor final class TaskQueryGate {
    private var isHolding = false
    private var held: [CheckedContinuation<Void, Never>] = []
    private var watchers: [(count: Int, continuation: CheckedContinuation<Void, Never>)] = []

    init(store: IndexStore) {
        store.testingTaskQueryDidFinish = { [weak self] in await self?.pass() }
    }

    /// Answers waiting at the gate.
    var heldCount: Int { held.count }

    func hold() { isHolding = true }

    /// Lets every held answer through; later ones pass straight on.
    func release() {
        isHolding = false
        let waiting = held
        held = []
        for continuation in waiting { continuation.resume() }
    }

    func waitUntilHolding(_ count: Int) async {
        guard held.count < count else { return }
        await withCheckedContinuation { watchers.append((count, $0)) }
    }

    private func pass() async {
        guard isHolding else { return }
        await withCheckedContinuation { continuation in
            held.append(continuation)
            let ready = watchers.filter { $0.count <= held.count }
            watchers.removeAll { $0.count <= held.count }
            for watcher in ready { watcher.continuation.resume() }
        }
    }
}
