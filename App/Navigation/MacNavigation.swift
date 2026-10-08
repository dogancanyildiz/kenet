#if os(macOS)
    import SwiftUI
    import VaultFormat

    /// Lists stay alongside their selection in the desktop's three columns.
    struct MacNavigation: View {
        let store: IndexStore
        @Environment(IntentNavigation.self) private var intentNavigation
        @Environment(NotificationService.self) private var notifications
        @State private var kanbanTasks: TasksModel
        @State private var detailPath = NavigationPath()
        @State private var section: DesktopSection? = .today
        @State private var selectedGoal: String?
        @State private var selectedProject: String?
        @State private var selectedTask: String?
        @State private var selectedDay: String?
        @State private var selectedEntity: String?
        @State private var selectedSummary: EntitySummary?
        @State private var entityRouteID = UUID()
        @State private var entityOrder = EntityOrdering.name
        @State private var entitySearch = ""
        @State private var selectedEntityKind = "person"
        @State private var sidebarRestoresFocus = false

        init(store: IndexStore) {
            self.store = store
            _kanbanTasks = State(initialValue: TasksModel(store: store))
        }

        var body: some View {
            Group {
                switch shellLayout {
                case .page:
                    NavigationSplitView {
                        sidebar
                    } detail: {
                        NavigationStack {
                            if section == .graph {
                                GraphView(store: store)
                            } else if section == .map {
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
                    NavigationSplitView {
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
            // The page name is the serif manşet inside the page; the toolbar repeats nothing.
            // The window keeps a title (Window menu, Mission Control): the selected sidebar row.
            .navigationTitle(windowTitle)
            .toolbar(removing: .title)
            .macMainWindowMinimumSize()
            .onChange(of: intentNavigation.todayRequest, initial: true) { _, request in
                guard request != nil else { return }
                detailPath = NavigationPath()
                selectedDay = nil
                selectedTask = nil
                tasksEvent(.navigationReset)
                selectedGoal = nil
                section = .today
            }
            .onChange(of: notifications.navigationRequest?.id, initial: true) { _, id in
                guard id != nil, let request = notifications.navigationRequest else { return }
                detailPath = NavigationPath()
                tasksEvent(.navigationReset)
                selectedTask = nil
                selectedDay = nil
                section = request.destination == .tasks ? .tasks : .today
            }
            .onChange(of: store.vaultURL) { _, _ in
                selectedTask = nil
                tasksEvent(.vaultChanged)
                kanbanTasks.clearFilters()
                selectedGoal = nil
            }
            .onChange(of: section) { _, value in
                if value == .people || value == .places { selectedEntityKind = value == .places ? "place" : "person" }
                if value != .tasks { tasksEvent(.sectionLeft) }
            }
            .onChange(of: store.content.projects) { _, projects in
                var selection = shellSelection
                selection.projectsChanged(projects)
                apply(selection)
            }
            .onChange(of: selectedDay) { _, value in
                if value != nil { section = .days }
            }
            .focusedSceneValue(
                \.goToToday,
                {
                    section = .today
                    selectedDay = nil
                })
        }

        private var sidebar: some View {
            MacSidebarList(
                entries: MacSidebar.entries(projects: store.content.projects),
                selection: Binding(
                    get: { shellSelection.sidebarEntry },
                    set: { entry in if let entry { selectSidebarEntry(entry) } }),
                // A click on the selected "Görevler" row still returns the list to its first section.
                onClick: { entry in if entry == .section(.tasks) { tasksEvent(.sidebarTasks) } },
                restoresFocus: $sidebarRestoresFocus
            )
        }

        private var standardLayout: some View {
            NavigationSplitView {
                sidebar
            } content: {
                Group {
                    switch section ?? .today {
                    case .today, .days:
                        MacDaysColumn(store: store, selection: $selectedDay) { section = .summaries }
                    case .tasks:
                        if let project = selectedProject {
                            NavigationStack { ProjectView(store: store, name: project).id(project) }
                        } else {
                            TasksView(
                                store: store, selection: $selectedTask,
                                notificationRequest: notifications.navigationRequest?.destination == .tasks
                                    ? notifications.navigationRequest?.id : nil,
                                tasks: kanbanTasks)
                        }
                    case .summaries, .graph, .map: EmptyView()
                    case .goals:
                        GoalsView(store: store, selection: $selectedGoal)
                    case .people, .places:
                        MacEntitiesColumn(
                            store: store, sectionTitle: (section ?? .people).title, kind: $selectedEntityKind,
                            order: $entityOrder, search: $entitySearch, selection: entitySelection)
                    }
                }
                .inkPage()
                .macListColumn()
            } detail: {
                NavigationStack(path: $detailPath) {
                    switch section ?? .today {
                    case .today:
                        TodayView(store: store)
                    case .days:
                        if let path = selectedDay,
                            let day = CalendarDate(String(path.dropFirst("journal/".count).dropLast(3)))
                        {
                            DayView(store: store, date: day).id(day)
                        } else {
                            MacEmptyDetail("Bir gün seç")
                        }
                    case .tasks:
                        if let row = store.content.tasks.first(where: { $0.id == selectedTask }) {
                            TaskDetailView(store: store, row: row) { path in
                                selectedDay = path
                                section = .days
                            }
                        } else {
                            MacEmptyDetail("Bir görev seç")
                        }
                    case .summaries, .graph, .map: EmptyView()
                    case .goals:
                        if let goal = store.content.goals.first(where: { $0.id == selectedGoal }) {
                            GoalDetailView(store: store, goal: goal).id(goal.id + (store.vaultURL?.path ?? ""))
                        } else {
                            MacEmptyDetail("Bir hedef seç")
                        }
                    case .people, .places:
                        if let entity = selectedSummary, entity.kind == entityKind {
                            EntityView(store: store, entity: entity) { path in
                                selectedEntity = path
                                selectedSummary = store.content.entities.first { $0.id == path } ?? selectedSummary
                            }.id(entityRouteID)
                        } else {
                            MacEmptyDetail("Bir varlık seç")
                        }
                    }
                }
                .id(section)
                // Shell paints paper full-width; each page view applies `.inkPageColumn()` itself.
                // An empty branch stretches over the column (`MacEmptyDetail`); otherwise this
                // paper is only as large as the prompt and the stack's system white (dark: gray)
                // shows around it.
                .inkPage()
                .macSearchToolbar()
            }
        }

        private var windowTitle: Text {
            shellSelection.sidebarEntry?.title ?? Text("Journal")
        }

        private var shellLayout: MacShellLayout { shellSelection.layout }

        private var shellSelection: MacShellSelection {
            MacShellSelection(section: section, tasks: tasksShell)
        }

        private func apply(_ selection: MacShellSelection) {
            if kanbanTasks.viewState != selection.tasks.view { kanbanTasks.viewState = selection.tasks.view }
            if selectedProject != selection.tasks.project { selectedProject = selection.tasks.project }
            if section != selection.section { section = selection.section }
        }

        /// Called for a choice made in the sidebar (click, arrow key or VoiceOver).
        private func selectSidebarEntry(_ entry: MacSidebarEntry) {
            var selection = shellSelection
            let restoresFocus = selection.select(entry)
            if entry.isNested { selectedTask = nil }
            apply(selection)
            if restoresFocus { sidebarRestoresFocus = true }
        }

        /// Tasks layout (list column, full-width board, project) comes from the shared view
        /// state alone; the sidebar and the tabs in the content area write the same value.
        private var tasksShell: TasksShellState {
            TasksShellState(view: kanbanTasks.viewState, project: selectedProject)
        }

        private func tasksEvent(_ event: TasksShellState.Event) {
            var shell = tasksShell
            shell.handle(event)
            if kanbanTasks.viewState != shell.view { kanbanTasks.viewState = shell.view }
            if selectedProject != shell.project { selectedProject = shell.project }
        }

        private func openTaskDay(_ path: String) {
            selectedDay = path
            section = .days
        }

        private var entitySelection: Binding<String?> {
            Binding(
                get: { selectedEntity },
                set: { path in
                    selectedEntity = path
                    selectedSummary = store.content.entities.first { $0.id == path }
                    entityRouteID = UUID()
                })
        }

        private var entityKind: String { selectedEntityKind }
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

    struct TodayNavigationKey: FocusedValueKey {
        typealias Value = () -> Void
    }

    extension FocusedValues {
        var goToToday: (() -> Void)? {
            get { self[TodayNavigationKey.self] }
            set { self[TodayNavigationKey.self] = newValue }
        }
    }

    /// Günlük list column: manşet, the Özetler link under it, the month and the days.
    struct MacDaysColumn: View {
        let store: IndexStore
        @Binding var selection: String?
        let openSummaries: () -> Void

        var body: some View {
            VStack(spacing: 0) {
                InkPageTitle("Günlük").macListColumnTitle()
                Button(action: openSummaries) {
                    Label("Özetler", systemImage: "chart.bar")
                }
                .buttonStyle(InkTextButtonStyle())
                // Starts where the manşet above it starts.
                .padding(.leading, InkSpacing.margin + MacListColumnChrome.rowInset)
                .padding(.vertical, 8)
                .frame(maxWidth: .infinity, alignment: .leading)
                DaysCalendarView(store: store) { selection = "journal/\($0).md" }
                MacDayList(days: store.content.days, selection: $selection)
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
                    showsUnseen: kind == "person", selection: $selection)
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
        let days: [DaySummary]
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
        @Binding var selection: String?

        var body: some View {
            List(selection: $selection) {
                if showsUnseen {
                    UnseenPeopleSection(store: store, people: entities) { entity in
                        selection = entity.id
                    }
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
#endif
