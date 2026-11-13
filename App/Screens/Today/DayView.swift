import GoalTracking
import Summaries
import SwiftUI
import VaultFormat

/// The same editable layout serves today and a selected historical day.
struct DayView: View {
    let store: IndexStore
    let date: CalendarDate
    var isToday = false
    /// Past-day host replaces the shown day without pushing (week strip / Mac Days).
    var onReplaceDay: ((CalendarDate) -> Void)? = nil
    /// Past-day host returns to Today root (`isToday: true`).
    var onReturnToToday: (() -> Void)? = nil
    // Optional: hosted tests build the screen without the app's navigation object.
    @Environment(IntentNavigation.self) var intentNavigation: IntentNavigation?
    @Environment(NotificationService.self) var notifications
    @Environment(CalendarService.self) var calendar
    @Environment(\.locale) var locale
    @Environment(\.calendar) var calendarValue
    @Environment(\.clockNow) var clockNow
    @Environment(\.openSettings) var openSettings
    @Environment(\.displayScale) var displayScale
    @Environment(\.inkMastheadPlacement) var mastheadPlacement
    @Environment(\.horizontalSizeClass) var horizontalSizeClass
    @Environment(\.scenePhase) var scenePhase
    /// The shell's bridge: the diary editor's presence and the drafts live there, so a shell
    /// rebuilt by the iPhone Duo shows the same page with the same text. Nil when the page is
    /// hosted without a shell (tests).
    @Environment(ShellNavigationState.self) var navigation: ShellNavigationState?
    #if os(macOS)
        @Environment(\.todayDeskChrome) var todayDeskChrome: TodayDeskChrome?
    #endif
    @State var showsDiary = false
    /// On screen (`onAppear`): a page in another tab or under a pushed page is not, and leaves
    /// the diary editor route to the page the user sees.
    @State var isVisible = false
    @State var closeDayRoute: CloseDayRoute?
    @State var tasksModel: DayTasksModel
    @State var isCarriedOverExpanded = false
    @State var isCompletedExpanded = false
    @State var isTasksExpanded = false
    /// Nil until the first query returns; a reload keeps the previous day until then.
    @State var loadedDay: DaySummary?
    /// The request the page's main load last finished for (``DayPageReadyKey``).
    @State var loadedRequest: DayRequest?
    /// Goal definitions and statuses as of the day they were queried for, loaded with the day.
    @State var loadedGoals: (day: CalendarDate, goals: [GoalDefinition], statuses: [String: GoalStatus])?
    @State var goalModels = GoalDayModelSlot()
    /// A goal page pushed from the strip, on this page's stack (the Today tab's on iPhone, the
    /// detail column's on the Mac).
    @State var goalDestination: GoalDetailRoute?
    /// Whether the day's own graph has a node besides the day, as of the day it was queried for.
    @State var dayGraph: (date: CalendarDate, isOffered: Bool)?
    @State var showsDayGraph = false
    @State var weekDestination: CalendarDate?
    /// Past-day schedule state: month picker, selected timeline card, and editors for events and
    /// tasks on the schedule.
    @State var showsMonthPicker = false
    /// The schedule card's leading icon box (the drawing's 32 pt square).
    @ScaledMetric(relativeTo: .body) var scheduleIconBox: CGFloat = 32
    /// The pinned manşet's small ring (the drawing's 30 pt).
    @ScaledMetric(relativeTo: .body) var compactRingSide: CGFloat = 30
    @State var selectedScheduleItemID: String?
    @State var editingScheduleEvent: EventEditorModel?
    @State var deletingScheduleEvent: EventRow?
    @State var editingScheduleTask: TaskEditorModel?
    @State var deletingScheduleTask: TaskRow?
    @State var scheduleLinkDestination: EntityLinkDestination?
    @State var writtenDays: Set<Date> = []
    @State var weekEventCounts: [Date: Int] = [:]
    @State var insightChips: [TodayInsightChip] = []
    @State var chipEntityDestination: EntitySummary?
    @State var isHeaderCompact = false
    /// Visible scroll height between the top safe area and the bottom chrome (fold budget).
    @State var viewportHeight: CGFloat = 550
    /// Bumped to the injected clock when the scene becomes active so the greeting tracks the
    /// hour. Starts in the distant past, not at the wall clock: `clockNow` alone decides the
    /// first greeting, so a frozen clock (previews, references) is never overridden by `Date()`.
    @State var greetingTick = Date.distantPast

    init(
        store: IndexStore, date: CalendarDate, isToday: Bool = false,
        onReplaceDay: ((CalendarDate) -> Void)? = nil,
        onReturnToToday: (() -> Void)? = nil
    ) {
        self.store = store
        self.date = date
        self.isToday = isToday
        self.onReplaceDay = onReplaceDay
        self.onReturnToToday = onReturnToToday
        _tasksModel = State(initialValue: DayTasksModel(store: store, day: date, isToday: isToday))
    }

    /// The queried day, once it is this date's. Until then the day's own sections are not drawn,
    /// so the page never shows an empty day that is still loading.
    var day: DaySummary? { loadedDay?.date == date && tasksModel.isLoaded ? loadedDay : nil }

    /// Mac desk shell draws "Günü kapat" in the panel / folded block.
    var showsInlineCloseDay: Bool {
        #if os(macOS)
            todayDeskChrome == nil
        #else
            true
        #endif
    }

    var foldsOpenTasks: Bool {
        guard isToday else { return false }
        #if os(macOS)
            return false
        #else
            return horizontalSizeClass != .regular
        #endif
    }

    private func makePresentation() -> TodayPresentation {
        let today = isToday ? date : LocalDay.today(at: clockNow())
        let goals = loadedGoals?.day == date ? loadedGoals : nil
        // A goal marked on this page counts from the strip's model until an answer has the mark.
        let statuses = goals.map { goalModels.model(store: store, day: date).shownStatuses($0.statuses) }
        let greeting: TodayGreeting? =
            isToday
            ? TodayGreeting.resolve(date: max(clockNow(), greetingTick), calendar: calendarValue)
            : nil
        return TodayPresentation(
            day: day ?? DaySummary(empty: date), groups: tasksModel.groups, goals: goals?.goals ?? [],
            goalStatuses: statuses ?? [:], goalStatusesDay: goals?.day, today: today, locale: locale,
            calendar: calendarValue,
            completedTasks: tasksModel.completedTasksForPresentation,
            completedTaskIDs: tasksModel.completed,
            isCarriedOverExpanded: isCarriedOverExpanded, isCompletedExpanded: isCompletedExpanded,
            isTasksExpanded: isTasksExpanded, foldsOpenTasks: foldsOpenTasks,
            foldViewportHeight: viewportHeight,
            calendarEventCount: calendar.events(on: date).count,
            greeting: greeting)
    }

    var body: some View {
        let presented = makePresentation()
        let goalModel = goalModels.model(store: store, day: date)
        let entitiesByID = InkLinkMapping.entityIndex(store.content.entities)
        let day = self.day
        let isEmptyDay =
            day.map { $0.events.isEmpty && $0.diary.isEmpty && !$0.hasGoalRecords } == true
            && tasksModel.groups.isEmpty && presented.completedTaskCount == 0
        let deskPlan = makeDeskPlan(presented: presented, day: day)
        return withPastDaySheets(
            mainScrollPage(
                presented: presented, goalModel: goalModel, entitiesByID: entitiesByID,
                day: day, isEmptyDay: isEmptyDay, deskPlan: deskPlan)
        )
    }

    /// Mac Today desk only: today's records split between the hour grid and the page, from the
    /// page's own loaded day and tasks. Nil everywhere else (iPhone, iPad, past days).
    private func makeDeskPlan(presented: TodayPresentation, day: DaySummary?) -> TodayDeskPlan? {
        #if os(macOS)
            guard isToday, todayDeskChrome != nil else { return nil }
            let now = clockNow()
            let carried = tasksModel.groups.overdue.filter { !$0.isClosed }
            return TodayDeskPlan(
                events: day?.events ?? [],
                openTasks: carried + presented.datedTasks + presented.createdTasks,
                carriedOver: carried,
                nowHour: calendarValue.component(.hour, from: now),
                nowMinute: calendarValue.component(.minute, from: now),
                completedTasks: presented.completedTasksOfDay, day: date)
        #else
            return nil
        #endif
    }

    private func mainScrollPage(
        presented: TodayPresentation, goalModel: GoalDayModel,
        entitiesByID: [String: EntitySummary], day: DaySummary?, isEmptyDay: Bool,
        deskPlan: TodayDeskPlan?
    ) -> some View {
        let todayInstant = LocalDay.instant(
            for: isToday ? date : LocalDay.today(at: clockNow()),
            timeZone: calendarValue.timeZone)
        return ScrollView {
            if isToday {
                todayScrollContent(
                    presented: presented, goalModel: goalModel, entitiesByID: entitiesByID,
                    day: day, isEmptyDay: isEmptyDay, todayInstant: todayInstant,
                    deskPlan: deskPlan)
            } else {
                pastDayScrollContent(
                    presented: presented, goalModel: goalModel, entitiesByID: entitiesByID,
                    day: day, isEmptyDay: isEmptyDay, todayInstant: todayInstant)
            }
        }
        // Measured inside the scroll view's insets: the tab bar, the quick-entry shelf and the
        // home indicator are already out, so the budget does not subtract chrome a second time.
        .onScrollGeometryChange(for: CGFloat.self) { geometry in
            geometry.containerSize.height - geometry.contentInsets.top - geometry.contentInsets.bottom
        } action: { _, height in
            if height > 0 { viewportHeight = height }
        }
        .onScrollGeometryChange(for: CGFloat.self) { geometry in
            geometry.contentOffset.y + geometry.contentInsets.top
        } action: { _, offset in
            if isHeaderCompact {
                if offset < 20 { isHeaderCompact = false }
            } else if offset > 28 {
                isHeaderCompact = true
            }
        }
        .safeAreaInset(edge: .top, spacing: 0) {
            // Today only: a past day keeps the navigation bar's title while it scrolls.
            if isToday && mastheadPlacement == .scrolled && isHeaderCompact {
                todayCompactHeader(presented)
                    .padding(.horizontal, InkSpacing.margin)
                    .padding(.top, 4)
                    .padding(.bottom, 6)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .inkPageColumn()
                    // The drawing's pinned row ends on a hairline over the page.
                    .overlay(alignment: .bottom) {
                        Rectangle()
                            .fill(Color.ink.rule)
                            .frame(height: InkStroke.hairline(scale: displayScale))
                            .accessibilityHidden(true)
                    }
                    .background(Color.ink.paper)
            }
        }
        // The stack's own top pad stays under the pinned strip: the gap below the manşet is the same.
        .inkPinnedMasthead(
            mastheadBlock(presented, todayInstant: todayInstant),
            insets: EdgeInsets(top: 8, leading: InkSpacing.margin, bottom: 0, trailing: InkSpacing.margin)
        )
        .inkPage()
        .modifier(TodayDeskColumns(panel: deskPanel(presented: presented, goalModel: goalModel, deskPlan: deskPlan)))
        .safeAreaInset(edge: .bottom) {
            #if os(macOS)
                if todayDeskChrome == nil {
                    QuickEntryBar(
                        store: store, isEnabled: true, day: isToday ? nil : date,
                        focusRequest: isToday ? intentNavigation?.focusRequest : nil,
                        acceptsPeopleMentions: isToday, drafts: navigation
                    )
                    .id(isToday ? "today" : date.description)
                }
            #else
                QuickEntryBar(
                    store: store, isEnabled: true, day: isToday ? nil : date,
                    focusRequest: isToday ? intentNavigation?.focusRequest : nil, acceptsPeopleMentions: isToday,
                    drafts: navigation
                )
                .id(isToday ? "today" : date.description)
            #endif
        }
        // Today is a root screen: same modifiers as `inkRootPageNavigationTitle`, kept
        // conditional because a past day is a pushed page that needs the bar's back button.
        .inkPageNavigationTitle(verbatim: presented.headline)
        #if os(iOS)
            // A past day leaves the bar to its subpage chrome: in the tab shell the navigation
            // row (``InkNavigationRow``) hides it; an `.automatic` here would bring it back.
            .modifier(TodayHiddenBar(isToday: isToday))
        #endif
        .accessibilityIdentifier(isToday ? "screen.today" : "screen.day")
        // The strip draws nothing until its model has the goals; hosts wait for this, goals or none.
        .preference(key: GoalsStripReadyKey.self, value: goalModel.hasLoaded && !goalModel.isLoading)
        .preference(
            key: DayPageReadyKey.self,
            value: loadedRequest == DayRequest(date: date, updated: store.lastUpdated)
                && tasksModel.isCurrent
        )
        .task(id: date) {
            if AppLaunchPolicy.allowsCalendarLoad() { await calendar.load(date) }
        }
        .task(id: DayRequest(date: date, updated: store.lastUpdated)) {
            // One load: the day and its goal statuses as of that day are taken together.
            let request = DayRequest(date: date, updated: store.lastUpdated)
            let goalModel = goalModels.model(store: store, day: date)
            let revision = goalModel.currentRevision()
            async let day = store.computeDay(on: date)
            async let goals = store.computeGoalStatuses(today: date)
            async let graph = store.computeDayGraphInput(on: date)
            let loaded = try? await day
            let statuses = try? await goals
            let graphInput = try? await graph
            guard !Task.isCancelled else { return }
            if let loaded { loadedDay = loaded }
            if let graphInput { dayGraph = (date, DayGraphEntry.isOffered(graphInput, on: date)) }
            if let statuses {
                loadedGoals = (date, statuses.map(\.definition), TodayPresentation.goalStatuses(statuses))
                goalModel.answerShown(askedAt: revision)
            }
            await loadWeekAndChips(
                goals: statuses?.map(\.definition) ?? [],
                statuses: statuses.map(TodayPresentation.goalStatuses) ?? [:])
            guard !Task.isCancelled else { return }
            loadedRequest = request
        }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active { greetingTick = clockNow() }
        }
        // The strip's goals and history, for the page's day and publish.
        .task(id: DayRequest(date: date, updated: store.lastUpdated)) {
            await goalModels.model(store: store, day: date).load()
        }
        .task(id: DayTasksRequest(model: ObjectIdentifier(tasksModel), updated: store.lastUpdated)) {
            await tasksModel.load()
        }
        .onChange(of: date) { _, newDate in
            selectedScheduleItemID = nil
            tasksModel = DayTasksModel(store: store, day: newDate, isToday: isToday)
            isCarriedOverExpanded = false
            isCompletedExpanded = false
            isTasksExpanded = false
        }
        .navigationDestination(isPresented: $showsDayGraph) {
            GraphView(store: store, scope: .day(date))
                .modifier(DayBackTitle(title: isToday ? nil : backTitle))
        }
        .navigationDestination(item: $goalDestination) { route in
            // As the Goals list opens it: the page's own day is today.
            GoalDetailView(
                store: store, goal: route.goal, day: LocalDay.today(at: clockNow()),
                focusesAmount: route.focusesAmount, amountDay: route.amountDay
            )
            .modifier(DayBackTitle(title: isToday ? nil : backTitle))
        }
        .navigationDestination(item: $weekDestination) { day in
            DayView(
                store: store, date: day,
                onReplaceDay: { weekDestination = $0 },
                onReturnToToday: {
                    weekDestination = nil
                    navigation?.todayPath = NavigationPath()
                }
            )
            .modifier(DayBackTitle(title: isToday ? nil : backTitle))
        }
        .navigationDestination(item: $chipEntityDestination) { entity in
            EntityView(store: store, entity: entity)
                .modifier(DayBackTitle(title: isToday ? nil : backTitle))
        }
        .onAppear { isVisible = true }
        .onDisappear { isVisible = false }
        .sheet(isPresented: diaryPresented) {
            NavigationStack { DiaryView(store: store, date: date) }
        }
        .sheet(item: $closeDayRoute) { route in
            NavigationStack {
                CloseDayView(
                    store: store, today: date, tasks: tasksModel.rows ?? [],
                    goals: goalModels.model(store: store, day: date), step: route.step,
                    summary: CloseDaySummary(
                        events: presented.eventCount,
                        completedTasks: presented.completedTaskCount,
                        remainingTasks: presented.closeDayTaskCount))
            }
            .inkAdaptiveFormPresentation()
        }
        .onChange(of: notifications.navigationRequest?.id, initial: true) { openCloseDayFromReminder() }
        .onChange(of: store.lastUpdated == nil) { openCloseDayFromReminder() }
        .onChange(of: tasksModel.isCurrent) { openCloseDayFromReminder() }
        .onChange(of: goalModel.isCurrent) { openCloseDayFromReminder() }
    }

    private func withPastDaySheets(_ content: some View) -> some View {
        content
            .sheet(isPresented: $showsMonthPicker) {
                NavigationStack {
                    ScrollView {
                        DaysCalendarView(
                            store: store, selected: date, initialMonth: date, style: .card
                        ) { picked in
                            showsMonthPicker = false
                            handleWeekDay(picked, today: LocalDay.today(at: clockNow()))
                        }
                        .padding(InkSpacing.margin)
                    }
                    .inkPage()
                    .inkSheet("Ay seç", onClose: { showsMonthPicker = false })
                }
                .inkAdaptiveFormPresentation()
            }
            .sheet(item: $editingScheduleEvent) { model in
                NavigationStack { EventTextEditor(model: model) }
                    .inkAdaptiveSheetPresentation()
                    .frame(minWidth: 320, minHeight: 200)
            }
            .sheet(item: $editingScheduleTask) { model in
                NavigationStack { TaskTextEditor(model: model) }
                    .frame(minWidth: 320, minHeight: 200)
                    .inkAdaptiveSheetPresentation(fitsContent: true)
            }
            .confirmationDialog(
                "Bu olayı silmek istiyor musun?",
                isPresented: Binding(
                    get: { deletingScheduleEvent != nil },
                    set: { if !$0 { deletingScheduleEvent = nil } }
                ),
                titleVisibility: .visible
            ) {
                Button("Olayı sil", role: .destructive) {
                    if let event = deletingScheduleEvent {
                        deletingScheduleEvent = nil
                        let model = EventEditorModel(store: store, day: date, row: event)
                        Task {
                            await model.load()
                            if model.target != nil { await model.delete() }
                        }
                    }
                }
                Button("Vazgeç", role: .cancel) { deletingScheduleEvent = nil }
            }
            .confirmationDialog(
                "Bu görevi silmek istiyor musun?",
                isPresented: Binding(
                    get: { deletingScheduleTask != nil },
                    set: { if !$0 { deletingScheduleTask = nil } }
                ),
                titleVisibility: .visible
            ) {
                Button("Görevi sil", role: .destructive) {
                    if let task = deletingScheduleTask {
                        deletingScheduleTask = nil
                        Task {
                            let model = TaskEditorModel(store: store, row: task)
                            await model.load()
                            if model.target != nil { _ = await model.delete() }
                        }
                    }
                }
                Button("Vazgeç", role: .cancel) { deletingScheduleTask = nil }
            }
            .entityLinkSheet($scheduleLinkDestination, store: store)
    }

    private func loadWeekAndChips(goals: [GoalDefinition], statuses: [String: GoalStatus]) async {
        let weekDays = TodayWeekStripMath.daysInWeek(
            containing: LocalDay.instant(for: date, timeZone: calendarValue.timeZone),
            calendar: calendarValue)
        let first = weekDays.first.map { LocalDay.today(at: $0, timeZone: calendarValue.timeZone) }
        let last = weekDays.last.map { LocalDay.today(at: $0, timeZone: calendarValue.timeZone) }
        if let first, let last {
            let overviews = (try? await store.computeDaySummaries(from: first, to: last)) ?? []
            guard !Task.isCancelled else { return }
            var written: Set<Date> = []
            var counts: [Date: Int] = [:]
            for overview in overviews {
                let instant = LocalDay.instant(for: overview.date, timeZone: calendarValue.timeZone)
                counts[instant] = overview.eventCount
                if overview.eventCount > 0 || overview.diaryCount > 0 {
                    written.insert(instant)
                }
            }
            writtenDays = written
            weekEventCounts = counts
        }

        guard isToday else {
            insightChips = []
            return
        }

        let yesterday = date.addingDays(-1)
        var yesterdayCount = 0
        if let yesterday {
            if let overview = try? await store.computeDaySummaries(from: yesterday, to: yesterday)
                .first
            {
                yesterdayCount = overview.eventCount
            }
        }
        guard !Task.isCancelled else { return }

        let encounters = (try? await store.computeLastEncounters(asOf: date)) ?? [:]
        guard !Task.isCancelled else { return }
        let streak = TodayInsightChip.longestDailyStreak(goals: goals, statuses: statuses)
        let person = TodayInsightChip.lastPerson(
            people: store.content.entities, encounters: encounters, today: date)
        insightChips = TodayInsightChip.make(
            from: TodayInsightChip.Inputs(
                longestDailyStreak: streak.days, streakGoalID: streak.goalID,
                yesterdayEventCount: yesterdayCount,
                yesterday: yesterday ?? date,
                lastPersonName: person?.name, lastPersonID: person?.id))
    }

    /// The evening diary reminder opens the flow on its diary step. The reminder's own day is
    /// not the flow's day: whatever day it names, Today's flow opens. A cold launch waits for the
    /// vault and for the day's tasks as that publish has them (an answer from before the vault opened
    /// has none) and for the strip's goals of that publish, because the flow lists its task and
    /// goal steps once, when it opens.
    private func openCloseDayFromReminder() {
        guard isToday, store.lastUpdated != nil, tasksModel.isCurrent,
            goalModels.model(store: store, day: date).isCurrent,
            CloseDayReminder.claim(notifications.navigationRequest?.closeDayRequestID)
        else { return }
        closeDayRoute = CloseDayRoute(step: .diary)
    }

    /// The back item of a page pushed from this past day: "17 Eyl" (drawing).
    private var backTitle: String {
        DayBackLabel.text(
            for: date, today: LocalDay.today(at: clockNow()), locale: locale, calendar: calendarValue)
    }

    private var diaryRoute: DiaryEditorRoute { DiaryEditorRoute(day: date, isToday: isToday) }

    /// Whether this page's diary editor is open. With a shell the bridge holds the route, so
    /// a new shell's page of the same day presents the editor again; only the page on screen
    /// presents, as the same past day can be live in two tabs. Without a shell the page itself.
    private var diaryPresented: Binding<Bool> {
        guard let navigation else { return $showsDiary }
        return Binding(
            get: { isVisible && navigation.diaryEditor == diaryRoute },
            set: { open in
                if open {
                    navigation.diaryEditor = diaryRoute
                } else {
                    navigation.closeDiaryEditor(diaryRoute)
                }
            })
    }

    /// Mac Today desk: the right panel beside the page when the detail column is wide enough.
    func deskPanel(
        presented: TodayPresentation, goalModel: GoalDayModel, deskPlan: TodayDeskPlan?
    ) -> AnyView? {
        #if os(macOS)
            guard let desk = todayDeskChrome, desk.showsPanel, let deskPlan else { return nil }
            return AnyView(
                TodayDeskPanel(
                    sections: deskPanelSections(
                        presented: presented, goalModel: goalModel, day: day, deskPlan: deskPlan,
                        onThisDay: desk.onThisDay, isFolded: false)))
        #else
            return nil
        #endif
    }

    #if os(macOS)
        func deskPanelSections(
            presented: TodayPresentation, goalModel: GoalDayModel, day: DaySummary?,
            deskPlan: TodayDeskPlan, onThisDay: OnThisDay?, isFolded: Bool
        ) -> TodayDeskPanelSections {
            let goals = loadedGoals?.day == date ? loadedGoals : nil
            return TodayDeskPanelSections(
                store: store, plan: deskPlan, day: date, goals: goals?.goals ?? [],
                statuses: goals.map { goalModel.shownStatuses($0.statuses) } ?? [:],
                onThisDay: onThisDay,
                closeDayLabel: deskCloseDayLabel(presented: presented, goalModel: goalModel, day: day),
                onCloseDay: { closeDayRoute = CloseDayRoute(step: .tasks) },
                onOpenGoal: { goalDestination = GoalDetailRoute(goal: $0) },
                sections: TodayDeskPlan.panelSections(isFolded: isFolded),
                showsHeader: !isFolded)
        }

        /// The panel's "Günü kapat" label, offered as the inline entry would be.
        func deskCloseDayLabel(
            presented: TodayPresentation, goalModel: GoalDayModel, day: DaySummary?
        ) -> String? {
            guard let day, goalModel.hasLoaded,
                CloseDayEntry.isOffered(
                    isToday: true, presentation: presented, hasDiary: CloseDayEntry.hasDiary(day))
            else { return nil }
            let count = presented.closeDayTaskCount
            let title = PresentationLocalization.string(localized: "Günü kapat", locale: locale)
            if count > 0 {
                return title + " · " + PresentationLocalization.string(localized: "\(count) görev", locale: locale)
            }
            return title
        }
    #endif

    /// A small accent row with a chevron under a full-width rule (the drawing's `--line`, 1 pt).
    var closeDayEntry: some View {
        VStack(spacing: 4) {
            Rectangle()
                .fill(Color.ink.line)
                .frame(height: InkStroke.rule)
                .accessibilityHidden(true)
            Button {
                closeDayRoute = CloseDayRoute(step: .tasks)
            } label: {
                HStack {
                    Text("Günü kapat")
                        .font(.ink.section)
                        .foregroundStyle(Color.ink.accent)
                    Spacer(minLength: 0)
                    Image(systemName: "chevron.right")
                        .font(.ink.meta.weight(.semibold))
                        .foregroundStyle(Color.ink.accent)
                }
                .frame(maxWidth: .infinity, minHeight: TapTarget.minimumLength)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier("button.closeDay")
        }
    }

    @ViewBuilder var diarySection: some View {
        // No section title: the card itself reads as the day's writing (the drawing).
        VStack(alignment: .leading, spacing: InkSpacing.row) {
            #if os(iOS)
                Button {
                    diaryPresented.wrappedValue = true
                } label: {
                    InkCard { diaryPreview }
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Günlük yazısını düzenle")
            #else
                NavigationLink {
                    DiaryView(store: store, date: date)
                } label: {
                    InkCard { diaryPreview }
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Günlük yazısını düzenle")
            #endif
        }
    }

    var diaryPreview: some View {
        DayDiaryPreview(isLoaded: day != nil, preview: day?.preview)
    }
}
