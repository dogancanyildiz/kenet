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

        init(store: IndexStore) {
            self.store = store
            _kanbanTasks = State(initialValue: TasksModel(store: store))
        }

        var body: some View {
            Group {
                if section == .summaries || section == .graph || section == .map {
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
                    }
                } else if section == .tasks && (tasksShell.layout == .kanban || tasksShell.layout == .timeline) {
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
                        .toolbar { SearchButton() }
                        .inkPage()
                    }
                } else {
                    standardLayout
                }
            }
            .frame(
                minWidth: InkSpacing.macWindowMinWidth,
                minHeight: InkSpacing.macWindowMinHeight
            )
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
            List(selection: $section) {
                ForEach(DesktopSection.allCases) { item in
                    Label(item.title, systemImage: item.symbol).tag(item)
                        .simultaneousGesture(
                            TapGesture().onEnded {
                                if item == .tasks { tasksEvent(.sidebarTasks) }
                            })
                    if item == .tasks {
                        Button {
                            section = .tasks
                            selectedTask = nil
                            tasksEvent(.sidebarBoard(.kanban))
                        } label: {
                            Label("Kanban", systemImage: "rectangle.split.3x1")
                        }
                        .buttonStyle(.plain).padding(.leading)
                        Button {
                            section = .tasks
                            selectedTask = nil
                            tasksEvent(.sidebarBoard(.timeline))
                        } label: {
                            Label("Zaman çizelgesi", systemImage: "chart.bar.xaxis")
                        }.buttonStyle(.plain).padding(.leading)
                        ForEach(store.content.projects, id: \.self) { project in
                            Button {
                                section = .tasks
                                selectedTask = nil
                                tasksEvent(.sidebarProject(project))
                            } label: {
                                Label {
                                    Text(verbatim: project)
                                } icon: {
                                    Image(systemName: "folder")
                                }
                            }.buttonStyle(.plain).padding(.leading)
                        }
                    }
                }
            }
            .navigationTitle("Journal")
            .navigationSplitViewColumnWidth(
                min: InkSpacing.macSidebarMinWidth, ideal: InkSpacing.macSidebarIdealWidth,
                max: InkSpacing.macSidebarMaxWidth)
        }

        private var standardLayout: some View {
            NavigationSplitView {
                sidebar
            } content: {
                Group {
                    switch section ?? .today {
                    case .today, .days:
                        VStack(spacing: 0) {
                            // List rows sit 8 pt inside the column; the manşet lines up with them.
                            InkPageTitle("Günlük").padding(.leading, 8)
                            Button {
                                section = .summaries
                            } label: {
                                Label("Özetler", systemImage: "chart.bar")
                            }
                            .buttonStyle(InkTextButtonStyle())
                            .padding(.horizontal, InkSpacing.margin)
                            .padding(.vertical, 8)
                            DaysCalendarView(store: store) { selectedDay = "journal/\($0).md" }
                            MacDayList(days: store.content.days, selection: $selectedDay)
                        }.navigationTitle("Günlük")
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
                        VStack(spacing: 0) {
                            if store.entityTypes.issue != nil {
                                Text(
                                    "Varlık tipleri okunamıyor. Yalnız yerleşik tipler kullanılıyor. Kasadaki .app/types.json dosyasını kontrol et."
                                )
                                .font(.ink.meta)
                                .foregroundStyle(Color.ink.warning)
                                .padding()
                            }
                            InkPageTitle(entityColumnTitle) {
                                EntitySortMenu(order: $entityOrder)
                            }
                            .padding(.leading, 8)
                            EntityTypePicker(store: store, selection: $selectedEntityKind)
                                .padding(.horizontal, InkSpacing.margin)
                                .padding(.bottom, InkSpacing.section)
                            EntityFilterField(search: $entitySearch)
                                .padding(.horizontal, InkSpacing.margin)
                                .padding(.bottom, InkSpacing.section)
                            let entities = EntityListQuery.entities(
                                in: store.content, usage: store.entityUsage, kind: entityKind,
                                search: entitySearch, order: entityOrder)
                            MacEntityList(
                                store: store, entities: entities, showsUnseen: entityKind == "person",
                                selection: entitySelection)
                        }
                        .navigationTitle((section ?? .people).title)
                    }
                }
                .inkPage()
                .navigationSplitViewColumnWidth(
                    min: InkSpacing.macListMinWidth, ideal: InkSpacing.macListIdealWidth,
                    max: InkSpacing.macListMaxWidth)
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
                            ContentUnavailableView("Bir gün seç", systemImage: "book.closed")
                                .toolbar { SearchButton() }
                        }
                    case .tasks:
                        if let row = store.content.tasks.first(where: { $0.id == selectedTask }) {
                            TaskDetailView(store: store, row: row) { path in
                                selectedDay = path
                                section = .days
                            }
                        } else {
                            ContentUnavailableView("Bir görev seç", systemImage: "checklist")
                                .toolbar { SearchButton() }
                        }
                    case .summaries, .graph, .map: EmptyView()
                    case .goals:
                        if let goal = store.content.goals.first(where: { $0.id == selectedGoal }) {
                            GoalDetailView(store: store, goal: goal).id(goal.id + (store.vaultURL?.path ?? ""))
                        } else {
                            ContentUnavailableView("Bir hedef seç", systemImage: "target").toolbar { SearchButton() }
                        }
                    case .people, .places:
                        if let entity = selectedSummary, entity.kind == entityKind {
                            EntityView(store: store, entity: entity) { path in
                                selectedEntity = path
                                selectedSummary = store.content.entities.first { $0.id == path } ?? selectedSummary
                            }.id(entityRouteID)
                        } else {
                            ContentUnavailableView("Bir varlık seç", systemImage: "person.2")
                                .toolbar { SearchButton() }
                        }
                    }
                }
                .id(section)
                // Shell paints paper full-width; each page view applies `.inkPageColumn()` itself.
                .inkPage()
            }
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

        /// The column's manşet follows the kind tab, which can differ from the sidebar entry.
        private var entityColumnTitle: LocalizedStringKey {
            switch selectedEntityKind {
            case "person": "Kişiler"
            case "place": "Konumlar"
            default: (section ?? .people).title
            }
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

    private enum DesktopSection: String, CaseIterable, Identifiable {
        case today, days, tasks, people, places, goals, summaries, graph, map
        var id: Self { self }

        var title: LocalizedStringKey {
            switch self {
            case .today: "Bugün"
            case .days: "Günlük"
            case .tasks: "Görevler"
            case .people: "Kişiler"
            case .places: "Konumlar"
            case .goals: "Hedefler"
            case .summaries: "Özetler"
            case .graph: "Graph"
            case .map: "Harita"
            }
        }

        var symbol: String {
            switch self {
            case .today: "sun.max"
            case .days: "book.closed"
            case .tasks: "checklist"
            case .people: "person.2"
            case .places: "mappin.and.ellipse"
            case .goals: "target"
            case .summaries: "chart.bar"
            case .graph: "point.3.connected.trianglepath.dotted"
            case .map: "map"
            }
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
