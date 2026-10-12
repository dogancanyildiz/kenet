import SwiftUI

/// Open tasks linking to an entity. The page queries the rows with its timeline
/// (`IndexStore.computeTaskGroups(today:scope:)`, linked to the entity), since a section that
/// draws nothing is never mounted to query them itself.
struct EntityOpenTasksView: View {
    let store: IndexStore
    let rows: [TaskRow]
    @State private var model: TasksModel

    init(store: IndexStore, rows: [TaskRow]) {
        self.store = store
        self.rows = rows
        _model = State(initialValue: TasksModel(store: store))
    }

    var body: some View {
        if !rows.isEmpty || model.errorText != nil {
            Section {
                SectionHeader(title: String(localized: "Açık işler"), count: rows.count)
                    .inkListRow()
                if let error = model.errorText {
                    Text(verbatim: error).foregroundStyle(.ink.danger)
                        .inkListRow()
                }
                ForEach(rows) { row in
                    DayTaskView(
                        store: store, row: row, isToday: true,
                        isOverdue: row.due.map { $0 < model.day } ?? false,
                        completed: false, isBusy: model.busy.contains(row.id)
                    ) { Task { await model.toggle(row) } }
                    .inkListRow()
                }
            }
        }
    }
}
