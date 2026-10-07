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
            selection: Binding(get: { current }, set: { tasks.viewState.mode = $0 }),
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

/// Pinned page top of a board (kanban, Mac timeline): manşet row with the shared icons and
/// the view tabs. `actions` are board icons placed left of filter; search stays rightmost.
struct TasksBoardHeader<Actions: View>: View {
    let tasks: TasksModel
    let current: TasksViewState.Mode
    @ViewBuilder var actions: Actions

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            InkPageTitle("Görevler") {
                actions
                TaskFiltersMenu(model: tasks)
                SearchButton()
            }
            TasksViewTabs(tasks: tasks, current: current)
                .padding(.horizontal, InkSpacing.margin)
        }
    }
}

extension TasksBoardHeader where Actions == EmptyView {
    init(tasks: TasksModel, current: TasksViewState.Mode) {
        self.init(tasks: tasks, current: current) { EmptyView() }
    }
}
