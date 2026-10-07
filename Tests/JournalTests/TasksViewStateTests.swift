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

    /// The boards own their models; the views seed them from, and report back to, the shared state.
    @Test func boardsStartFromAndReportTheirMenuChoice() throws {
        let source = try String(
            contentsOf: URL(fileURLWithPath: #filePath).deletingLastPathComponent()
                .deletingLastPathComponent().deletingLastPathComponent()
                .appendingPathComponent("App/Screens/Tasks/Kanban/KanbanView.swift"), encoding: .utf8)
        #expect(source.contains("model.grouping = tasks.viewState.kanbanGrouping"))
        #expect(source.contains("model.tasks.viewState.kanbanGrouping = grouping"))
        let timeline = try String(
            contentsOf: URL(fileURLWithPath: #filePath).deletingLastPathComponent()
                .deletingLastPathComponent().deletingLastPathComponent()
                .appendingPathComponent("App/Screens/Tasks/Timeline/TaskTimelineView.swift"),
            encoding: .utf8)
        #expect(timeline.contains("model.scale = tasks.viewState.timelineScale"))
        #expect(timeline.contains("model.tasks.viewState.timelineScale = scale"))
    }
}
