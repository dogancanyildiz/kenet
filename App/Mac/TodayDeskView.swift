import GoalTracking
import SwiftUI
import VaultFormat

#if os(macOS)
    /// Mac Today detail shell: ``TodayView`` / ``DayView`` content, hour grid, optional 300 pt
    /// panel (or the same sections folded under the grid when the detail is narrow).
    struct TodayDeskView: View {
        let store: IndexStore
        @Environment(IntentNavigation.self) private var intentNavigation: IntentNavigation?
        @Environment(ShellNavigationState.self) private var navigation: ShellNavigationState?
        @Environment(\.locale) private var locale
        @Environment(\.calendar) private var calendar
        @Environment(\.clockNow) private var clockNow

        @State private var tasksModel: DayTasksModel
        @State private var goalModels = GoalDayModelSlot()
        @State private var loadedDay: DaySummary?
        @State private var loadedGoals: (day: CalendarDate, goals: [GoalDefinition], statuses: [String: GoalStatus])?
        @State private var onThisDay: OnThisDayModel
        @State private var closeDayRoute: CloseDayRoute?
        @State private var goalDestination: GoalDetailRoute?
        @State private var detailWidth: CGFloat = 0
        @State private var editingEvent: EventEditorModel?
        @State private var editingTask: TaskEditorModel?
        @State private var deletingEvent: EventRow?
        @State private var deletingTask: TaskRow?

        init(store: IndexStore) {
            self.store = store
            let day = LocalDay.today()
            _tasksModel = State(initialValue: DayTasksModel(store: store, day: day, isToday: true))
            _onThisDay = State(initialValue: OnThisDayModel(store: store))
        }

        var body: some View {
            TimelineView(.periodic(from: .now, by: 60)) { context in
                let today = LocalDay.today(at: context.date)
                desk(now: context.date, today: today)
            }
        }

        @ViewBuilder
        private func desk(now: Date, today: CalendarDate) -> some View {
            let presented = makePresentation(today: today)
            let daySummary = loadedDay?.date == today && tasksModel.isLoaded ? loadedDay : nil
            let plan = makePlan(
                presented: presented, events: daySummary?.events ?? [], now: now)
            let showsPanel = TodayDeskPlan.showsPanel(detailWidth: detailWidth)
            let shownStatuses: [String: GoalStatus] = {
                guard loadedGoals?.day == today, let raw = loadedGoals?.statuses else { return [:] }
                return goalModels.model(store: store, day: today).shownStatuses(raw)
            }()
            let goals = loadedGoals?.day == today ? loadedGoals?.goals ?? [] : []
            let closeLabel = closeDayLabel(presented: presented, day: daySummary)

            HStack(spacing: 0) {
                TodayView(store: store)
                    .environment(
                        \.todayDeskChrome,
                        TodayDeskChrome(
                            hourGrid: AnyView(
                                TodayDeskTimeline(
                                    store: store, plan: plan, day: today, today: today,
                                    onSelectEvent: { openEvent($0, day: today) },
                                    onSelectTask: { openTask($0) }
                                )
                            ),
                            foldedPanel: showsPanel
                                ? nil
                                : AnyView(
                                    TodayDeskPanelSections(
                                        store: store, plan: plan, day: today, goals: goals,
                                        statuses: shownStatuses, onThisDay: onThisDay.entry,
                                        closeDayLabel: closeLabel,
                                        onCloseDay: { closeDayRoute = CloseDayRoute(step: .tasks) },
                                        onOpenGoal: { goalDestination = GoalDetailRoute(goal: $0) },
                                        showsHeader: false
                                    )
                                ),
                            suppressCloseDay: true,
                            suppressQuickEntry: true
                        )
                    )
                if showsPanel {
                    TodayDeskPanel(
                        store: store, plan: plan, day: today, goals: goals,
                        statuses: shownStatuses, onThisDay: onThisDay.entry,
                        closeDayLabel: closeLabel,
                        onCloseDay: { closeDayRoute = CloseDayRoute(step: .tasks) },
                        onOpenGoal: { goalDestination = GoalDetailRoute(goal: $0) }
                    )
                }
            }
            .onGeometryChange(for: CGFloat.self) {
                $0.size.width
            } action: {
                detailWidth = $0
            }
            .safeAreaInset(edge: .bottom) {
                QuickEntryBar(
                    store: store, isEnabled: true, day: nil,
                    focusRequest: intentNavigation?.focusRequest, acceptsPeopleMentions: true,
                    drafts: navigation
                )
                .id("today")
            }
            .navigationDestination(item: $goalDestination) { route in
                GoalDetailView(store: store, goal: route.goal, day: today)
            }
            .sheet(item: $closeDayRoute) { route in
                NavigationStack {
                    CloseDayView(
                        store: store, today: today, tasks: tasksModel.rows ?? [],
                        goals: goalModels.model(store: store, day: today), step: route.step)
                }
                .inkAdaptiveFormPresentation()
            }
            .sheet(item: $editingEvent) { model in
                NavigationStack { EventTextEditor(model: model) }
                    .inkAdaptiveSheetPresentation()
                    .frame(minWidth: 320, minHeight: 200)
            }
            .sheet(item: $editingTask) { model in
                NavigationStack { TaskTextEditor(model: model) }
                    .frame(minWidth: 320, minHeight: 200)
                    .inkAdaptiveSheetPresentation(fitsContent: true)
            }
            .confirmationDialog(
                "Bu olayı silmek istiyor musun?",
                isPresented: Binding(
                    get: { deletingEvent != nil },
                    set: { if !$0 { deletingEvent = nil } }
                ),
                titleVisibility: .visible
            ) {
                Button("Olayı sil", role: .destructive) {
                    if let event = deletingEvent {
                        deletingEvent = nil
                        let model = EventEditorModel(store: store, day: today, row: event)
                        Task {
                            await model.load()
                            if model.target != nil { await model.delete() }
                        }
                    }
                }
                Button("Vazgeç", role: .cancel) { deletingEvent = nil }
            }
            .confirmationDialog(
                "Bu görevi silmek istiyor musun?",
                isPresented: Binding(
                    get: { deletingTask != nil },
                    set: { if !$0 { deletingTask = nil } }
                ),
                titleVisibility: .visible
            ) {
                Button("Görevi sil", role: .destructive) {
                    if let task = deletingTask {
                        deletingTask = nil
                        Task {
                            let model = TaskEditorModel(store: store, row: task)
                            await model.load()
                            if model.target != nil { _ = await model.delete() }
                        }
                    }
                }
                Button("Vazgeç", role: .cancel) { deletingTask = nil }
            }
            .task(id: DayRequest(date: today, updated: store.lastUpdated)) {
                await reloadDay(today: today)
            }
            .task(id: DayRequest(date: today, updated: store.lastUpdated)) {
                await goalModels.model(store: store, day: today).load()
            }
            .task(id: DayTasksRequest(model: ObjectIdentifier(tasksModel), updated: store.lastUpdated)) {
                await tasksModel.load()
            }
            .onChange(of: today) { _, newDay in
                tasksModel = DayTasksModel(store: store, day: newDay, isToday: true)
            }
        }

        private func makePresentation(today: CalendarDate) -> TodayPresentation {
            let goals = loadedGoals?.day == today ? loadedGoals : nil
            let statuses = goals.map {
                goalModels.model(store: store, day: today).shownStatuses($0.statuses)
            }
            return TodayPresentation(
                day: (loadedDay?.date == today ? loadedDay : nil) ?? DaySummary(empty: today),
                groups: tasksModel.groups,
                goals: goals?.goals ?? [],
                goalStatuses: statuses ?? [:],
                goalStatusesDay: goals?.day,
                today: today,
                locale: locale,
                calendar: calendar,
                completedTasks: tasksModel.completedTasksForPresentation,
                completedTaskIDs: tasksModel.completed,
                isCarriedOverExpanded: true,
                isCompletedExpanded: true)
        }

        private func makePlan(presented: TodayPresentation, events: [EventRow], now: Date)
            -> TodayDeskPlan
        {
            let carried = tasksModel.groups.overdue.filter { !$0.isClosed }
            return TodayDeskPlan(
                events: events,
                openTasks: carried + presented.datedTasks + presented.createdTasks,
                carriedOver: carried,
                nowHour: calendar.component(.hour, from: now),
                nowMinute: calendar.component(.minute, from: now),
                taskTime: { DaySchedulePresentation.extractLeadingTime(from: $0.text.plainText) })
        }

        private func closeDayLabel(presented: TodayPresentation, day: DaySummary?) -> String? {
            guard
                CloseDayEntry.isOffered(
                    isToday: true, presentation: presented,
                    hasJournal: day.map(CloseDayEntry.hasJournal) ?? false)
            else { return nil }
            let count = presented.closeDayTaskCount
            if count > 0 {
                return String(localized: "Günü kapat") + " · "
                    + String(localized: "\(count) görev")
            }
            return String(localized: "Günü kapat")
        }

        private func openEvent(_ event: EventRow, day: CalendarDate) {
            editingEvent = EventEditorModel(store: store, day: day, row: event)
        }

        private func openTask(_ task: TaskRow) {
            editingTask = TaskEditorModel(store: store, row: task)
        }

        private func reloadDay(today: CalendarDate) async {
            let goalModel = goalModels.model(store: store, day: today)
            let revision = goalModel.currentRevision()
            async let dayLoad = store.computeDay(on: today)
            async let goalsLoad = store.computeGoalStatuses(today: today)
            async let history: Void = onThisDay.load(today: today)
            let loaded = try? await dayLoad
            let statuses = try? await goalsLoad
            _ = await history
            guard !Task.isCancelled else { return }
            if let loaded { loadedDay = loaded }
            if let statuses {
                loadedGoals = (
                    today, statuses.map(\.definition), TodayPresentation.goalStatuses(statuses)
                )
                goalModel.answerShown(askedAt: revision)
            }
        }
    }
#endif
