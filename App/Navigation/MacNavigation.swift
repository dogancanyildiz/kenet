import SwiftUI
import VaultFormat
import VaultIndex
import VaultStore

/// Lists stay alongside their selection in the desktop's three columns. The Mac window, and
/// on iOS the iPhone Duo inner screen (`AdaptiveNavigation`): there the shell shows two
/// columns at a time (``ShellStyle/columnVisibility(layout:width:)``).
struct MacNavigation: View {
    let store: IndexStore
    @Environment(IntentNavigation.self) private var intentNavigation
    @Environment(NotificationService.self) private var notifications
    #if os(macOS)
        @Environment(\.openSearchQuery) private var openSearchQuery
    #endif
    @State private var kanbanTasks: TasksModel
    @State private var navigation: ShellNavigationState
    @State private var sidebarRestoresFocus = false
    @State private var taskSelection = TaskSelectionAnswer()
    /// The sidebar's project rows (`IndexStore.computeProjects()`); a reload keeps them until it answers.
    @State private var sidebarProjects: [String] = []
    #if os(macOS)
        /// The menu bar's "Bugüne git". Made once (``ShellAction``).
        @State private var goToToday: ShellAction
        /// Sidebar searchable text + ⌘F focus action (stable ``ShellAction``).
        @State private var sidebarSearch = SidebarSearchState()
    #endif
    #if os(iOS)
        @State private var columnVisibility = NavigationSplitViewVisibility.automatic
        @State private var shellWidth: CGFloat = 0
        /// Set by the first measurement and kept: the split view is built once and stays.
        @State private var measured = false
    #endif

    init(store: IndexStore, navigation: ShellNavigationState = ShellNavigationState()) {
        self.store = store
        _kanbanTasks = State(initialValue: TasksModel(store: store))
        _navigation = State(initialValue: navigation)
        #if os(macOS)
            _goToToday = State(initialValue: ShellAction { [navigation] in navigation.goToToday(shell: .split) })
        #endif
    }

    var body: some View {
        Group {
            #if os(iOS)
                // No split view before the first measurement: one built earlier opens with the
                // system's own visibility, and its first layout writes that back over the
                // shell's request (an upright 13" iPad lost its sidebar on some cold starts).
                // Built after it, the split view opens with the columns the width asks for.
                if measured {
                    layouts
                } else {
                    Color.ink.paper.ignoresSafeArea()
                }
            #else
                layouts
            #endif
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
                let previous = shellWidth
                shellWidth = width
                resetColumns(from: previous)
                if width > 0 { measured = true }
            }
            .onChange(of: shellLayout) { previous, _ in resetColumns(from: shellWidth, layout: previous) }
            .environment(\.shellTier, ShellTier.resolve(measuredWidth: shellWidth))
        #endif
        .environment(\.shellKind, .split)
        // The pages take their drafts from the bridge.
        .environment(navigation)
        // `initial: true` so a request from before the shell was built is still routed; the
        // bridge tells a shell rebuilt after the request (the Duo closed and opened again) to
        // leave it alone.
        .onChange(of: intentNavigation.todayRequest, initial: true) { _, request in
            guard navigation.claimTodayRequest(request) else { return }
            navigation.detailPath = NavigationPath()
            navigation.selectedDay = nil
            navigation.selectedTask = nil
            tasksEvent(.navigationReset)
            navigation.selectedGoal = nil
            navigation.section = .today
        }
        .onChange(of: notifications.navigationRequest?.id, initial: true) { _, id in
            guard navigation.claimNavigationRequest(id), let request = notifications.navigationRequest else { return }
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
            // Searchable stays on the sidebar child (below), not here: applying it on the shell
            // root republished menu-bar focused values on every rebuild.
            .focusedSceneValue(\.goToToday, goToToday)
            .focusedSceneValue(\.focusSidebarSearch, sidebarSearch.focus)
        #endif
    }

    /// The split view of the current layout: each layout is a split view of its own.
    @ViewBuilder private var layouts: some View {
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
            }
        case .columns:
            standardLayout
        }
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
        #if os(macOS)
            .searchable(
                text: Bindable(sidebarSearch).query,
                isPresented: Bindable(sidebarSearch).isFocused,
                placement: .sidebar, prompt: "Ara"
            )
            .onSubmit(of: .search) { sidebarSearch.submit(openSearchQuery) }
            .accessibilityIdentifier("sidebar.search")
            // Re-apply after searchable so the split view still sees the column width range.
            .macSidebarColumn()
        #endif
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
                    #if os(macOS)
                        TodayDeskView(store: store)
                    #else
                        TodayView(store: store)
                    #endif
                case .days:
                    if let path = navigation.selectedDay,
                        let day = VaultLayout.day(ofDayPath: path)
                    {
                        DayView(
                            store: store, date: day,
                            onReplaceDay: { navigation.selectedDay = TodayDayPath.file(for: $0) },
                            onReturnToToday: { navigation.goToToday(shell: .split) }
                        ).id(day)
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
                    GoalDetailColumn(store: store, goalID: navigation.selectedGoal)
                case .people, .places:
                    if let entity = navigation.selectedSummary, entity.kind == entityKind {
                        EntityView(
                            store: store, entity: entity,
                            onRenamed: { path in
                                navigation.selectedEntity = path
                                navigation.selectedSummary =
                                    store.content.entities.first { $0.id == path } ?? navigation.selectedSummary
                            },
                            // `dismiss()` does nothing in a split view column; the empty state takes over.
                            onDeleted: { navigation.entityDeleted(path: $0) }
                        ).id(navigation.entityRouteID)
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
        }
    }

    #if os(macOS)
        private var windowTitle: Text {
            shellSelection.sidebarEntry?.title ?? Text("Kenet")
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
            resetColumns(from: shellWidth)
        #endif
    }

    #if os(iOS)
        /// `previousWidth`: the width before this change (the same width for a layout switch or a
        /// sidebar choice), so three columns come back only when the tier is entered;
        /// `previousLayout`: the layout before a layout switch, whose visibility is translated.
        private func resetColumns(from previousWidth: CGFloat, layout previousLayout: MacShellLayout? = nil) {
            guard
                let visibility = ShellStyle.columnVisibility(
                    layout: shellLayout, width: shellWidth, previousWidth: previousWidth,
                    previousLayout: previousLayout, current: columnVisibility)
            else { return }
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

#if os(macOS)
    /// Sidebar searchable state: query text, focus flag, and a once-made ⌘F ``ShellAction``.
    @MainActor @Observable
    final class SidebarSearchState {
        var query = ""
        var isFocused = false
        @ObservationIgnored private(set) var focus = ShellAction.nothing

        init() {
            focus = ShellAction { [weak self] in self?.isFocused = true }
        }

        /// Return in the field: a non-empty query opens the search sheet, then the field clears
        /// and gives up focus.
        func submit(_ openQuery: (String) -> Void) {
            let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else { return }
            openQuery(trimmed)
            query = ""
            isFocused = false
        }
    }

    struct TodayNavigationKey: FocusedValueKey {
        typealias Value = ShellAction
    }

    struct SidebarSearchFocusKey: FocusedValueKey {
        typealias Value = ShellAction
    }

    extension FocusedValues {
        /// The menu bar's "Bugüne git"; made once by the shell (``ShellAction``).
        var goToToday: ShellAction? {
            get { self[TodayNavigationKey.self] }
            set { self[TodayNavigationKey.self] = newValue }
        }

        /// Menu bar "Ara" / ⌘F: focuses the sidebar searchable field.
        var focusSidebarSearch: ShellAction? {
            get { self[SidebarSearchFocusKey.self] }
            set { self[SidebarSearchFocusKey.self] = newValue }
        }
    }
#endif
