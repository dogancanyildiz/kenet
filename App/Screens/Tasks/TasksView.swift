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
    #if os(iOS)
        @AppStorage(TasksModel.Section.storageKey) private var storedSection = "upcoming"
    #endif

    init(
        store: IndexStore, selection: Binding<String?> = .constant(nil), notificationRequest: UUID? = nil,
        tasks: TasksModel? = nil, onKanbanSelected: (() -> Void)? = nil, onTimelineSelected: (() -> Void)? = nil
    ) {
        self.store = store
        self.notificationRequest = notificationRequest
        self.onKanbanSelected = onKanbanSelected
        self.onTimelineSelected = onTimelineSelected
        _selection = selection
        let model = tasks ?? TasksModel(store: store)
        #if os(iOS)
            if tasks == nil,
                let restored = TasksModel.Section(
                    rawValue: UserDefaults.standard.string(forKey: TasksModel.Section.storageKey) ?? "")
            {
                model.section = restored
            }
        #endif
        _model = State(initialValue: model)
    }

    var body: some View {
        ScrollViewReader { proxy in
            VStack(spacing: 0) {
                if model.hasFilters {
                    filterBand
                }
                if model.section == .kanban {
                    KanbanView(tasks: model)
                } else if model.section == .timeline {
                    TaskTimelineView(tasks: model)
                } else {
                    listContent
                }
            }
            .inkPage()
            .inkPageColumn()
            .navigationTitle("Görevler")
            .accessibilityIdentifier("screen.tasks")
            .toolbar {
                TasksSectionPicker(section: $model.section)
                TaskFiltersMenu(model: model)
                SearchButton()
            }
            .onChange(of: model.section) { _, section in
                #if os(iOS)
                    storedSection = section.rawValue
                #endif
                if section == .kanban { onKanbanSelected?() }
                if section == .timeline { onTimelineSelected?() }
            }
            .onChange(of: notificationRequest, initial: true) { _, request in
                guard request != nil else { return }
                // Temporary jump for the notification; do not persist over the user's section.
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

    private var filterBand: some View {
        HStack(spacing: 8) {
            if let path = model.entityFilter,
                let entity = store.content.entities.first(where: { $0.id == path })
            {
                TagChip(
                    title: entity.name,
                    systemImage: entity.kind == "place" ? "mappin" : "person")
            }
            if let project = model.projectFilter {
                TagChip(title: project, systemImage: "folder")
            }
            Spacer(minLength: 0)
            Button {
                model.clearFilters()
            } label: {
                Label("Filtreleri temizle", systemImage: "xmark.circle")
                    .labelStyle(.iconOnly)
                    .tapTarget()
            }
            .buttonStyle(InkTextButtonStyle())
        }
        .padding(.horizontal, InkSpacing.margin)
        .padding(.vertical, 8)
    }

    @ViewBuilder private var listContent: some View {
        List(selection: $selection) {
            if let error = model.errorText {
                InfoBand(kind: .error, verbatim: error)
                    .listRowBackground(Color.clear)
                    .listRowInsets(EdgeInsets())
            }
            switch model.section {
            case .kanban, .timeline: EmptyView()
            case .projects:
                ForEach(model.projects, id: \.self) { project in
                    NavigationLink {
                        ProjectView(store: store, name: project)
                    } label: {
                        LabeledContent {
                            Text(ProjectModel(store: store, name: project).openCount.formatted())
                                .font(.ink.value)
                                .foregroundStyle(.ink.secondaryText)
                        } label: {
                            Text(verbatim: project)
                                .font(.ink.content)
                                .foregroundStyle(.ink.text)
                        }
                    }
                }
                if model.projects.isEmpty {
                    EmptyState("Henüz proje yok")
                        .listRowBackground(Color.clear)
                }
            case .upcoming:
                ForEach(model.agenda) { group in
                    Section {
                        rows(group.rows)
                    } header: {
                        SectionHeader(title: headingTitle(group.date), count: group.rows.count)
                    }.id(group.id)
                }
                if model.agenda.isEmpty {
                    EmptyState("Görev yok.")
                        .listRowBackground(Color.clear)
                }
            case .undated:
                Section {
                    rows(model.undated)
                } header: {
                    SectionHeader(title: String(localized: "Tarihsiz"), count: model.undated.count)
                }
                if model.undated.isEmpty {
                    EmptyState("Görev yok.")
                        .listRowBackground(Color.clear)
                }
            case .completed:
                Section {
                    rows(model.completed)
                } header: {
                    SectionHeader(title: String(localized: "Tamamlanan"), count: model.completed.count)
                }
                if model.completed.isEmpty {
                    EmptyState("Görev yok.")
                        .listRowBackground(Color.clear)
                }
            }
        }
        .listStyle(.plain)
        .scrollContentBackground(.hidden)
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
                TasksListRow(
                    store: store, row: row, day: model.day,
                    isOverdue: row.due.map { $0 < model.day } ?? false,
                    completed: false, isBusy: model.busy.contains(row.id), allowsReopening: true,
                    footnote: footnote(for: row)
                ) { Task { await model.toggle(row) } }
                #if os(macOS)
                    Button("Ayrıntıları göster", systemImage: "info.circle") { selection = row.id }
                        .font(.ink.meta)
                        .buttonStyle(InkTextButtonStyle())
                #endif
            }
            .tag(row.id)
            .listRowBackground(Color.ink.paper)
            .alignmentGuide(.listRowSeparatorLeading) { _ in 0 }
        }
    }

    private func footnote(for row: TaskRow) -> Text? {
        if model.section == .undated, let date = row.createdDate {
            return Text(LocalDay.instant(for: date), format: .dateTime.day().month().year())
        }
        if model.section == .completed, let date = row.done {
            return Text(LocalDay.instant(for: date), format: .dateTime.day().month().year())
        }
        return nil
    }

    private func headingTitle(_ date: CalendarDate?) -> String {
        if let date {
            if date == model.day {
                return String(localized: "Bugün")
            }
            if date == tomorrow {
                return String(localized: "Yarın")
            }
            return LocalDay.instant(for: date).formatted(.dateTime.day().month().year())
        }
        return String(localized: "Devreden")
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
