import Foundation
import Testing

@testable import Journal

/// Two-layer Tasks view selector: tab + per-tab menu, and the migration of the old single
/// stored value.
@MainActor
struct TasksViewStateTests {
    @Test func defaultsAreListAndUpcoming() {
        let state = TasksViewState()
        #expect(state.mode == .list)
        #expect(state.listSection == .upcoming)
        #expect(state.kanbanGrouping == .status)
        #expect(state.timelineScale == .quarter)
        #expect(state.legacySection == .upcoming)
    }

    @Test func legacyKanbanBecomesKanbanTab() throws {
        let defaults = try TestDefaults()
        defer { defaults.clean() }
        defaults.defaults.set("kanban", forKey: TasksViewState.StorageKey.legacySection)
        let state = TasksViewState.restore(from: defaults.defaults)
        #expect(state.mode == .kanban)
        #expect(state.listSection == .upcoming)
    }

    @Test func legacyUndatedBecomesListTabWithUndatedSection() throws {
        let defaults = try TestDefaults()
        defer { defaults.clean() }
        defaults.defaults.set("undated", forKey: TasksViewState.StorageKey.legacySection)
        let state = TasksViewState.restore(from: defaults.defaults)
        #expect(state.mode == .list)
        #expect(state.listSection == .undated)
    }

    @Test(arguments: TasksModel.Section.allCases)
    func everyLegacyValueRoundTrips(_ section: TasksModel.Section) throws {
        let defaults = try TestDefaults()
        defer { defaults.clean() }
        defaults.defaults.set(section.rawValue, forKey: TasksModel.Section.storageKey)
        #expect(TasksViewState.restore(from: defaults.defaults).legacySection == section)
    }

    @Test func migrationWritesNewKeysAndRemovesTheLegacyKey() throws {
        let defaults = try TestDefaults()
        defer { defaults.clean() }
        defaults.defaults.set("timeline", forKey: TasksViewState.StorageKey.legacySection)
        _ = TasksViewState.restore(from: defaults.defaults)
        #expect(defaults.defaults.object(forKey: TasksViewState.StorageKey.legacySection) == nil)
        #expect(defaults.defaults.string(forKey: TasksViewState.StorageKey.mode) == "timeline")
        // A second launch reads the migrated value, not the default.
        #expect(TasksViewState.restore(from: defaults.defaults).mode == .timeline)
    }

    @Test func savedStateRestoresEveryTabsMenuChoice() throws {
        let defaults = try TestDefaults()
        defer { defaults.clean() }
        var state = TasksViewState()
        state.mode = .timeline
        state.listSection = .projects
        state.kanbanGrouping = .person
        state.timelineScale = .week
        state.save(to: defaults.defaults)
        #expect(TasksViewState.restore(from: defaults.defaults) == state)
    }

    @Test func legacyValueKeepsTheOtherTabsChoices() throws {
        let defaults = try TestDefaults()
        defer { defaults.clean() }
        var state = TasksViewState()
        state.mode = .kanban
        state.listSection = .completed
        state.kanbanGrouping = .project
        state.save(to: defaults.defaults)
        defaults.defaults.set("timeline", forKey: TasksViewState.StorageKey.legacySection)
        let restored = TasksViewState.restore(from: defaults.defaults)
        #expect(restored.mode == .timeline)
        #expect(restored.listSection == .completed)
        #expect(restored.kanbanGrouping == .project)
    }

    @Test func unknownValuesFallBackAndTheLegacyKeyIsDropped() throws {
        let defaults = try TestDefaults()
        defer { defaults.clean() }
        defaults.defaults.set("board", forKey: TasksViewState.StorageKey.mode)
        defaults.defaults.set("someday", forKey: TasksViewState.StorageKey.listSection)
        defaults.defaults.set("gone", forKey: TasksViewState.StorageKey.legacySection)
        #expect(TasksViewState.restore(from: defaults.defaults) == TasksViewState())
        #expect(defaults.defaults.object(forKey: TasksViewState.StorageKey.legacySection) == nil)
    }

    @Test func modelSectionMapsOntoTabAndListSection() throws {
        let context = try TaskTestContext()
        defer { context.clean() }
        let model = TasksModel(store: context.store)
        model.section = .completed
        #expect(model.viewState.mode == .list)
        #expect(model.viewState.listSection == .completed)
        model.section = .kanban
        #expect(model.viewState.mode == .kanban)
        #expect(model.viewState.listSection == .completed, "a board keeps the list's last section")
        #expect(model.section == .kanban)
        model.section = .upcoming
        #expect(model.viewState.mode == .list)
        #expect(model.viewState.listSection == .upcoming)
    }

    /// The boards own their models: each starts from the shared state's last menu choice and
    /// reports a new choice back, so a rebuilt board (tab switch) keeps it.
    @Test func boardsStartFromAndReportTheirMenuChoice() throws {
        let context = try TaskTestContext()
        defer { context.clean() }
        let tasks = TasksModel(store: context.store)
        #expect(KanbanModel.board(for: tasks).grouping == .status)
        #expect(TimelineModel.board(for: tasks).scale == .quarter)

        let kanban = KanbanModel.board(for: tasks)
        kanban.choose(.person)
        #expect(kanban.grouping == .person)
        #expect(tasks.viewState.kanbanGrouping == .person)
        let timeline = TimelineModel.board(for: tasks)
        timeline.choose(.week)
        #expect(timeline.scale == .week)
        #expect(tasks.viewState.timelineScale == .week)

        // Leaving the tab and coming back builds new boards.
        tasks.viewState.selectTab(.list)
        tasks.viewState.selectTab(.kanban)
        #expect(KanbanModel.board(for: tasks).grouping == .person)
        #expect(TimelineModel.board(for: tasks).scale == .week)
        #expect(tasks.viewState.mode == .kanban)
    }
}

/// Mac shell: which Tasks layout each sidebar / tab / vault event ends in.
@MainActor
struct TasksShellStateTests {
    typealias Event = TasksShellState.Event

    private func state(after events: [Event], from start: TasksShellState = TasksShellState()) -> TasksShellState {
        events.reduce(into: start) { $0.handle($1) }
    }

    @Test func startsOnTheList() {
        #expect(TasksShellState().layout == .list)
    }

    @Test func sidebarEntriesOpenTheirOwnLayout() {
        #expect(state(after: [.sidebarBoard(.kanban)]).layout == .kanban)
        #expect(state(after: [.sidebarBoard(.timeline)]).layout == .timeline)
        #expect(state(after: [.sidebarProject("Atlas")]).layout == .project("Atlas"))
        #expect(state(after: [.sidebarBoard(.kanban), .sidebarTasks]).layout == .list)
        #expect(state(after: [.sidebarProject("Atlas"), .sidebarTasks]).layout == .list)
    }

    /// Sidebar Kanban → Günlük → back to Görevler (arrow key: no sidebar click) is the list.
    @Test(arguments: [TasksViewState.Mode.kanban, .timeline])
    func aBoardIsNotStickyAcrossSections(_ board: TasksViewState.Mode) {
        // Returning with the arrow keys sends no event of its own: leaving already reset it.
        #expect(state(after: [.sidebarBoard(board), .sectionLeft]).layout == .list)
        #expect(state(after: [.tab(board), .sectionLeft]).layout == .list)
        #expect(state(after: [.sidebarBoard(board), .navigationReset]).layout == .list)
    }

    @Test(arguments: [TasksViewState.Mode.kanban, .timeline])
    func aVaultChangeLandsOnTheList(_ board: TasksViewState.Mode) {
        #expect(state(after: [.sidebarBoard(board), .vaultChanged]).layout == .list)
        #expect(state(after: [.tab(board), .vaultChanged]).layout == .list)
        #expect(state(after: [.sidebarProject("Atlas"), .vaultChanged]).layout == .list)
    }

    /// "Liste" tab inside a full-width board: back to the three-column list. The event does
    /// not touch the sidebar section, so "Görevler" stays highlighted.
    @Test func theListTabLeavesTheBoard() {
        #expect(state(after: [.sidebarBoard(.kanban), .tab(.list)]).layout == .list)
        #expect(state(after: [.sidebarBoard(.timeline), .tab(.list)]).layout == .list)
    }

    /// A board tab in the list column opens the full-width board, same as its sidebar entry.
    @Test func aBoardTabInTheListColumnOpensTheFullWidthBoard() {
        #expect(state(after: [.tab(.kanban)]).layout == .kanban)
        #expect(state(after: [.tab(.timeline)]).layout == .timeline)
        #expect(state(after: [.tab(.kanban)]) == state(after: [.sidebarBoard(.kanban)]))
        #expect(state(after: [.sidebarBoard(.kanban), .tab(.timeline)]).layout == .timeline)
    }

    /// The tab is the single source: repeating an event changes nothing, and the layout is a
    /// function of the state, so there is no second flag to bounce a change back.
    @Test func eventsAreIdempotent() {
        let events: [Event] = [
            .sidebarTasks, .sidebarBoard(.kanban), .sidebarBoard(.timeline), .sidebarProject("Atlas"),
            .tab(.list), .tab(.kanban), .tab(.timeline), .sectionLeft, .navigationReset, .vaultChanged,
        ]
        for first in events {
            for event in events {
                let once = state(after: [first, event])
                #expect(state(after: [event], from: once) == once, "\(first) then \(event) twice")
            }
        }
    }

    @Test func boardsAndProjectsExcludeEachOther() {
        let project = state(after: [.sidebarBoard(.kanban), .sidebarProject("Atlas")])
        #expect(project.layout == .project("Atlas"))
        #expect(project.view.mode == .list)
        let board = state(after: [.sidebarProject("Atlas"), .sidebarBoard(.timeline)])
        #expect(board.layout == .timeline)
        #expect(board.project == nil)
    }

    /// Only "Görevler" itself goes back to the first list section; the other ways of landing
    /// on the list keep the section, and the boards keep their menu choices throughout.
    @Test func menuChoicesSurviveTheShellEvents() {
        var start = TasksShellState()
        start.view.listSection = .completed
        start.view.kanbanGrouping = .person
        start.view.timelineScale = .week
        let left = state(after: [.sidebarBoard(.kanban), .sectionLeft], from: start)
        #expect(left.view.listSection == .completed)
        #expect(left.view.kanbanGrouping == .person)
        #expect(left.view.timelineScale == .week)
        let clicked = state(after: [.sidebarBoard(.kanban), .sidebarTasks], from: start)
        #expect(clicked.view.listSection == .upcoming)
        #expect(clicked.view.kanbanGrouping == .person)
    }

    /// The tabs write through the same function the shell's `.tab` event uses.
    @Test func theTabsAndTheShellShareOneWritePath() throws {
        let context = try TaskTestContext()
        defer { context.clean() }
        let model = TasksModel(store: context.store)
        model.viewState.selectTab(.kanban)
        var shell = TasksShellState()
        shell.handle(.tab(.kanban))
        #expect(shell.view == model.viewState)
        #expect(TasksShellState(view: model.viewState, project: nil).layout == .kanban)
    }
}
