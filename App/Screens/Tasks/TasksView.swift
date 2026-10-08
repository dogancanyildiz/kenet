import SwiftUI
import VaultFormat

struct TasksView: View {
    let store: IndexStore
    let notificationRequest: UUID?
    @Binding var selection: String?
    @State private var pendingNotificationScroll: UUID?
    @State private var model: TasksModel
    init(
        store: IndexStore, selection: Binding<String?> = .constant(nil), notificationRequest: UUID? = nil,
        tasks: TasksModel? = nil
    ) {
        self.store = store
        self.notificationRequest = notificationRequest
        _selection = selection
        let model = tasks ?? TasksModel(store: store)
        #if os(iOS)
            if tasks == nil { model.viewState = TasksViewState.restore(from: .standard) }
        #endif
        _model = State(initialValue: model)
    }

    var body: some View {
        ScrollViewReader { proxy in
            Group {
                switch model.viewState.mode {
                case .kanban: KanbanView(tasks: model)
                case .timeline: TaskTimelineView(tasks: model)
                case .list:
                    listContent
                        .inkPageColumn()
                }
            }
            .inkPage()
            .inkRootPageNavigationTitle("Görevler")
            .accessibilityIdentifier("screen.tasks")
            .onChange(of: model.viewState) { _, state in
                #if os(iOS)
                    state.save(to: .standard)
                #endif
            }
            .onChange(of: notificationRequest, initial: true) { _, request in
                guard request != nil else { return }
                // Jump to the agenda for the notification.
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

    @ViewBuilder private var listContent: some View {
        List(selection: $selection) {
            TasksPageTop(tasks: model, current: .list) {
                TasksSectionMenu(tasks: model)
            }
            .tasksPageTopRow()
            if let error = model.errorText {
                InfoBand(kind: .error, verbatim: error)
                    .listRowInsets(EdgeInsets())
                    .listRowSeparator(.hidden)
                    .listRowBackground(Color.ink.paper)
            }
            switch model.viewState.listSection {
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
                    .inkListRow()
                }
                if model.projects.isEmpty {
                    EmptyState("Henüz proje yok")
                        .inkListRow()
                }
            case .upcoming:
                ForEach(model.agenda) { group in
                    Section {
                        SectionHeader(title: headingTitle(group.date), count: group.rows.count)
                            .inkListRow()
                        rows(group.rows)
                    }.id(group.id)
                }
                if model.agenda.isEmpty {
                    EmptyState("Görev yok.")
                        .inkListRow()
                }
            case .undated:
                Section {
                    SectionHeader(title: String(localized: "Tarihsiz"), count: model.undated.count)
                        .inkListRow()
                    rows(model.undated)
                }
                if model.undated.isEmpty {
                    EmptyState("Görev yok.")
                        .inkListRow()
                }
            case .completed:
                Section {
                    SectionHeader(title: String(localized: "Tamamlanan"), count: model.completed.count)
                        .inkListRow()
                    rows(model.completed)
                }
                if model.completed.isEmpty {
                    EmptyState("Görev yok.")
                        .inkListRow()
                }
            }
        }
        .listStyle(.plain)
        .inkPage()
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
            TasksListRow(
                store: store, row: row, day: model.day,
                isOverdue: row.due.map { $0 < model.day } ?? false,
                isBusy: model.busy.contains(row.id), allowsReopening: true,
                footnote: footnote(for: row)
            ) { Task { await model.toggle(row) } }
            .inkListRow()
            .inkColumnSelection(isSelected: selection == row.id)
            .tag(row.id)
            .alignmentGuide(.listRowSeparatorLeading) { _ in 0 }
        }
    }

    private func footnote(for row: TaskRow) -> Text? {
        if model.viewState.listSection == .undated, let date = row.createdDate {
            return Text(LocalDay.instant(for: date), format: .dateTime.day().month().year())
        }
        if model.viewState.listSection == .completed, let date = row.done {
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
