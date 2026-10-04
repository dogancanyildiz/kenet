import SwiftUI
import VaultFormat

struct ProjectView: View {
    let store: IndexStore
    let name: String
    @State private var actions: TasksModel
    init(store: IndexStore, name: String) {
        self.store = store
        self.name = name
        _actions = State(initialValue: TasksModel(store: store))
    }
    private var model: ProjectModel { ProjectModel(store: store, name: name) }
    var body: some View {
        List {
            Section("Proje") {
                LabeledContent("Açık görevler", value: model.openCount.formatted())
                if let day = model.lastActivity {
                    LabeledContent("Son etkinlik") {
                        Text(LocalDay.instant(for: day), format: .dateTime.day().month().year())
                    }
                }
            }
            ForEach(model.openGroups) { group in
                Section {
                    rows(group.rows)
                } header: {
                    if let day = group.date {
                        Text(LocalDay.instant(for: day), format: .dateTime.day().month().year())
                    } else {
                        Text("Tarihsiz")
                    }
                }
            }
            Section("Tamamlanan") { rows(model.completed) }
            Section("Kişiler ve Konumlar") {
                ForEach(model.entities) { entity in
                    NavigationLink {
                        EntityView(store: store, entity: entity)
                    } label: {
                        EntityRow(entity: entity)
                    }
                }
            }
            if let error = actions.errorText { Text(verbatim: error).foregroundStyle(.red) }
        }
        .navigationTitle(Text(verbatim: name)).toolbar { SearchButton() }
    }
    private func rows(_ rows: [TaskRow]) -> some View {
        ForEach(rows) { row in
            DayTaskView(
                store: store, row: row, isToday: true, isOverdue: row.due.map { $0 < actions.day } ?? false,
                completed: row.isClosed, isBusy: actions.busy.contains(row.id), allowsReopening: true
            ) { Task { await actions.toggle(row) } }
        }
    }
}
