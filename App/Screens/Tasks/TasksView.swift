import SwiftUI
import VaultFormat
import VaultIndex

struct TasksView: View {
    let store: IndexStore
    let notificationRequest: UUID?
    @Binding var selection: String?
    @State private var pendingNotificationScroll: UUID?
    @State private var detailRow: TaskRow?
    @State private var model: TasksModel
    @ScaledMetric(relativeTo: .body) private var projectCardWidth: CGFloat = 170
    @Environment(\.shellKind) private var shellKind
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
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
            .taskDetailSheet(store: store, row: $detailRow)
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
                    .inkListRowBackground()
            }
            // The sections wait for the first answer: no "Görev yok." or 0 count while it loads.
            if model.list != nil {
                weeklySummaryRow
                projectCardsRow
                #if !os(macOS)
                    // screens.md "Seçici": the list's section menu sits under the project cards.
                    TasksSectionMenu(tasks: model)
                        .inkListRow()
                #endif
                listSections
            }
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

    /// The Mac keeps the section menu in the pinned page top; on iOS it sits under the
    /// project cards (``listContent``).
    private var pageTop: some View {
        TasksPageTop(tasks: model, current: .list) {
            #if os(macOS)
                TasksSectionMenu(tasks: model)
            #endif
        }
    }

    /// "Bu hafta": a small label, the large "3/8 görev" and the accent bar under them.
    private var weeklySummaryRow: some View {
        let summary = model.list?.weekly ?? .empty
        return InkCard {
            VStack(alignment: .leading, spacing: 6) {
                Text("Bu hafta").font(.ink.meta).foregroundStyle(.ink.secondaryText)
                    .accessibilityIdentifier("tasks.weekly.title")
                Text("\(weeklyFraction(summary)) görev")
                    .font(.ink.content)
                    .foregroundStyle(.ink.secondaryText)
                    .monospacedDigit()
                    .accessibilityIdentifier("tasks.weekly.count")
                InkProgress(kind: .fraction(summary.fraction))
            }
        }
        .accessibilityElement(children: .combine)
        .inkListRow()
    }

    private func weeklyFraction(_ summary: TasksWeeklySummary) -> Text {
        Text(verbatim: "\(summary.completed)/\(summary.total)")
            .font(.title2.weight(.bold))
            .foregroundStyle(.ink.text)
    }

    /// Project cards (screens.md): a horizontal strip; at accessibility sizes the cards stack
    /// full width, as the Graph and Map cards do, so grown text is never cut by the strip.
    @ViewBuilder private var projectCardsRow: some View {
        if !model.projects.isEmpty {
            Group {
                if dynamicTypeSize.isAccessibilitySize {
                    VStack(alignment: .leading, spacing: 10) {
                        ForEach(model.projects, id: \.self) { projectCard($0, width: nil) }
                    }
                } else {
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(alignment: .top, spacing: 10) {
                            ForEach(model.projects, id: \.self) { projectCard($0, width: projectCardWidth) }
                        }
                        .fixedSize(horizontal: false, vertical: true)
                    }
                    // A text size change rebuilds the strip, so the row takes the grown cards'
                    // height instead of clipping them at the old one (iPad Dynamic Type audit).
                    .id(dynamicTypeSize)
                    .scrollClipDisabled()
                }
            }
            .inkListRow()
        }
    }

    private func projectCard(_ project: String, width: CGFloat?) -> some View {
        let open = model.openCount(ofProject: project)
        let count = model.list?.projectCounts[VaultIndex.projectKey(project)]
        let completed = count?.done ?? 0
        let total = (count?.open ?? open) + completed
        let color = ProjectColor.color(for: project)
        return NavigationLink {
            ProjectView(store: store, name: project)
        } label: {
            InkCard {
                VStack(alignment: .leading, spacing: 8) {
                    ProjectStateChip(state: .make(completed: completed, total: total))
                    HStack(spacing: 6) {
                        Circle().fill(color).frame(width: 8, height: 8)
                            .accessibilityHidden(true)
                        Text(verbatim: project).font(.ink.content.weight(.semibold)).foregroundStyle(.ink.text)
                            .lineLimit(width == nil ? nil : 1)
                    }
                    Text(String(format: String(localized: "%1$d/%2$d görev"), completed, total))
                        .font(.ink.meta).monospacedDigit().foregroundStyle(.ink.secondaryText)
                    ProjectProgressBar(fraction: total == 0 ? 0 : Double(completed) / Double(total), color: color)
                }
                .frame(width: width, alignment: .leading)
                .frame(maxWidth: width == nil ? .infinity : nil, alignment: .leading)
            }
            .accessibilityElement(children: .combine)
        }
        .buttonStyle(.plain)
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
        ForEach(Array(rows.enumerated()), id: \.element.id) { index, row in
            TasksListRow(
                store: store, row: row, day: model.day,
                isOverdue: row.due.map { $0 < model.day } ?? false,
                isBusy: model.busy.contains(row.id), allowsReopening: true,
                footnote: footnote(for: row), openDetail: { detailRow = row },
                namesMissingProject: true
            ) { Task { await model.toggle(row) } }
            .inkListRow(
                columnSelected: selection == row.id,
                cardSegment: .position(index, of: rows.count)
            )
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

/// A project's state on its card, from its task counts: none done yet, some done, all done.
enum ProjectCardState: Equatable {
    case notStarted, running, done

    static func make(completed: Int, total: Int) -> Self {
        if total > 0 && completed >= total { return .done }
        return completed > 0 ? .running : .notStarted
    }
}

/// The small state capsule at the top of a project card ("● Sürüyor").
struct ProjectStateChip: View {
    let state: ProjectCardState

    var body: some View {
        HStack(spacing: 4) {
            Circle()
                .strokeBorder(dotColor, lineWidth: state == .notStarted ? 1.5 : 0)
                .background(Circle().fill(state == .notStarted ? Color.clear : dotColor))
                .frame(width: 7, height: 7)
                .accessibilityHidden(true)
            title
                .font(.ink.meta)
                .foregroundStyle(.ink.secondaryText)
                .lineLimit(1)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 3)
        .background(Capsule().fill(Color.ink.well))
    }

    private var dotColor: Color {
        switch state {
        case .running: Color.ink.accent
        case .notStarted, .done: Color.ink.secondaryText
        }
    }

    private var title: Text {
        switch state {
        case .notStarted: Text("Başlamadı")
        case .running: Text("Sürüyor")
        case .done: Text("Bitti")
        }
    }
}

/// A project card's bar in the project's own color (the weekly card keeps the accent).
struct ProjectProgressBar: View {
    let fraction: Double
    let color: Color

    var body: some View {
        let value = InkProgressMath.fraction(fraction)
        GeometryReader { geometry in
            ZStack(alignment: .leading) {
                Capsule().fill(Color.ink.well)
                Capsule().fill(color).frame(width: max(0, geometry.size.width * value))
            }
        }
        .frame(height: 4)
        .accessibilityValue(Text(verbatim: InkProgressMath.percentText(value)))
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
