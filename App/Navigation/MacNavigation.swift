#if os(macOS)
    import SwiftUI
    import VaultFormat

    /// Lists stay alongside their selection in the desktop's three columns.
    struct MacNavigation: View {
        let store: IndexStore
        @Environment(IntentNavigation.self) private var intentNavigation
        @Environment(NotificationService.self) private var notifications
        @State private var showingKanban = false
        @State private var showingTimeline = false
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
                    }
                } else if section == .tasks && (showingKanban || showingTimeline) {
                    NavigationSplitView {
                        sidebar
                    } detail: {
                        Group {
                            if showingTimeline {
                                TaskTimelineView(tasks: kanbanTasks, showsFilters: true, openDay: openTaskDay)
                            } else {
                                KanbanView(tasks: kanbanTasks, showsFilters: true, openDay: openTaskDay)
                            }
                        }.toolbar { SearchButton() }
                    }
                } else {
                    standardLayout
                }
            }
            .onChange(of: intentNavigation.todayRequest, initial: true) { _, request in
                guard request != nil else { return }
                detailPath = NavigationPath()
                selectedDay = nil
                selectedTask = nil
                selectedProject = nil
                showingKanban = false
                showingTimeline = false
                selectedGoal = nil
                section = .today
            }
            .onChange(of: notifications.navigationRequest?.id, initial: true) { _, id in
                guard id != nil, let request = notifications.navigationRequest else { return }
                detailPath = NavigationPath()
                selectedProject = nil
                showingKanban = false
                showingTimeline = false
                selectedTask = nil
                selectedDay = nil
                section = request.destination == .tasks ? .tasks : .today
            }
            .onChange(of: store.vaultURL) { _, _ in
                selectedTask = nil
                selectedProject = nil
                showingKanban = false
                showingTimeline = false
                kanbanTasks.clearFilters()
                selectedGoal = nil
            }
            .onChange(of: section) { _, value in
                if value != .tasks {
                    selectedProject = nil
                    showingKanban = false
                    showingTimeline = false
                }
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
                                if item == .tasks {
                                    selectedProject = nil
                                    showingKanban = false
                                    showingTimeline = false
                                    kanbanTasks.section = .upcoming
                                }
                            })
                    if item == .tasks {
                        Button {
                            section = .tasks
                            selectedProject = nil
                            selectedTask = nil
                            showingKanban = true
                            showingTimeline = false
                        } label: {
                            Label("Kanban", systemImage: "rectangle.split.3x1")
                        }
                        .buttonStyle(.plain).padding(.leading)
                        Button {
                            section = .tasks
                            selectedProject = nil
                            selectedTask = nil
                            showingKanban = false
                            showingTimeline = true
                        } label: {
                            Label("Zaman çizelgesi", systemImage: "chart.bar.xaxis")
                        }.buttonStyle(.plain).padding(.leading)
                        ForEach(store.content.projects, id: \.self) { project in
                            Button {
                                showingKanban = false
                                showingTimeline = false
                                section = .tasks
                                selectedTask = nil
                                selectedProject = project
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
        }

        private var standardLayout: some View {
            NavigationSplitView {
                sidebar
            } content: {
                switch section ?? .today {
                case .today, .days:
                    VStack(spacing: 0) {
                        Button("Özetler", systemImage: "chart.bar") { section = .summaries }.padding()
                        DaysCalendarView(store: store) { selectedDay = "journal/\($0).md" }
                        List(store.content.days, selection: $selectedDay) { day in
                            DayRow(day: day).tag(day.id)
                        }
                    }.navigationTitle("Günlük")
                case .tasks:
                    if let project = selectedProject {
                        NavigationStack { ProjectView(store: store, name: project).id(project) }
                    } else {
                        TasksView(
                            store: store, selection: $selectedTask,
                            notificationRequest: notifications.navigationRequest?.destination == .tasks
                                ? notifications.navigationRequest?.id : nil,
                            tasks: kanbanTasks,
                            onKanbanSelected: {
                                showingKanban = true
                                showingTimeline = false
                            },
                            onTimelineSelected: {
                                showingTimeline = true
                                showingKanban = false
                            })
                    }
                case .summaries, .graph, .map: EmptyView()
                case .goals:
                    GoalsView(store: store, selection: $selectedGoal)
                case .people, .places:
                    VStack(spacing: 0) {
                        EntityListControls(order: $entityOrder, search: $entitySearch)
                        let entities = EntityListQuery.entities(
                            in: store.content, usage: store.entityUsage, kind: entityKind,
                            search: entitySearch, order: entityOrder)
                        List(selection: entitySelection) {
                            if entityKind == "person" {
                                UnseenPeopleSection(store: store, people: entities) { entity in
                                    entitySelection.wrappedValue = entity.id
                                }
                            }
                            ForEach(entities) { entity in EntityRow(entity: entity).tag(entity.id) }
                        }
                    }.navigationTitle((section ?? .people).title)
                case .notes:
                    List { EmptyView() }
                        .overlay { Text("Notlar sonraki sürümde").foregroundStyle(.secondary) }
                        .navigationTitle("Notlar")
                }
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
                    case .notes:
                        ContentUnavailableView("Notlar sonraki sürümde", systemImage: "note.text")
                            .toolbar { SearchButton() }
                    }
                }
                .id(section)
            }
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

        private var entityKind: String { section == .places ? "place" : "person" }
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
        case today, days, tasks, people, places, goals, summaries, graph, map, notes
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
            case .notes: "Notlar"
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
            case .notes: "note.text"
            }
        }
    }
#endif
