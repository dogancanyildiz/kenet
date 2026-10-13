import SwiftUI
import VaultFormat

/// Lists stay alongside their selection in the desktop's three columns. The Mac window, and
/// on iOS the iPhone Duo inner screen (`AdaptiveNavigation`): there the shell shows two
/// columns at a time (``ShellStyle/columnVisibility(layout:width:)``).
struct MacNavigation: View {
    let store: IndexStore
    @Environment(IntentNavigation.self) private var intentNavigation
    @Environment(NotificationService.self) private var notifications
    @State private var kanbanTasks: TasksModel
    @State private var navigation: ShellNavigationState
    @State private var sidebarRestoresFocus = false
    @State private var taskSelection = TaskSelectionAnswer()
    /// The sidebar's project rows (`IndexStore.computeProjects()`); a reload keeps them until it answers.
    @State private var sidebarProjects: [String] = []
    #if os(iOS)
        @State private var columnVisibility = NavigationSplitViewVisibility.automatic
        @State private var shellWidth: CGFloat = 0
    #endif

    init(store: IndexStore, navigation: ShellNavigationState = ShellNavigationState()) {
        self.store = store
        _kanbanTasks = State(initialValue: TasksModel(store: store))
        _navigation = State(initialValue: navigation)
    }

    var body: some View {
        Group {
            switch shellLayout {
            case .page:
                splitView {
                    sidebar
                } detail: {
                    NavigationStack {
                        if navigation.section == .graph {
                            GraphView(store: store)
                        } else if navigation.section == .map {
                            PlacesMapView(store: store)
                        } else {
                            SummariesView(store: store)
                        }
                    }
                    // Full-width paper; graph / map / summaries are not reading columns.
                    .inkPage()
                    .macSearchToolbar()
                }
            case .board:
                splitView {
                    sidebar
                } detail: {
                    Group {
                        if tasksShell.layout == .timeline {
                            TaskTimelineView(tasks: kanbanTasks, showsFilters: true, openDay: openTaskDay)
                        } else {
                            KanbanView(tasks: kanbanTasks, showsFilters: true, openDay: openTaskDay)
                        }
                    }
                    .inkPage()
                    .macSearchToolbar()
                }
            case .columns:
                standardLayout
            }
        }
        #if os(macOS)
            // The page name is the serif manşet inside the page; the toolbar repeats nothing.
            // The window keeps a title (Window menu, Mission Control): the selected sidebar row.
            .navigationTitle(windowTitle)
            .toolbar(removing: .title)
            .macMainWindowMinimumSize()
        #else
            // Columns side by side: the default style lays the detail over the others.
            .navigationSplitViewStyle(.balanced)
            .onGeometryChange(for: CGFloat.self) {
                $0.size.width
            } action: { width in
                shellWidth = width
                resetColumns()
            }
            .onChange(of: shellLayout) { _, _ in resetColumns() }
        #endif
        .environment(\.shellKind, .split)
        .onChange(of: intentNavigation.todayRequest, initial: true) { _, request in
            guard request != nil else { return }
            navigation.detailPath = NavigationPath()
            navigation.selectedDay = nil
            navigation.selectedTask = nil
            tasksEvent(.navigationReset)
            navigation.selectedGoal = nil
            navigation.section = .today
        }
        .onChange(of: notifications.navigationRequest?.id, initial: true) { _, id in
            guard id != nil, let request = notifications.navigationRequest else { return }
            navigation.detailPath = NavigationPath()
            tasksEvent(.navigationReset)
            navigation.selectedTask = nil
            navigation.selectedDay = nil
            switch NotificationRoute(request.destination) {
            case .tasks:
                navigation.section = .tasks
            case .unseenPeople:
                navigation.section = .people
                navigation.selectedEntityKind = "person"
                navigation.entitySearch = ""
                navigation.selectedEntity = nil
                navigation.selectedSummary = nil
                navigation.unseenReveal = request.id
            case .today:
                navigation.section = .today
            }
        }
        .onChange(of: store.vaultURL) { _, _ in
            navigation.selectedTask = nil
            tasksEvent(.vaultChanged)
            kanbanTasks.clearFilters()
            navigation.selectedGoal = nil
        }
        .onChange(of: navigation.section) { _, value in
            if value == .people || value == .places {
                navigation.selectedEntityKind = value == .places ? "place" : "person"
            }
            if value != .tasks { tasksEvent(.sectionLeft) }
        }
        .task(id: store.lastUpdated) {
            if let projects = try? await store.computeProjects() { sidebarProjects = projects }
        }
        .onChange(of: sidebarProjects) { _, projects in
            var selection = shellSelection
            selection.projectsChanged(projects)
            apply(selection)
        }
        .onChange(of: navigation.selectedDay) { _, value in
            if value != nil { navigation.section = .days }
        }
        .task(id: TaskSelectionRequest(id: navigation.selectedTask, updated: store.lastUpdated)) {
            let request = TaskSelectionRequest(id: navigation.selectedTask, updated: store.lastUpdated)
            if let answer = await TaskSelectionAnswer.load(request, store: store) { taskSelection = answer }
        }
        #if os(macOS)
            .focusedSceneValue(
                \.goToToday,
                {
                    navigation.section = .today
                    navigation.selectedDay = nil
                })
        #endif
    }

    private var sidebar: some View {
        MacSidebarList(
            entries: MacSidebar.entries(projects: sidebarProjects),
            selection: Binding(
                get: { shellSelection.sidebarEntry },
                set: { entry in if let entry { selectSidebarEntry(entry) } }),
            // A click on the selected "Görevler" row still returns the list to its first section.
            onClick: { entry in if entry == .section(.tasks) { tasksEvent(.sidebarTasks) } },
            restoresFocus: $sidebarRestoresFocus
        )
    }

    /// Sidebar and one full-width detail (board, page). iOS hands the column visibility to the
    /// shell; the Mac window keeps the system's own, as each layout always had.
    private func splitView<Sidebar: View, Detail: View>(
        @ViewBuilder sidebar: () -> Sidebar, @ViewBuilder detail: () -> Detail
    ) -> some View {
        #if os(macOS)
            NavigationSplitView(sidebar: sidebar, detail: detail)
        #else
            NavigationSplitView(columnVisibility: $columnVisibility, sidebar: sidebar, detail: detail)
        #endif
    }

    /// Sidebar, list column and detail.
    private func splitView<Sidebar: View, Content: View, Detail: View>(
        @ViewBuilder sidebar: () -> Sidebar, @ViewBuilder content: () -> Content,
        @ViewBuilder detail: () -> Detail
    ) -> some View {
        #if os(macOS)
            NavigationSplitView(sidebar: sidebar, content: content, detail: detail)
        #else
            NavigationSplitView(
                columnVisibility: $columnVisibility, sidebar: sidebar, content: content, detail: detail)
        #endif
    }

    private var standardLayout: some View {
        splitView {
            sidebar
        } content: {
            Group {
                switch navigation.section ?? .today {
                case .today, .days:
                    MacDaysColumn(store: store, selection: $navigation.selectedDay) {
                        navigation.section = .summaries
                    }
                case .tasks:
                    if let project = navigation.selectedProject {
                        NavigationStack { ProjectView(store: store, name: project).id(project) }
                    } else {
                        TasksView(
                            store: store, selection: $navigation.selectedTask,
                            notificationRequest: notifications.navigationRequest?.destination == .tasks
                                ? notifications.navigationRequest?.id : nil,
                            tasks: kanbanTasks)
                    }
                case .summaries, .graph, .map: EmptyView()
                case .goals:
                    GoalsView(store: store, selection: $navigation.selectedGoal)
                case .people, .places:
                    MacEntitiesColumn(
                        store: store, sectionTitle: (navigation.section ?? .people).title,
                        kind: $navigation.selectedEntityKind, order: $navigation.entityOrder,
                        search: $navigation.entitySearch, selection: entitySelection,
                        unseenReveal: navigation.unseenReveal)
                }
            }
            .inkPage()
            .macListColumn()
        } detail: {
            NavigationStack(path: $navigation.detailPath) {
                switch navigation.section ?? .today {
                case .today:
                    TodayView(store: store)
                case .days:
                    if let path = navigation.selectedDay,
                        let day = CalendarDate(String(path.dropFirst("journal/".count).dropLast(3)))
                    {
                        DayView(store: store, date: day).id(day)
                    } else {
                        MacEmptyDetail("Bir gün seç")
                    }
                case .tasks:
                    if let row = taskSelection.row(
                        for: navigation.selectedTask, listed: kanbanTasks.listedRow(id: navigation.selectedTask))
                    {
                        TaskDetailView(store: store, row: row) { path in
                            navigation.selectedDay = path
                            navigation.section = .days
                        }
                    } else {
                        MacEmptyDetail("Bir görev seç")
                    }
                case .summaries, .graph, .map: EmptyView()
                case .goals:
                    if let goal = store.content.goals.first(where: { $0.id == navigation.selectedGoal }) {
                        GoalDetailView(store: store, goal: goal).id(goal.id + (store.vaultURL?.path ?? ""))
                    } else {
                        MacEmptyDetail("Bir hedef seç")
                    }
                case .people, .places:
                    if let entity = navigation.selectedSummary, entity.kind == entityKind {
                        EntityView(store: store, entity: entity) { path in
                            navigation.selectedEntity = path
                            navigation.selectedSummary =
                                store.content.entities.first { $0.id == path } ?? navigation.selectedSummary
                        }.id(navigation.entityRouteID)
                    } else {
                        MacEmptyDetail("Bir varlık seç")
                    }
                }
            }
            .id(navigation.section)
            // Shell paints paper full-width; each page view applies `.inkPageColumn()` itself.
            // An empty branch stretches over the column (`MacEmptyDetail`); otherwise this
            // paper is only as large as the prompt and the stack's system white (dark: gray)
            // shows around it.
            .inkPage()
            .macSearchToolbar()
        }
    }

    #if os(macOS)
        private var windowTitle: Text {
            shellSelection.sidebarEntry?.title ?? Text("Journal")
        }
    #endif

    private var shellLayout: MacShellLayout { shellSelection.layout }

    private var shellSelection: MacShellSelection {
        MacShellSelection(section: navigation.section, tasks: tasksShell)
    }

    private func apply(_ selection: MacShellSelection) {
        if kanbanTasks.viewState != selection.tasks.view { kanbanTasks.viewState = selection.tasks.view }
        if navigation.selectedProject != selection.tasks.project {
            navigation.selectedProject = selection.tasks.project
        }
        if navigation.section != selection.section { navigation.section = selection.section }
    }

    /// Called for a choice made in the sidebar (click, arrow key, touch or VoiceOver).
    private func selectSidebarEntry(_ entry: MacSidebarEntry) {
        var selection = shellSelection
        let restoresFocus = selection.select(entry)
        if entry.isNested { navigation.selectedTask = nil }
        apply(selection)
        if restoresFocus { sidebarRestoresFocus = true }
        #if os(iOS)
            // Two columns at a time: the choice puts the sidebar away again.
            resetColumns()
        #endif
    }

    #if os(iOS)
        private func resetColumns() {
            guard let visibility = ShellStyle.columnVisibility(layout: shellLayout, width: shellWidth) else { return }
            if columnVisibility != visibility { columnVisibility = visibility }
        }
    #endif

    /// Tasks layout (list column, full-width board, project) comes from the shared view
    /// state alone; the sidebar and the tabs in the content area write the same value.
    private var tasksShell: TasksShellState {
        TasksShellState(view: kanbanTasks.viewState, project: navigation.selectedProject)
    }

    private func tasksEvent(_ event: TasksShellState.Event) {
        var shell = tasksShell
        shell.handle(event)
        if kanbanTasks.viewState != shell.view { kanbanTasks.viewState = shell.view }
        if navigation.selectedProject != shell.project { navigation.selectedProject = shell.project }
    }

    private func openTaskDay(_ path: String) {
        navigation.selectedDay = path
        navigation.section = .days
    }

    private var entitySelection: Binding<String?> {
        Binding(
            get: { navigation.selectedEntity },
            set: { path in
                navigation.selectedEntity = path
                navigation.selectedSummary = store.content.entities.first { $0.id == path }
                navigation.entityRouteID = UUID()
            })
    }

    private var entityKind: String { navigation.selectedEntityKind }
}

/// Detail column with nothing selected: the shared empty state (one italic line, no box),
/// stretched over the column so the shell's `.inkPage()` paper reaches every edge. Günlük,
/// Görevler (projects included), Hedefler and Kişiler / Konumlar use this.
struct MacEmptyDetail: View {
    let message: LocalizedStringKey

    init(_ message: LocalizedStringKey) {
        self.message = message
    }

    var body: some View {
        EmptyState(message)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

#if os(macOS)
    struct TodayNavigationKey: FocusedValueKey {
        typealias Value = () -> Void
    }

    extension FocusedValues {
        var goToToday: (() -> Void)? {
            get { self[TodayNavigationKey.self] }
            set { self[TodayNavigationKey.self] = newValue }
        }
    }
#endif

/// Günlük list column: manşet, the Özetler and weekly review links under it, the month and the days.
struct MacDaysColumn: View {
    let store: IndexStore
    @Binding var selection: String?
    let openSummaries: () -> Void
    @State private var showsWeeklyReview = false
    @State private var weeklyReviewNotice: WeeklyReviewNotice?
    /// Nil until the first query returns; a reload keeps the previous rows until then.
    @State private var days: [DayOverview]?

    var body: some View {
        VStack(spacing: 0) {
            InkPageTitle("Günlük").macListColumnTitle()
            VStack(alignment: .leading, spacing: 0) {
                Button(action: openSummaries) {
                    Label("Özetler", systemImage: "chart.bar")
                }
                // Like the iPhone row: once this week is reviewed, the link says so.
                HStack(alignment: .firstTextBaseline, spacing: InkSpacing.row) {
                    Button {
                        showsWeeklyReview = true
                    } label: {
                        Label("Haftalık inceleme", systemImage: "checklist")
                    }
                    .accessibilityIdentifier("button.weeklyReview")
                    WeeklyReviewEntryStatus()
                }
            }
            .buttonStyle(InkTextButtonStyle())
            // Starts where the manşet above it starts.
            .padding(.leading, InkSpacing.margin + MacListColumnChrome.rowInset)
            .padding(.vertical, 8)
            .frame(maxWidth: .infinity, alignment: .leading)
            if let notice = weeklyReviewNotice {
                InfoBand(kind: notice.kind, verbatim: notice.text, onDismiss: { weeklyReviewNotice = nil })
            }
            DaysCalendarView(store: store) { selection = "journal/\($0).md" }
            MacDayList(days: days ?? [], selection: $selection)
        }
        .weeklyReviewSheet(isPresented: $showsWeeklyReview, store: store) { weeklyReviewNotice = $0 }
        .task(id: DayRangeRequest(from: nil, to: nil, updated: store.lastUpdated)) {
            if let loaded = try? await store.computeDaySummaries() { days = loaded }
        }
    }
}

/// Kişiler / Konumlar list column: manşet with the sort icon, kind tabs, filter and the list.
struct MacEntitiesColumn: View {
    let store: IndexStore
    /// Manşet for a custom kind, which has no sidebar row of its own.
    let sectionTitle: LocalizedStringKey
    @Binding var kind: String
    @Binding var order: EntityOrdering
    @Binding var search: String
    @Binding var selection: String?
    var unseenReveal: UUID? = nil

    var body: some View {
        VStack(spacing: 0) {
            if store.entityTypes.issue != nil {
                Text(
                    "Varlık tipleri okunamıyor. Yalnız yerleşik tipler kullanılıyor. Kasadaki .app/types.json dosyasını kontrol et."
                )
                .font(.ink.meta)
                .foregroundStyle(Color.ink.warning)
                .padding()
            }
            InkPageTitle(title) {
                EntitySortMenu(order: $order)
            }
            .macListColumnTitle()
            EntityTypePicker(store: store, selection: $kind)
                .padding(.horizontal, InkSpacing.margin)
                .padding(.bottom, InkSpacing.section)
            EntityFilterField(search: $search)
                .padding(.horizontal, InkSpacing.margin)
                .padding(.bottom, InkSpacing.section)
            MacEntityList(
                store: store,
                entities: EntityListQuery.entities(
                    in: store.content, usage: store.entityUsage, kind: kind, search: search, order: order),
                showsUnseen: kind == "person", unseenReveal: unseenReveal, selection: $selection)
        }
    }

    /// The manşet follows the kind tab, which can differ from the sidebar row.
    private var title: LocalizedStringKey {
        switch kind {
        case "person": "Kişiler"
        case "place": "Konumlar"
        default: sectionTitle
        }
    }
}

enum MacListColumnChrome {
    /// A Mac list insets its rows by this much; a manşet above the list lines up with them.
    static let rowInset: CGFloat = 8
    /// ``InkPageTitle`` starts 4 pt above an ``InkPageTitleRow`` (the first row of a list);
    /// a column whose manşet is not a list row adds the difference.
    static let titleTopInset: CGFloat = 4
}

extension View {
    /// Puts a stack manşet where the list columns (Görevler, Hedefler) draw theirs.
    func macListColumnTitle() -> some View {
        padding(.leading, MacListColumnChrome.rowInset)
            .padding(.top, MacListColumnChrome.titleTopInset)
    }
}

/// Günlük column. Selection chrome lives here so the day row and its tests share one list.
struct MacDayList: View {
    let days: [DayOverview]
    @Binding var selection: String?

    var body: some View {
        List(days, selection: $selection) { day in
            DayRow(day: day)
                .inkListRow(columnSelected: selection == day.id)
                .tag(day.id)
        }
        .listStyle(.plain)
        .scrollContentBackground(.hidden)
    }
}

/// Kişiler / Konumlar column.
struct MacEntityList: View {
    let store: IndexStore
    let entities: [EntitySummary]
    var showsUnseen: Bool
    var unseenReveal: UUID? = nil
    @Binding var selection: String?

    var body: some View {
        List(selection: $selection) {
            if showsUnseen {
                UnseenPeopleSection(
                    store: store, people: entities, select: { selection = $0.id },
                    initiallyExpanded: unseenReveal != nil
                )
                .id(unseenReveal)
            }
            ForEach(entities) { entity in
                EntityRow(entity: entity)
                    .inkListRow(columnSelected: selection == entity.id)
                    .tag(entity.id)
            }
        }
        .listStyle(.plain)
        .scrollContentBackground(.hidden)
    }
}
