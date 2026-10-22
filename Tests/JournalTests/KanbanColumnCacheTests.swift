import Foundation
import Observation
import Testing
import VaultFormat

@testable import Journal

/// The board builds its columns once per set of inputs: the board, every card's move menu and
/// every card's VoiceOver actions read the same columns instead of filtering and sorting the rows
/// again (one card per row made that quadratic).
@MainActor struct KanbanColumnCacheTests {
    private static let source = """
        ## Tasks
        - [ ] Plan #project/Alpha ^plan
        - [/] Draft #project/Beta ^draft
        - [x] Shipped ✅ 2026-10-01 ^shipped
        - [-] Dropped ^dropped
        """

    @Test func repeatedReadsBuildTheColumnsOnce() async throws {
        let context = try TaskTestContext()
        defer { context.clean() }
        let model = try await Self.board(context)
        #expect(model.columnBuilds == 0, "loading does not build the columns")
        let first = model.columns
        #expect(model.columnBuilds == 1)
        // The board, then every card: menu targets and VoiceOver actions for each row.
        let second = model.columns
        for row in first.flatMap(\.rows) {
            _ = model.moveTargets.filter { model.canMove(row, to: $0) }
        }
        #expect(model.columnBuilds == 1)
        #expect(second.map(\.id) == first.map(\.id))
        #expect(second.map { $0.rows.map(\.id) } == first.map { $0.rows.map(\.id) })
        #expect(model.moveTargets == first.map(\.target))
    }

    @Test func groupingChangeBuildsTheNewColumns() async throws {
        let context = try TaskTestContext()
        defer { context.clean() }
        let model = try await Self.board(context)
        #expect(model.columns.map(\.id) == ["status:todo", "status:inProgress", "status:done"])
        model.grouping = .project
        #expect(model.columns.map(\.id) == ["project:alpha", "project:beta", "project:"])
        #expect(model.moveTargets.map(\.id) == ["project:alpha", "project:beta", "project:"])
        #expect(model.columns.map { $0.rows.compactMap(\.sourceIdentifier) } == [["plan"], ["draft"], ["shipped"]])
        #expect(model.columnBuilds == 2)
        model.grouping = .status
        #expect(model.columns.map(\.id) == ["status:todo", "status:inProgress", "status:done"])
        #expect(model.columnBuilds == 3)
        // No people and no project names here: only the grouping tells these boards apart.
        model.grouping = .person
        #expect(model.columns.map(\.id) == ["person:"])
        model.tasks.projects = []
        model.grouping = .project
        #expect(model.columns.map(\.id) == ["project:"])
        #expect(model.columnBuilds == 5)
    }

    @Test func showCancelledBuildsTheCancelledColumn() async throws {
        let context = try TaskTestContext()
        defer { context.clean() }
        let model = try await Self.board(context)
        #expect(!model.columns.flatMap(\.rows).contains { $0.sourceIdentifier == "dropped" })
        model.showsCancelled = true
        #expect(model.columns.last?.destination == .status(.cancelled))
        #expect(model.columns.last?.rows.compactMap(\.sourceIdentifier) == ["dropped"])
        #expect(model.moveTargets.last?.destination == .status(.cancelled))
        model.showsCancelled = false
        #expect(model.columns.map(\.destination) == [.status(.todo), .status(.inProgress), .status(.done)])
        #expect(model.columnBuilds == 3)
    }

    /// A reload assigns new rows: the next read builds from them, even with the same grouping.
    @Test func newRowsBuildTheColumnsAgain() async throws {
        let context = try TaskTestContext()
        defer { context.clean() }
        let model = try await Self.board(context)
        #expect(model.columns.first?.rows.compactMap(\.sourceIdentifier) == ["plan"])
        try (Self.source + "\n- [ ] Added ^added\n").write(to: context.file, atomically: true, encoding: .utf8)
        await context.store.refresh()
        await model.load()
        #expect(model.columns.first?.rows.compactMap(\.sourceIdentifier) == ["added", "plan"])
        #expect(model.columnBuilds == 2)
    }

    /// A new day moves the thirty-day window of the done column.
    @Test func newDayBuildsTheColumnsAgain() async throws {
        let context = try TaskTestContext()
        defer { context.clean() }
        await context.start()
        try Self.source.write(to: context.file, atomically: true, encoding: .utf8)
        await context.store.refresh()
        let clock = BoardClock(day: context.today)
        let model = KanbanModel(tasks: TasksModel(store: context.store, today: { clock.day }))
        await model.load()
        #expect(model.columns.last?.rows.compactMap(\.sourceIdentifier) == ["shipped"])
        clock.day = try #require(context.today.addingDays(40))
        #expect(model.columns.last?.rows.isEmpty == true)
    }

    /// New project names (set with the rows) build the project columns again.
    @Test func newProjectNamesBuildTheColumnsAgain() async throws {
        let context = try TaskTestContext()
        defer { context.clean() }
        let model = try await Self.board(context)
        model.grouping = .project
        #expect(model.columns.count == 3)
        model.tasks.projects = ["Alpha"]
        #expect(model.columns.map(\.id) == ["project:alpha", "project:"])
    }

    /// A read the cache answers still reads every input, so the board is told when one changes.
    @Test func cachedReadIsObservedWithItsInputs() async throws {
        let context = try TaskTestContext()
        defer { context.clean() }
        let model = try await Self.board(context)
        _ = model.columns
        // Rows first: in the status grouping nothing else the reload sets is read.
        for change in [BoardChange.rows, .grouping, .showsCancelled] {
            let builds = model.columnBuilds
            let changed = BoardChangeFlag()
            withObservationTracking {
                _ = model.columns
            } onChange: {
                changed.set()
            }
            #expect(model.columnBuilds == builds, "the tracked read was the cached one")
            switch change {
            case .grouping: model.grouping = model.grouping == .status ? .project : .status
            case .showsCancelled: model.showsCancelled.toggle()
            case .rows: await model.load()
            }
            #expect(changed.isSet, "\(change)")
            _ = model.columns
        }
    }

    /// In the project grouping a cached read is observed with the project names too.
    @Test func cachedProjectReadIsObservedWithTheProjectNames() async throws {
        let context = try TaskTestContext()
        defer { context.clean() }
        let model = try await Self.board(context)
        model.grouping = .project
        _ = model.columns
        let builds = model.columnBuilds
        let changed = BoardChangeFlag()
        withObservationTracking {
            _ = model.columns
        } onChange: {
            changed.set()
        }
        #expect(model.columnBuilds == builds, "the tracked read was the cached one")
        model.tasks.projects = ["Alpha"]
        #expect(changed.isSet)
        #expect(model.columns.map(\.id) == ["project:alpha", "project:"])
    }

    /// In the person grouping a new people list (a person file edited, the board's rows not
    /// reloaded yet) builds the columns again, and a cached read is observed with it.
    @Test func newPeopleBuildThePersonColumnsAgain() async throws {
        let context = try TaskTestContext(sample: true)
        defer { context.clean() }
        await context.start()
        try """
        ## Tasks
        - [ ] [[Deniz Arıkan]] Shared #project/board ^shared
        - [ ] Free #project/board ^free
        """.write(to: context.file, atomically: true, encoding: .utf8)
        await context.store.refresh()
        let model = KanbanModel(tasks: TasksModel(store: context.store, today: { context.today }))
        model.tasks.projectFilter = "board"
        await model.load()
        model.grouping = .person
        let person = "people/Deniz Arıkan.md"
        #expect(model.columns.map(\.id) == ["person:" + person, "person:"])
        #expect(model.columns.first?.name == "Deniz Arıkan")
        let builds = model.columnBuilds
        let changed = BoardChangeFlag()
        withObservationTracking {
            _ = model.columns
        } onChange: {
            changed.set()
        }
        #expect(model.columnBuilds == builds, "the tracked read was the cached one")
        let file = context.root.appendingPathComponent(person)
        let source = try String(contentsOf: file, encoding: .utf8)
        try source.replacingOccurrences(of: "name: Deniz Arıkan\n", with: "name: Deniz Arıkan\nqualifier: okul\n")
            .write(to: file, atomically: true, encoding: .utf8)
        await context.store.refresh()
        #expect(changed.isSet)
        #expect(model.columns.first?.name == "Deniz Arıkan (okul)")
        #expect(model.moveTargets.first?.name == "Deniz Arıkan (okul)")
        #expect(model.columns.first?.rows.compactMap(\.sourceIdentifier) == ["shared"])
        #expect(model.columnBuilds == builds + 1)
    }

    /// A card's move goes through the cached targets; a target the board no longer has is refused.
    @Test func moveTargetsMoveAndStaleTargetsAreRefused() async throws {
        let context = try TaskTestContext()
        defer { context.clean() }
        let model = try await Self.board(context)
        let plan = try #require(try await context.store.allTasks().first { $0.sourceIdentifier == "plan" })
        let stale = KanbanMoveTarget(id: "project:gone", destination: .project("Gone"), name: "Gone")
        model.grouping = .project
        #expect(await !model.move(plan, to: stale))
        let beta = try #require(model.moveTargets.first { $0.name == "Beta" })
        #expect(model.canMove(plan, to: beta))
        #expect(await model.move(plan, to: beta))
        #expect(try await context.store.allTasks().first { $0.sourceIdentifier == "plan" }?.project == "Beta")
    }

    /// The board as the view loads it, over ``source``.
    private static func board(_ context: TaskTestContext) async throws -> KanbanModel {
        await context.start()
        try source.write(to: context.file, atomically: true, encoding: .utf8)
        await context.store.refresh()
        let model = KanbanModel(tasks: TasksModel(store: context.store, today: { context.today }))
        await model.load()
        return model
    }
}

private enum BoardChange { case grouping, showsCancelled, rows }

private final class BoardClock {
    var day: CalendarDate
    init(day: CalendarDate) { self.day = day }
}

private final class BoardChangeFlag: @unchecked Sendable {
    private let lock = NSLock()
    private var value = false
    var isSet: Bool { lock.withLock { value } }
    func set() { lock.withLock { value = true } }
}
