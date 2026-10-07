import Foundation

/// Which Tasks view is showing and the last menu choice of each view.
///
/// The selector has two layers (`docs/screens.md`, "Görevler"): a tab (list, kanban, timeline)
/// and under it one menu that depends on the tab (list section, kanban grouping, timeline
/// scale). iPhone remembers all four values across launches; Mac keeps them for the session.
struct TasksViewState: Equatable {
    enum Mode: String, CaseIterable { case list, kanban, timeline }
    enum ListSection: String, CaseIterable { case upcoming, undated, completed, projects }

    var mode = Mode.list
    var listSection = ListSection.upcoming
    var kanbanGrouping = KanbanModel.Grouping.status
    var timelineScale = TimelineModel.Scale.quarter

    /// The single six-way value used before the two-layer selector.
    var legacySection: TasksModel.Section {
        switch mode {
        case .kanban: .kanban
        case .timeline: .timeline
        case .list:
            switch listSection {
            case .upcoming: .upcoming
            case .undated: .undated
            case .completed: .completed
            case .projects: .projects
            }
        }
    }

    /// Maps the six-way value onto tab + list section. A board value only switches the tab,
    /// so the list keeps its last section.
    mutating func apply(_ section: TasksModel.Section) {
        switch section {
        case .kanban: mode = .kanban
        case .timeline: mode = .timeline
        case .upcoming: select(.upcoming)
        case .undated: select(.undated)
        case .completed: select(.completed)
        case .projects: select(.projects)
        }
    }

    private mutating func select(_ section: ListSection) {
        mode = .list
        listSection = section
    }
}

// MARK: - Device preference

extension TasksViewState {
    enum StorageKey {
        static let mode = "tasks.view.mode"
        static let listSection = "tasks.view.list.section"
        static let kanbanGrouping = "tasks.view.kanban.grouping"
        static let timelineScale = "tasks.view.timeline.scale"
        /// One value (`upcoming` … `timeline`) written before the two-layer selector.
        static let legacySection = "tasks.section"
    }

    /// Reads the stored state; unknown or missing values fall back to the defaults.
    ///
    /// Migration: when the legacy single value is present it is mapped onto tab + list section
    /// (`kanban` → kanban tab; `undated` → list tab, undated section), the new keys are
    /// written and the legacy key is removed. Because it is removed here, a legacy value that
    /// shows up again is newer than the stored state and wins once more.
    static func restore(from defaults: UserDefaults) -> TasksViewState {
        var state = TasksViewState()
        if let value = defaults.string(forKey: StorageKey.mode).flatMap(Mode.init(rawValue:)) {
            state.mode = value
        }
        if let value = defaults.string(forKey: StorageKey.listSection).flatMap(ListSection.init(rawValue:)) {
            state.listSection = value
        }
        if let value = defaults.string(forKey: StorageKey.kanbanGrouping)
            .flatMap(KanbanModel.Grouping.init(rawValue:))
        {
            state.kanbanGrouping = value
        }
        if let value = defaults.string(forKey: StorageKey.timelineScale)
            .flatMap(TimelineModel.Scale.init(rawValue:))
        {
            state.timelineScale = value
        }
        if let legacy = defaults.string(forKey: StorageKey.legacySection) {
            if let section = TasksModel.Section(rawValue: legacy) { state.apply(section) }
            state.save(to: defaults)
        }
        return state
    }

    /// Writes the four values and drops the legacy key.
    func save(to defaults: UserDefaults) {
        defaults.set(mode.rawValue, forKey: StorageKey.mode)
        defaults.set(listSection.rawValue, forKey: StorageKey.listSection)
        defaults.set(kanbanGrouping.rawValue, forKey: StorageKey.kanbanGrouping)
        defaults.set(timelineScale.rawValue, forKey: StorageKey.timelineScale)
        defaults.removeObject(forKey: StorageKey.legacySection)
    }
}

extension TasksModel.Section {
    /// Legacy device preference key (see ``TasksViewState/restore(from:)``).
    static let storageKey = TasksViewState.StorageKey.legacySection
}
