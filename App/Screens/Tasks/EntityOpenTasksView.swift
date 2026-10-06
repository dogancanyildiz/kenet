import SwiftUI

struct EntityOpenTasksView: View {
    let store: IndexStore
    let path: String
    @State private var model: TasksModel

    init(store: IndexStore, path: String) {
        self.store = store
        self.path = path
        _model = State(initialValue: TasksModel(store: store))
    }

    var body: some View {
        let rows = TasksModel.openTasks(in: store, linkedTo: path)
        if !rows.isEmpty || model.errorText != nil {
            Section {
                SectionHeader(title: String(localized: "Açık işler"), count: rows.count)
                if let error = model.errorText {
                    Text(verbatim: error).foregroundStyle(.ink.danger)
                }
                ForEach(rows) { row in
                    DayTaskView(
                        store: store, row: row, isToday: true,
                        isOverdue: row.due.map { $0 < model.day } ?? false,
                        completed: false, isBusy: model.busy.contains(row.id)
                    ) { Task { await model.toggle(row) } }
                }
            }
        }
    }
}
