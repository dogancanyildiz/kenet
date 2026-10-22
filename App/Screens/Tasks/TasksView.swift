import SwiftUI
import VaultFormat

struct TasksView: View {
    let store: IndexStore
    let notificationRequest: UUID?
    @Binding var selection: String?
    @State private var pendingNotificationScroll: UUID?
    @State private var model: TasksModel
    @Environment(\.shellKind) private var shellKind
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
                        .inkPageScrollColumn()
                        .task(id: model.listRequest) {
                            await model.loadList()
                            scrollNotification(using: proxy)
                        }
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
            .onChange(of: store.vaultURL) { _, _ in
                model.clearFilters()
                selection = nil
            }
            // Only a split shell's detail column follows the selection (the Mac window, the
            // iPhone Duo inner screen, an iPad); the phone's tab shell never sets one.
            .onChange(of: model.viewState.listSection) { _, _ in
                if followsSelection { selection = nil }
            }
            .onChange(of: model.entityFilter) { _, _ in
                if followsSelection { selection = nil }
            }
            .onChange(of: model.projectFilter) { _, _ in
                if followsSelection { selection = nil }
            }
            // The phone does not build the row list for nothing on every body.
            .onChange(of: followsSelection ? listedTaskIDs : []) { _, ids in
                if followsSelection { selection = TaskListSelection.keeping(selection, listedIDs: ids) }
            }
        }
    }

    /// The Mac shell always has a detail column; on iOS only the split shell does.
    private var followsSelection: Bool {
        #if os(macOS)
            true
        #else
            shellKind == .split
        #endif
    }

    /// Rows on screen for the current section. The detail column clears when the selection
    /// is no longer one of them (a completed task leaves Yaklaşan, a filter drops it).
    private var listedTaskIDs: [String] {
        switch model.viewState.listSection {
        case .projects:
            []
        case .upcoming:
            model.agenda.flatMap(\.rows).map(\.id)
        case .undated:
            model.undated.map(\.id)
        case .completed:
            model.completed.map(\.id)
        }
    }

    @ViewBuilder private var listContent: some View {
        List(selection: $selection) {
            InkScrolledMasthead(pageTop)
                .tasksPageTopRow()
            if let error = model.errorText ?? model.listErrorText {
                InfoBand(kind: .error, verbatim: error)
                    .listRowInsets(EdgeInsets())
                    .listRowSeparator(.hidden)
                    .listRowBackground(Color.ink.paper)
            }
            // The sections wait for the first answer: no "Görev yok." or 0 count while it loads.
            if model.list != nil { listSections }
        }
        .listStyle(.plain)
        .inkPage()
        // The whole page top stays, as it does above the boards: manşet, view tabs, menu row.
        // A Mac list insets even a row with no insets of its own; the strip does the same.
        .inkPinnedMasthead(
            pageTop,
            insets: EdgeInsets(
                top: 0, leading: MacListColumnChrome.rowInset, bottom: 0, trailing: MacListColumnChrome.rowInset),
            columnWidth: .infinity)
    }

    private var pageTop: some View {
        TasksPageTop(tasks: model, current: .list) {
            TasksSectionMenu(tasks: model)
        }
    }

    @ViewBuilder private var listSections: some View {
        switch model.viewState.listSection {
        case .projects:
            ForEach(model.projects, id: \.self) { project in
                NavigationLink {
                    ProjectView(store: store, name: project)
                } label: {
                    LabeledContent {
                        Text(model.openCount(ofProject: project).formatted())
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

    /// A cold notification launch can arrive before the first index publication; the jump waits
    /// for the list's answer to the cleared filters after it.
    private func scrollNotification(using proxy: ScrollViewProxy) {
        guard let request = pendingNotificationScroll, store.lastUpdated != nil, model.isListCurrent else { return }
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
            .inkListRow(columnSelected: selection == row.id)
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

/// Detail-column selection. A section or filter change clears it outright; a list refresh
/// keeps it only while the id is still on screen.
enum TaskListSelection {
    static func keeping(_ selection: String?, listedIDs: [String]) -> String? {
        guard let selection, listedIDs.contains(selection) else { return nil }
        return selection
    }
}
