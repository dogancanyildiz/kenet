import SwiftUI
import VaultFormat

struct TasksView: View {
    let store: IndexStore
    let notificationRequest: UUID?
    let onKanbanSelected: (() -> Void)?
    let onTimelineSelected: (() -> Void)?
    @Binding var selection: String?
    @State private var pendingNotificationScroll: UUID?
    @State private var model: TasksModel

    init(
        store: IndexStore, selection: Binding<String?> = .constant(nil), notificationRequest: UUID? = nil,
        tasks: TasksModel? = nil, onKanbanSelected: (() -> Void)? = nil, onTimelineSelected: (() -> Void)? = nil
    ) {
        self.store = store
        self.notificationRequest = notificationRequest
        self.onKanbanSelected = onKanbanSelected
        self.onTimelineSelected = onTimelineSelected
        _selection = selection
        _model = State(initialValue: tasks ?? TasksModel(store: store))
    }

    var body: some View {
        ScrollViewReader { proxy in
            VStack(spacing: 0) {
                Picker("Görev bölümü", selection: $model.section) {
                    Text("Yaklaşan").tag(TasksModel.Section.upcoming)
                    Text("Tarihsiz").tag(TasksModel.Section.undated)
                    Text("Tamamlanan").tag(TasksModel.Section.completed)
                    Text("Projeler").tag(TasksModel.Section.projects)
                    Text("Kanban").tag(TasksModel.Section.kanban)
                    Text("Zaman çizelgesi").tag(TasksModel.Section.timeline)
                }.pickerStyle(.menu).frame(maxWidth: .infinity, alignment: .leading).padding()
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
                if model.section == .kanban {
                    KanbanView(tasks: model)
                } else if model.section == .timeline {
                    TaskTimelineView(tasks: model)
                } else {
                    List(selection: $selection) {
                        if let error = model.errorText { Text(verbatim: error).foregroundStyle(.red) }
                        switch model.section {
                        case .kanban, .timeline: EmptyView()
                        case .projects:
                            ForEach(model.projects, id: \.self) { project in
                                NavigationLink {
                                    ProjectView(store: store, name: project)
                                } label: {
                                    LabeledContent {
                                        Text(ProjectModel(store: store, name: project).openCount.formatted())
                                    } label: {
                                        Text(verbatim: project)
                                    }
                                }
                            }
                            if model.projects.isEmpty { Text("Henüz proje yok").foregroundStyle(.secondary) }
                        case .upcoming:
                            ForEach(model.agenda) { group in
                                Section {
                                    rows(group.rows)
                                } header: {
                                    heading(group.date)
                                }.id(group.id)
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
            }
            .navigationTitle("Görevler")
            .toolbar {
                TaskFiltersMenu(model: model)
                SearchButton()
            }
            .onChange(of: model.section) { _, section in
                if section == .kanban { onKanbanSelected?() }
                if section == .timeline { onTimelineSelected?() }
            }
            .onChange(of: notificationRequest, initial: true) { _, request in
                guard request != nil else { return }
                model.section = .upcoming
                model.clearFilters()
                selection = nil
                pendingNotificationScroll = request
                scrollNotification(using: proxy)
            }
            .onChange(of: store.lastUpdated) { _, _ in scrollNotification(using: proxy) }
            .onChange(of: store.vaultURL) { _, _ in
                model.clearFilters()
                selection = nil
            }
        }
    }

    /// A cold notification launch can arrive before the first index publication.
    private func scrollNotification(using proxy: ScrollViewProxy) {
        guard let request = pendingNotificationScroll, store.lastUpdated != nil else { return }
        guard !model.agenda.isEmpty else {
            pendingNotificationScroll = nil
            return
        }
        Task { @MainActor in
            await Task.yield()
            guard pendingNotificationScroll == request else { return }
            let target = model.agenda.contains { $0.date == model.day } ? model.day.description : "overdue"
            proxy.scrollTo(target, anchor: .top)
            pendingNotificationScroll = nil
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

struct TaskFiltersMenu: View {
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
