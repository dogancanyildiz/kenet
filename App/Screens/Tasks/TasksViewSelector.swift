import SwiftUI

/// First layer of the Tasks view selector: Liste | Kanban | Zaman çizelgesi, right under the
/// manşet on iPhone and in the Mac content area. The second layer is one menu that depends on
/// the tab: ``TasksSectionMenu`` (list), "Grupla" (kanban), "Ölçek" (timeline).
struct TasksViewTabs: View {
    let tasks: TasksModel
    /// The view that draws these tabs. A board hosted full-width by the Mac shell shows its
    /// own tab as selected and only reports the new choice through ``TasksModel/viewState``.
    let current: TasksViewState.Mode

    var body: some View {
        InkTabs(
            selection: Binding(get: { current }, set: { tasks.viewState.selectTab($0) }),
            items: [
                InkTabItem("Liste", value: TasksViewState.Mode.list, identifier: "tasks.tab.list"),
                InkTabItem("Kanban", value: TasksViewState.Mode.kanban, identifier: "tasks.tab.kanban"),
                InkTabItem(
                    "Zaman çizelgesi", value: TasksViewState.Mode.timeline,
                    identifier: "tasks.tab.timeline"),
            ], identifier: "tasks.tabs")
    }
}

/// Second layer in the list: which section of the task list is shown.
struct TasksSectionMenu: View {
    @Bindable var tasks: TasksModel

    var body: some View {
        InkLabeledMenu(
            "Bölüm", selection: $tasks.viewState.listSection,
            options: [
                InkMenuOption("Yaklaşan", value: TasksViewState.ListSection.upcoming),
                InkMenuOption("Tarihsiz", value: TasksViewState.ListSection.undated),
                InkMenuOption("Tamamlanan", value: TasksViewState.ListSection.completed),
                InkMenuOption("Projeler", value: TasksViewState.ListSection.projects),
            ], identifier: TasksViewSelector.menuIdentifier)
    }
}

enum TasksViewSelector {
    /// Shared by the second-layer menu of every tab (only one is on screen at a time).
    static let menuIdentifier = "tasks.menu"
}

/// Page top shared by the three Tasks views on both platforms: manşet row, view tabs, the
/// tab's menu row and the active-filter band, with one set of vertical measures. Switching
/// tabs therefore leaves the manşet, the tabs and the menu exactly where they were.
///
/// Lists show it as their first row (``View/tasksPageTopRow()``), boards pin it above the
/// board. `actions` are view icons placed left of filter; search stays rightmost. `menu` is
/// the second layer of the selector and whatever shares its row.
struct TasksPageTop<Actions: View, MenuRow: View>: View {
    let tasks: TasksModel
    let current: TasksViewState.Mode
    @ViewBuilder var actions: Actions
    @ViewBuilder var menu: MenuRow

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            InkPageHeader("Görevler") {
                actions
                TaskFiltersMenu(model: tasks)
                SearchButton()
            }
            // Same insets as ``InkPageTitleRow``.
            .padding(.top, 8)
            .padding(.bottom, 4)
            TasksViewTabs(tasks: tasks, current: current)
                .padding(.vertical, Self.gap)
            menu
                .padding(.vertical, Self.gap)
            if tasks.hasFilters {
                TaskFilterBand(model: tasks)
                    .padding(.vertical, Self.gap)
            }
        }
        .padding(.horizontal, InkSpacing.margin)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.ink.paper)
    }

    /// Space above and below each row of the page top (same as a list row's inset).
    private static var gap: CGFloat { InkSpacing.row }
}

extension TasksPageTop where Actions == EmptyView {
    init(tasks: TasksModel, current: TasksViewState.Mode, @ViewBuilder menu: () -> MenuRow) {
        self.init(tasks: tasks, current: current, actions: { EmptyView() }, menu: menu)
    }
}

extension View {
    /// ``TasksPageTop`` as the first row of a list: it brings its own margins and spacing.
    func tasksPageTopRow() -> some View {
        listRowInsets(EdgeInsets())
            .listRowSeparator(.hidden)
            .listRowBackground(Color.ink.paper)
    }
}

// MARK: - Board menu choices

extension KanbanModel {
    /// A board that starts from the grouping last chosen in the shared view state, so
    /// switching tabs (the view is rebuilt) does not reset the menu.
    static func board(for tasks: TasksModel) -> KanbanModel {
        let model = KanbanModel(tasks: tasks)
        model.grouping = tasks.viewState.kanbanGrouping
        return model
    }

    /// The "Grupla" menu: applies the choice and reports it to the shared view state.
    func choose(_ grouping: Grouping) {
        self.grouping = grouping
        tasks.viewState.kanbanGrouping = grouping
    }
}

extension TimelineModel {
    /// Grouping of a fresh timeline; the Mac header icon is accented for any other value.
    static var defaultGrouping: Grouping { .project }

    /// A timeline that starts from the scale last chosen in the shared view state.
    static func board(for tasks: TasksModel) -> TimelineModel {
        let model = TimelineModel(tasks: tasks)
        model.scale = tasks.viewState.timelineScale
        return model
    }

    /// The "Ölçek" menu: applies the choice and reports it to the shared view state.
    func choose(_ scale: Scale) {
        self.scale = scale
        tasks.viewState.timelineScale = scale
    }
}
