import GoalTracking
import SwiftUI
import VaultFormat

#if os(macOS)
    /// Mac Today detail: hour-grid desk + optional 300 pt "Bugün" panel. Built beside D4's
    /// `DayView` / `TodayView`; after D4 merges, swap the Mac `.today` detail to this (or fold
    /// D4's header/week-strip helpers into it). Do not edit `DayView.swift` from D7.
    struct TodayDeskView: View {
        let store: IndexStore
        @Environment(IntentNavigation.self) private var intentNavigation: IntentNavigation?
        @Environment(NotificationService.self) private var notifications
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
        @State private var isCarriedOverExpanded = false
        @State private var isCompletedExpanded = false

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
            .accessibilityIdentifier("screen.today")
        }

        @ViewBuilder
        private func desk(now: Date, today: CalendarDate) -> some View {
            let presented = makePresentation(today: today)
            let daySummary = loadedDay?.date == today && tasksModel.isLoaded ? loadedDay : nil
            let plan = makePlan(
                presented: presented, events: daySummary?.events ?? [], now: now)
            let showsPanel = TodayDeskPlan.showsPanel(detailWidth: detailWidth)
            let goalModel = goalModels.model(store: store, day: today)

            HStack(spacing: 0) {
                deskColumn(
                    presented: presented, plan: plan, today: today, daySummary: daySummary,
                    showsPanel: showsPanel)
                if showsPanel {
                    TodayDeskPanel(
                        store: store,
                        plan: plan,
                        day: today,
                        goals: loadedGoals?.day == today ? loadedGoals?.goals ?? [] : [],
                        statuses: loadedGoals?.day == today ? loadedGoals?.statuses ?? [:] : [:],
                        onThisDay: onThisDay.entry,
                        closeDayLabel: closeDayLabel(presented: presented, day: daySummary),
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
            .inkPage()
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
                        goals: goalModel, step: route.step)
                }
                .inkAdaptiveFormPresentation()
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
                isCarriedOverExpanded = false
                isCompletedExpanded = false
            }
            .onChange(of: notifications.navigationRequest?.id, initial: true) { _, _ in
                openCloseDayFromReminder(today: today, goalModel: goalModel)
            }
            .preference(
                key: GoalsStripReadyKey.self,
                value: goalModel.hasLoaded && !goalModel.isLoading)
        }

        private func deskColumn(
            presented: TodayPresentation, plan: TodayDeskPlan, today: CalendarDate,
            daySummary: DaySummary?, showsPanel: Bool
        ) -> some View {
            ScrollView {
                VStack(alignment: .leading, spacing: InkSpacing.section) {
                    header(presented: presented, today: today)
                    summary(presented: presented)
                    TodayDeskTimeline(store: store, plan: plan, day: today, today: today)
                    journalCard(today: today, daySummary: daySummary)
                    if !showsPanel, let label = closeDayLabel(presented: presented, day: daySummary) {
                        Button {
                            closeDayRoute = CloseDayRoute(step: .tasks)
                        } label: {
                            Text(verbatim: label)
                                .font(.ink.byline.weight(.semibold))
                                .foregroundStyle(Color.ink.accent)
                        }
                        .buttonStyle(.plain)
                        .accessibilityIdentifier("button.closeDay")
                    }
                }
                .padding(.horizontal, InkSpacing.margin)
                .padding(.top, 8)
                .padding(.bottom, 8)
                .inkPageColumn()
            }
            .inkGlow()
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }

        private func header(presented: TodayPresentation, today: CalendarDate) -> some View {
            let total = max(1, presented.goalCount)
            let done = presented.completedGoalCount
            let progress = Double(done) / Double(total)
            return InkDayHeader(
                date: LocalDay.instant(for: today),
                progress: presented.goalCount == 0 ? 1 : progress,
                remainingCount: presented.remainingGoalCount
            )
        }

        private func summary(presented: TodayPresentation) -> some View {
            // D4's InkSummaryLine greeting lands with that PR; until then the existing byline.
            Group {
                if let byline = presented.byline {
                    Text(verbatim: byline)
                        .font(.ink.byline)
                        .foregroundStyle(Color.ink.secondaryText)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
        }

        private func journalCard(today: CalendarDate, daySummary: DaySummary?) -> some View {
            VStack(alignment: .leading, spacing: 8) {
                SectionHeader(title: String(localized: "Günlük yazısı"))
                NavigationLink {
                    JournalView(store: store, date: today)
                } label: {
                    InkCard {
                        DayJournalPreview(isLoaded: daySummary != nil, preview: daySummary?.preview)
                    }
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Günlük yazısını düzenle")
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
                isCarriedOverExpanded: isCarriedOverExpanded,
                isCompletedExpanded: isCompletedExpanded)
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
                nowMinute: calendar.component(.minute, from: now))
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

        private func openCloseDayFromReminder(today: CalendarDate, goalModel: GoalDayModel) {
            guard store.lastUpdated != nil, tasksModel.isCurrent, goalModel.isCurrent,
                CloseDayReminder.claim(notifications.navigationRequest?.closeDayRequestID)
            else { return }
            closeDayRoute = CloseDayRoute(step: .journal)
        }
    }
#endif
