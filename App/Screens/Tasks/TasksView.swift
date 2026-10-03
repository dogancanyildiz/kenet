import SwiftUI
import VaultFormat

struct TasksView: View {
    let store: IndexStore
    @Binding var selection: String?
    @State private var model: TasksModel

    init(store: IndexStore, selection: Binding<String?> = .constant(nil)) {
        self.store = store
        _selection = selection
        _model = State(initialValue: TasksModel(store: store))
    }

    var body: some View {
        VStack(spacing: 0) {
            Picker("Görev bölümü", selection: $model.section) {
                Text("Yaklaşan").tag(TasksModel.Section.upcoming)
                Text("Tarihsiz").tag(TasksModel.Section.undated)
                Text("Tamamlanan").tag(TasksModel.Section.completed)
            }.pickerStyle(.segmented).padding()
            if model.hasFilters {
                HStack {
                    if let path = model.entityFilter,
                        let entity = store.content.entities.first(where: { $0.id == path })
                    {
                        Text(verbatim: entity.name)
                        if let qualifier = entity.qualifier { Text(verbatim: qualifier) }
                    }
                    if let project = model.projectFilter { Text(verbatim: project) }
                    Button("Filtreleri temizle", systemImage: "xmark.circle") { model.clearFilters() }
                        .labelStyle(.iconOnly)
                }.font(.caption).padding(8).background(.quaternary, in: Capsule()).padding(.horizontal)
            }
            List(selection: $selection) {
                if let error = model.errorText { Text(verbatim: error).foregroundStyle(.red) }
                switch model.section {
                case .upcoming:
                    ForEach(model.agenda) { group in
                        Section {
                            rows(group.rows)
                        } header: {
                            heading(group.date)
                        }
                    }
                    if model.agenda.isEmpty { Text("Görev yok.").foregroundStyle(.secondary) }
                case .undated:
                    rows(model.undated)
                    if model.undated.isEmpty { Text("Görev yok.").foregroundStyle(.secondary) }
                case .completed:
                    rows(model.completed)
                    if model.completed.isEmpty { Text("Görev yok.").foregroundStyle(.secondary) }
                }
            }
        }
        .navigationTitle("Görevler")
        .toolbar {
            TaskFiltersMenu(model: model)
            SearchButton()
        }
        .onChange(of: store.vaultURL) { _, _ in
            model.clearFilters()
            selection = nil
        }
    }

    private func rows(_ rows: [TaskRow]) -> some View {
        ForEach(rows) { row in
            VStack(alignment: .leading, spacing: 4) {
                DayTaskView(
                    store: store, row: row, isToday: true,
                    isOverdue: row.due.map { $0 < model.day } ?? false,
                    completed: false, isBusy: model.busy.contains(row.id), allowsReopening: true
                ) { Task { await model.toggle(row) } }
                if model.section == .undated, let date = row.createdDate {
                    Text(LocalDay.instant(for: date), format: .dateTime.day().month().year())
                        .font(.caption).foregroundStyle(.secondary)
                }
                if model.section == .completed, let date = row.done {
                    Text(LocalDay.instant(for: date), format: .dateTime.day().month().year())
                        .font(.caption).foregroundStyle(.secondary)
                }
                #if os(macOS)
                    Button("Ayrıntıları göster", systemImage: "info.circle") { selection = row.id }
                        .font(.caption).buttonStyle(.borderless)
                #endif
            }.tag(row.id)
        }
    }

    @ViewBuilder private func heading(_ date: CalendarDate?) -> some View {
        if let date {
            if date == model.day {
                Text("Bugün")
            } else if date == tomorrow {
                Text("Yarın")
            } else {
                Text(LocalDay.instant(for: date), format: .dateTime.day().month().year())
            }
        } else {
            Text("Geciken")
        }
    }

    private var tomorrow: CalendarDate {
        let calendar = Calendar(identifier: .gregorian)
        let instant = calendar.date(byAdding: .day, value: 1, to: LocalDay.instant(for: model.day))!
        return LocalDay.today(at: instant)
    }
}

private struct TaskFiltersMenu: View {
    @Bindable var model: TasksModel
    var body: some View {
        Menu {
            ForEach(["person", "place"], id: \.self) { kind in
                Menu(LocalizedStringKey(kind == "person" ? "Kişiler" : "Konumlar")) {
                    ForEach(model.store.content.entities.filter { $0.kind == kind }) { entity in
                        Button {
                            model.entityFilter = entity.id
                        } label: {
                            Text(verbatim: entity.name)
                            if let qualifier = entity.qualifier { Text(verbatim: qualifier) }
                            if model.entityFilter == entity.id { Image(systemName: "checkmark") }
                        }
                    }
                }
            }
            Menu("Projeler") {
                ForEach(model.projects, id: \.self) { project in
                    Button {
                        model.projectFilter = project
                    } label: {
                        Text(verbatim: project)
                        if model.projectFilter == project { Image(systemName: "checkmark") }
                    }
                }
            }
            if model.hasFilters { Button("Filtreleri temizle") { model.clearFilters() } }
        } label: {
            Label(
                "Filtre",
                systemImage: model.hasFilters
                    ? "line.3.horizontal.decrease.circle.fill" : "line.3.horizontal.decrease.circle")
        }
    }
}
