import Foundation
import Testing
import VaultFormat

@testable import Journal

/// The project names left the read model for a query (`IndexStore.computeProjects()`). A board or
/// timeline takes the names with its rows, so a project column never shows before its tasks; the
/// Mac sidebar keeps its project rows while a reload is on its way.
@MainActor struct ProjectQueryLoadingTests {
    @Test func boardProjectColumnsArriveWithTheirRows() async throws {
        let context = try TaskTestContext(sample: true)
        defer { context.clean() }
        await context.start()
        let store = context.store
        let board = KanbanModel(tasks: TasksModel(store: store, today: { context.today }))
        board.grouping = .project
        await board.load()
        let before = board.columns.map(\.id)
        #expect(!before.isEmpty && !before.contains("project:zeplin"))

        #expect(await store.addTask(on: context.today, text: "yeni iş #project/Zeplin", due: nil))
        let gate = StepGate(store: store)
        let loading = Task { await board.load() }
        await gate.waitUntilHolding(1)
        gate.releaseFirst()
        await gate.waitUntilHolding(1)
        #expect(board.columns.map(\.id) == before, "the names wait for the rows")
        gate.release()
        await loading.value
        let zeplin = try #require(board.columns.first { $0.id == "project:zeplin" })
        #expect(zeplin.rows.count == 1)
    }

    @Test func timelineProjectGroupsArriveWithTheirRows() async throws {
        let context = try TaskTestContext(sample: true)
        defer { context.clean() }
        await context.start()
        let store = context.store
        let timeline = TimelineModel(tasks: TasksModel(store: store, today: { context.today }))
        timeline.grouping = .project
        await timeline.load()
        let before = timeline.groups.map(\.id)
        #expect(!before.contains("project:zeplin"))
        #expect(timeline.tasks.projects == (try await store.computeProjects()))

        #expect(await store.addTask(on: context.today, text: "yeni iş #project/Zeplin", due: context.today))
        let gate = StepGate(store: store)
        let loading = Task { await timeline.load() }
        await gate.waitUntilHolding(1)
        gate.releaseFirst()
        await gate.waitUntilHolding(1)
        #expect(!timeline.tasks.projects.contains("Zeplin"), "the names wait for the rows")
        gate.release()
        await loading.value
        #expect(timeline.groups.first { $0.id == "project:zeplin" }?.rows.count == 1)
    }
}

#if os(macOS)
    import AppKit

    /// The real shell with the sample vault: a project removed from the vault stays in the sidebar
    /// until the project query answers, then goes.
    @MainActor @Suite(.serialized, .timeLimit(.minutes(1)))
    struct MacSidebarProjectLoadingTests {
        private let watchdog = HostedTestWatchdog()

        @Test func sidebarKeepsItsProjectsWhileTheQueryIsOnItsWay() async throws {
            let shell = try await MacShellWiringTests.Shell()
            defer { shell.close() }
            let table = try #require(shell.sidebarTable)
            await shell.mount.settle(rounds: 8)
            let rows = table.numberOfRows
            #expect(rows > 5, "the sample's projects are listed")

            let gate = TaskQueryGate(store: shell.context.store)
            gate.hold()
            let file = shell.context.root.appendingPathComponent("journal/2026-09-15.md")
            let text = try String(contentsOf: file, encoding: .utf8)
            #expect(text.contains("#project/altyapi"))
            try text.replacingOccurrences(of: " #project/altyapi", with: "")
                .write(to: file, atomically: true, encoding: .utf8)
            await shell.context.store.refresh()
            for _ in 0..<40 where gate.heldCount == 0 { await shell.mount.settle(rounds: 1) }
            #expect(gate.heldCount > 0, "the publish asks for the names again")
            await shell.mount.settle(rounds: 8)
            #expect(table.numberOfRows == rows, "the sidebar keeps its rows")

            gate.release()
            for _ in 0..<40 where table.numberOfRows == rows { await shell.mount.settle(rounds: 1) }
            #expect(table.numberOfRows == rows - 1)
        }
    }

    /// The quick entry bar reads the project names its `#project/` suggestions offer when it is
    /// mounted and again after every publish.
    @MainActor @Suite(.timeLimit(.minutes(1)))
    struct QuickEntryProjectLoadingTests {
        private let watchdog = HostedTestWatchdog()

        @Test func barLoadsTheProjectNamesAndReloadsThemAfterAWrite() async throws {
            let context = try TaskTestContext(sample: true)
            defer { context.clean() }
            await context.start()
            let store = context.store
            let model = context.model()
            let defaults = context.defaults.defaults
            let bar = QuickEntryBar(store: store, isEnabled: true, model: model)
                .environment(LocationService(source: FakeLocationSource(), defaults: defaults))
                .environment(IntentNavigation())
            let mount = HostedLayout.Mount(bar, size: CGSize(width: 600, height: 200))
            defer { mount.close() }
            let names = try await store.computeProjects()
            #expect(!names.isEmpty)
            for _ in 0..<40 where model.knownProjects != names { await mount.settle(rounds: 1) }
            #expect(model.knownProjects == names)

            #expect(await store.addTask(on: context.today, text: "yeni iş #project/Zeplin", due: nil))
            for _ in 0..<40 where !model.knownProjects.contains("Zeplin") { await mount.settle(rounds: 1) }
            #expect(model.knownProjects.contains("Zeplin"))
            model.mode = .task
            model.text = "Plan #project/zep"
            #expect(model.projectSuggestions() == ["Zeplin"])
        }
    }
#endif

/// Holds the store's task queries after they return and lets them through one at a time, so a
/// test can look at a model between two answers of one load.
@MainActor private final class StepGate {
    private var held: [CheckedContinuation<Void, Never>] = []
    private var watchers: [(count: Int, continuation: CheckedContinuation<Void, Never>)] = []
    private var isHolding = true

    init(store: IndexStore) {
        store.testingTaskQueryDidFinish = { [weak self] in await self?.pass() }
    }

    func waitUntilHolding(_ count: Int) async {
        guard held.count < count else { return }
        await withCheckedContinuation { watchers.append((count, $0)) }
    }

    func releaseFirst() { held.removeFirst().resume() }

    func release() {
        isHolding = false
        let waiting = held
        held = []
        for continuation in waiting { continuation.resume() }
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
