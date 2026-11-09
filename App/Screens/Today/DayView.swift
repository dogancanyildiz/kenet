import GoalTracking
import SwiftUI
import VaultFormat

/// Stable identity for ``GoalStripView``: its state starts over per day/vault, with the new model.
enum GoalStripIdentity {
    static func key(day: CalendarDate, vaultPath: String?) -> String {
        day.description + (vaultPath ?? "")
    }
}

/// The goal editing model of the page's day, shared by the strip and the page's goal count. Another
/// day or vault gets a new model in the pass that draws it, so the strip never shows another day's.
/// Another day of the same vault starts from the previous model's goals and history (neither
/// depends on the day): the strip draws at once instead of after the new model's load.
@MainActor final class GoalDayModelSlot {
    private var current: GoalDayModel?

    func model(store: IndexStore, day: CalendarDate) -> GoalDayModel {
        if let current, current.day == day, current.belongs(to: store.vaultURL) { return current }
        let model =
            current.map { GoalDayModel(store: store, day: day, startingFrom: $0) }
            ?? GoalDayModel(store: store, day: day)
        current = model
        return model
    }
}

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
    @Environment(IntentNavigation.self) private var intentNavigation: IntentNavigation?
    @Environment(NotificationService.self) private var notifications
    @Environment(CalendarService.self) private var calendar
    @Environment(\.locale) private var locale
    @Environment(\.calendar) private var calendarValue
    @Environment(\.clockNow) private var clockNow
    @Environment(\.openSettings) private var openSettings
    @Environment(\.displayScale) private var displayScale
    @Environment(\.inkMastheadPlacement) private var mastheadPlacement
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    @Environment(\.scenePhase) private var scenePhase
    /// The shell's bridge: the journal editor's presence and the drafts live there, so a shell
    /// rebuilt by the iPhone Duo shows the same page with the same text. Nil when the page is
    /// hosted without a shell (tests).
    @Environment(ShellNavigationState.self) private var navigation: ShellNavigationState?
    @State private var showsJournal = false
    /// On screen (`onAppear`): a page in another tab or under a pushed page is not, and leaves
    /// the journal editor route to the page the user sees.
    @State private var isVisible = false
    @State private var closeDayRoute: CloseDayRoute?
    @State private var tasksModel: DayTasksModel
    @State private var isCarriedOverExpanded = false
    @State private var isCompletedExpanded = false
    @State private var isTasksExpanded = false
    /// Nil until the first query returns; a reload keeps the previous day until then.
    @State private var loadedDay: DaySummary?
    /// Goal definitions and statuses as of the day they were queried for, loaded with the day.
    @State private var loadedGoals: (day: CalendarDate, goals: [GoalDefinition], statuses: [String: GoalStatus])?
    @State private var goalModels = GoalDayModelSlot()
    /// A goal page pushed from the strip, on this page's stack (the Today tab's on iPhone, the
    /// detail column's on the Mac).
    @State private var goalDestination: GoalDetailRoute?
    /// Whether the day's own graph has a node besides the day, as of the day it was queried for.
    @State private var dayGraph: (date: CalendarDate, isOffered: Bool)?
    @State private var showsDayGraph = false
    @State private var weekDestination: CalendarDate?
    /// Past-day schedule state: month picker, selected timeline card, and editors for events and
    /// tasks on the schedule.
    @State private var showsMonthPicker = false
    @State private var selectedScheduleItemID: String?
    @State private var editingScheduleEvent: EventEditorModel?
    @State private var deletingScheduleEvent: EventRow?
    @State private var editingScheduleTask: TaskEditorModel?
    @State private var deletingScheduleTask: TaskRow?
    @State private var scheduleLinkDestination: EntityLinkDestination?
    @State private var writtenDays: Set<Date> = []
    @State private var weekEventCounts: [Date: Int] = [:]
    @State private var insightChips: [TodayInsightChip] = []
    @State private var chipEntityDestination: EntitySummary?
    @State private var isHeaderCompact = false
    /// Visible scroll height between the top safe area and the bottom chrome (fold budget).
    @State private var viewportHeight: CGFloat = 550
    /// Bumped when the scene becomes active so the greeting tracks the hour.
    @State private var greetingTick = Date()

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
    private var day: DaySummary? { loadedDay?.date == date && tasksModel.isLoaded ? loadedDay : nil }

    private var foldsOpenTasks: Bool {
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
            day.map { $0.events.isEmpty && $0.journal.isEmpty && !$0.hasGoalRecords } == true
            && tasksModel.groups.isEmpty && presented.completedTaskCount == 0
        return withPastDaySheets(
            mainScrollPage(
                presented: presented, goalModel: goalModel, entitiesByID: entitiesByID,
                day: day, isEmptyDay: isEmptyDay)
        )
    }

    private func mainScrollPage(
        presented: TodayPresentation, goalModel: GoalDayModel,
        entitiesByID: [String: EntitySummary], day: DaySummary?, isEmptyDay: Bool
    ) -> some View {
        let todayInstant = LocalDay.instant(
            for: isToday ? date : LocalDay.today(at: clockNow()),
            timeZone: calendarValue.timeZone)
        return ScrollView {
            if isToday {
                todayScrollContent(
                    presented: presented, goalModel: goalModel, entitiesByID: entitiesByID,
                    day: day, isEmptyDay: isEmptyDay, todayInstant: todayInstant)
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
                todayHeader(presented, compact: true)
                    .padding(.horizontal, InkSpacing.margin)
                    .padding(.vertical, 8)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(Color.ink.paper)
            }
        }
        // The stack's own top pad stays under the pinned strip: the gap below the manşet is the same.
        .inkPinnedMasthead(
            mastheadBlock(presented, todayInstant: todayInstant),
            insets: EdgeInsets(top: 8, leading: InkSpacing.margin, bottom: 0, trailing: InkSpacing.margin)
        )
        .inkPage()
        .safeAreaInset(edge: .bottom) {
            QuickEntryBar(
                store: store, isEnabled: true, day: isToday ? nil : date,
                focusRequest: isToday ? intentNavigation?.focusRequest : nil, acceptsPeopleMentions: isToday,
                drafts: navigation
            )
            .id(isToday ? "today" : date.description)
        }
        // Today is a root screen: same modifiers as `inkRootPageNavigationTitle`, kept
        // conditional because a past day is a pushed page that needs the bar's back button.
        .inkPageNavigationTitle(verbatim: presented.headline)
        #if os(iOS)
            .toolbar(isToday ? .hidden : .automatic, for: .navigationBar)
        #endif
        .accessibilityIdentifier(isToday ? "screen.today" : "screen.day")
        // The strip draws nothing until its model has the goals; hosts wait for this, goals or none.
        .preference(key: GoalsStripReadyKey.self, value: goalModel.hasLoaded && !goalModel.isLoading)
        .task(id: date) {
            if AppLaunchPolicy.allowsAutomaticStart() { await calendar.load(date) }
        }
        .task(id: DayRequest(date: date, updated: store.lastUpdated)) {
            // One load: the day and its goal statuses as of that day are taken together.
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
        }
        .navigationDestination(item: $goalDestination) { route in
            // As the Goals list opens it: the page's own day is today.
            GoalDetailView(store: store, goal: route.goal, day: LocalDay.today(at: clockNow()))
        }
        .navigationDestination(item: $weekDestination) { day in
            DayView(
                store: store, date: day,
                onReplaceDay: { weekDestination = $0 },
                onReturnToToday: {
                    weekDestination = nil
                    navigation?.todayPath = NavigationPath()
                })
        }
        .navigationDestination(item: $chipEntityDestination) { entity in
            EntityView(store: store, entity: entity)
        }
        .onAppear { isVisible = true }
        .onDisappear { isVisible = false }
        .sheet(isPresented: journalPresented) {
            NavigationStack { JournalView(store: store, date: date) }
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
                            store: store, selected: date, initialMonth: date
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

    @ViewBuilder
    private func todayScrollContent(
        presented: TodayPresentation, goalModel: GoalDayModel,
        entitiesByID: [String: EntitySummary], day: DaySummary?, isEmptyDay: Bool, todayInstant: Date
    ) -> some View {
        VStack(alignment: .leading, spacing: InkSpacing.section) {
            InkScrolledMasthead(todayHeader(presented, compact: false))

            weekStrip(todayInstant: todayInstant)

            if isToday, day != nil {
                InkSummaryLine(parts: presented.summaryParts)
                if !insightChips.isEmpty {
                    chipRow
                }
            }

            if store.isProcessing && !store.isWriting {
                InkProgress(kind: .indeterminate(label: "İndeks güncelleniyor…"))
            }
            if let error = store.errorText {
                InfoBand(kind: .error, verbatim: error)
            }
            if isEmptyDay {
                EmptyState(
                    isToday
                        ? "Gününden bir an yaz; @ ile kişi ekle"
                        : "Bu gün henüz bir şey yazılmadı.")
            }

            // Until this day's statuses come, the strip counts from its own model: never `0/0`.
            GoalStripView(
                model: goalModels.model(store: store, day: date), countedGoalIDs: presented.countedGoalIDs,
                counter: loadedGoals?.day == date ? presented.counter(for: .goals) : nil,
                onOpen: { goalDestination = GoalDetailRoute(goal: $0) }
            )
            .id(GoalStripIdentity.key(day: date, vaultPath: store.vaultURL?.path))

            DayTasksView(
                store: store, date: date, isToday: isToday, model: tasksModel,
                presentation: presented, entityIndex: entitiesByID,
                onExpandCarriedOver: { isCarriedOverExpanded = true },
                onExpandTasks: { isTasksExpanded = true },
                onExpandCompleted: { isCompletedExpanded = true })

            DayCalendarView(date: date)

            if let day, !day.events.isEmpty {
                VStack(alignment: .leading, spacing: InkSpacing.row) {
                    SectionHeader(
                        title: String(
                            localized: "Olaylar",
                            bundle: PresentationLocalization.bundle(locale), locale: locale),
                        counter: presented.counter(for: .events))
                    InkCard(padded: true) {
                        ForEach(Array(day.events.enumerated()), id: \.element.id) { index, event in
                            if index > 0 { InkCardDivider() }
                            DayEventView(
                                store: store, day: date, event: event,
                                entityIndex: entitiesByID)
                        }
                    }
                }
            }

            journalSection
                .dayContext(store: store, today: isToday ? date : nil)
                .dayBacklinks(store: store, date: date)

            // Last on the page: above the fold it would push the first event out of sight. The
            // flow decides its goal step from the strip's model, so it waits for its goals.
            if let day, goalModel.hasLoaded,
                CloseDayEntry.isOffered(
                    isToday: isToday, presentation: presented, hasJournal: CloseDayEntry.hasJournal(day))
            {
                closeDayEntry
            }
        }
        .padding(.horizontal, InkSpacing.margin)
        .padding(.top, 8)
        // `safeAreaInset` already reserves the capsule; only a small page pad here.
        .padding(.bottom, 8)
        .inkPageColumn()
        .modifier(TodayGlowBackground(isToday: isToday))
    }

    @ViewBuilder
    private func pastDayScrollContent(
        presented: TodayPresentation, goalModel: GoalDayModel,
        entitiesByID: [String: EntitySummary], day: DaySummary?, isEmptyDay: Bool,
        todayInstant: Date
    ) -> some View {
        let schedule = DaySchedulePresentation(
            events: day?.events ?? [],
            tasks: day == nil ? [] : (tasksModel.rows ?? [])
        )
        VStack(alignment: .leading, spacing: InkSpacing.section) {
            InkScrolledMasthead(mastheadBlock(presented, todayInstant: todayInstant))

            if store.isProcessing && !store.isWriting {
                InkProgress(kind: .indeterminate(label: "İndeks güncelleniyor…"))
            }
            if let error = store.errorText {
                InfoBand(kind: .error, verbatim: error)
            }
            if isEmptyDay {
                EmptyState("Bu gün henüz bir şey yazılmadı.")
            }

            DayCalendarView(date: date)

            if day != nil, !schedule.timed.isEmpty {
                VStack(alignment: .leading, spacing: 8) {
                    ForEach(schedule.timed) { entry in
                        scheduleRow(entry: entry, isTimedSection: true, entitiesByID: entitiesByID)
                    }
                }
            }

            if day != nil, !schedule.untimed.isEmpty {
                VStack(alignment: .leading, spacing: 8) {
                    SectionHeader(
                        title: String(
                            localized: "Saatsiz",
                            bundle: PresentationLocalization.bundle(locale), locale: locale),
                        counter: "\(schedule.untimed.count)")
                    ForEach(schedule.untimed) { entry in
                        scheduleRow(entry: entry, isTimedSection: false, entitiesByID: entitiesByID)
                    }
                }
            }

            InkCard {
                GoalStripView(
                    model: goalModels.model(store: store, day: date),
                    countedGoalIDs: presented.countedGoalIDs,
                    counter: loadedGoals?.day == date ? presented.counter(for: .goals) : nil,
                    onOpen: { goalDestination = GoalDetailRoute(goal: $0) }
                )
                .id(GoalStripIdentity.key(day: date, vaultPath: store.vaultURL?.path))
            }

            InkCard {
                journalSection
            }
            .dayBacklinks(store: store, date: date)
        }
        .padding(.horizontal, InkSpacing.margin)
        .padding(.top, 8)
        .padding(.bottom, 8)
        .inkPageColumn()
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
                if overview.eventCount > 0 || overview.journalCount > 0 {
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

    /// The evening journal reminder opens the flow on its journal step. The reminder's own day is
    /// not the flow's day: whatever day it names, Today's flow opens. A cold launch waits for the
    /// vault and for the day's tasks as that publish has them (an answer from before the vault opened
    /// has none) and for the strip's goals of that publish, because the flow lists its task and
    /// goal steps once, when it opens.
    private func openCloseDayFromReminder() {
        guard isToday, store.lastUpdated != nil, tasksModel.isCurrent,
            goalModels.model(store: store, day: date).isCurrent,
            CloseDayReminder.claim(notifications.navigationRequest?.closeDayRequestID)
        else { return }
        closeDayRoute = CloseDayRoute(step: .journal)
    }

    private var journalRoute: JournalEditorRoute { JournalEditorRoute(day: date, isToday: isToday) }

    /// Whether this page's journal editor is open. With a shell the bridge holds the route, so
    /// a new shell's page of the same day presents the editor again; only the page on screen
    /// presents, as the same past day can be live in two tabs. Without a shell the page itself.
    private var journalPresented: Binding<Bool> {
        guard let navigation else { return $showsJournal }
        return Binding(
            get: { isVisible && navigation.journalEditor == journalRoute },
            set: { open in
                if open {
                    navigation.journalEditor = journalRoute
                } else {
                    navigation.closeJournalEditor(journalRoute)
                }
            })
    }

    @ViewBuilder
    private func mastheadBlock(_ presented: TodayPresentation, todayInstant: Date) -> some View {
        if isToday {
            todayHeader(presented, compact: false)
        } else {
            pastDayHeaderBlock(presented, todayInstant: todayInstant)
        }
    }

    /// Today's manşet: the day header with the goal ring.
    private func todayHeader(_ presented: TodayPresentation, compact: Bool) -> some View {
        let total = presented.goalCount
        return dayHeader(
            presented,
            progress: TodayDayRing.progress(completed: presented.completedGoalCount, total: total),
            remaining: TodayDayRing.remaining(completed: presented.completedGoalCount, total: total),
            total: total, compact: compact,
            instant: LocalDay.instant(for: date, timeZone: calendarValue.timeZone))
    }

    private func dayHeader(
        _ presented: TodayPresentation, progress: Double, remaining: Int, total: Int,
        compact: Bool, instant: Date
    ) -> some View {
        InkDayHeader(
            date: instant, progress: progress, remainingCount: remaining,
            showsRing: TodayDayRing.showsRing(total: total), compact: compact,
            compactTitle: presented.shortHeadline
        ) {
            if let dayGraph, dayGraph.date == date, dayGraph.isOffered {
                InkHeaderAction(
                    "Günün grafiği", systemImage: "point.3.connected.trianglepath.dotted",
                    identifier: "button.dayGraph"
                ) {
                    showsDayGraph = true
                }
            }
            if isToday, let openSettings {
                InkHeaderAction("Ayarlar", systemImage: "gearshape", identifier: "button.settings") {
                    openSettings()
                }
            }
            SearchButton()
        }
    }

    private func weekStrip(todayInstant: Date) -> some View {
        let selectionInstant = LocalDay.instant(for: date, timeZone: calendarValue.timeZone)
        return InkWeekStrip(
            selection: Binding(
                get: { selectionInstant },
                set: { newValue in
                    handleWeekDay(
                        LocalDay.today(at: newValue, timeZone: calendarValue.timeZone),
                        today: LocalDay.today(at: todayInstant, timeZone: calendarValue.timeZone))
                }),
            writtenDays: writtenDays,
            eventCounts: weekEventCounts,
            latestSelectable: todayInstant)
    }

    private func handleWeekDay(_ picked: CalendarDate, today: CalendarDate) {
        if picked == date { return }
        if picked > today { return }
        if picked == today {
            if isToday { return }
            if let onReturnToToday {
                onReturnToToday()
            } else if let navigation {
                #if os(macOS)
                    navigation.goToToday(shell: .split)
                #else
                    navigation.todayPath = NavigationPath()
                    navigation.goToToday(shell: .tabs)
                #endif
            } else {
                weekDestination = nil
            }
            return
        }
        if isToday {
            weekDestination = picked
        } else if let onReplaceDay {
            onReplaceDay(picked)
        } else {
            #if os(macOS)
                // Mac Days column: selection drives the detail. iPhone never reads `selectedDay`.
                if let navigation, navigation.section == .days {
                    navigation.selectedDay = TodayDayPath.file(for: picked)
                    return
                }
            #endif
            weekDestination = picked
        }
    }

    private var chipRow: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(Array(insightChips.enumerated()), id: \.offset) { _, chip in
                    TagChip(
                        title: chip.title(locale: locale), systemImage: chip.systemImage,
                        filled: true,
                        onTap: {
                            switch chip {
                            case .streak(_, let goalID):
                                if let goal = loadedGoals?.goals.first(where: { $0.id == goalID }) {
                                    goalDestination = GoalDetailRoute(goal: goal)
                                }
                            case .yesterdayEvents(_, let day):
                                handleWeekDay(day, today: date)
                            case .lastMeeting(_, let entityID):
                                chipEntityDestination = store.content.entities.first {
                                    $0.id == entityID
                                }
                            }
                        })
                }
            }
        }
    }

    private func pastDayHeaderBlock(_ presented: TodayPresentation, todayInstant: Date) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .center, spacing: 8) {
                Button {
                    showsMonthPicker = true
                } label: {
                    HStack(spacing: 4) {
                        Text(LocalDay.instant(for: date), format: .dateTime.month(.wide).year())
                            .font(.ink.section)
                            .foregroundStyle(.ink.text)
                        Image(systemName: "chevron.down")
                            .font(.ink.meta)
                            .foregroundStyle(.ink.secondaryText)
                            .accessibilityHidden(true)
                    }
                    .tapTarget()
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("button.dayMonthPicker")

                Spacer(minLength: 8)

                if let dayGraph, dayGraph.date == date, dayGraph.isOffered {
                    InkHeaderAction(
                        "Günün grafiği", systemImage: "point.3.connected.trianglepath.dotted",
                        identifier: "button.dayGraph"
                    ) {
                        showsDayGraph = true
                    }
                }
                SearchButton()
            }

            weekStrip(todayInstant: todayInstant)
                .frame(maxWidth: .infinity)

            if let byline = day == nil ? nil : presented.byline, !byline.isEmpty {
                Text(verbatim: byline)
                    .font(.ink.byline)
                    .foregroundStyle(.ink.secondaryText)
            }
        }
    }

    @ViewBuilder
    private func scheduleRow(
        entry: DayScheduleEntry, isTimedSection: Bool, entitiesByID: [String: EntitySummary]
    ) -> some View {
        let isSelected = selectedScheduleItemID == entry.id
        HStack(alignment: .top, spacing: 8) {
            Text(
                verbatim: isTimedSection
                    ? (entry.time.map { EventTimeFormat.string(for: $0, locale: locale) } ?? "")
                    : "—"
            )
            .font(.ink.time)
            .monospacedDigit()
            .foregroundStyle(isTimedSection ? Color.ink.secondaryText : Color.ink.tertiaryText)
            .frame(width: 52, alignment: .leading)
            .padding(.top, 10)

            switch entry.kind {
            case .event(let event):
                scheduleEventCard(
                    entryID: entry.id, event: event, isSelected: isSelected,
                    entitiesByID: entitiesByID)
            case .task(let task):
                scheduleTaskCard(
                    entryID: entry.id, task: task, isTimed: entry.time != nil,
                    isSelected: isSelected, entitiesByID: entitiesByID)
            }
        }
    }

    @ViewBuilder
    private func scheduleEventCard(
        entryID: String, event: EventRow, isSelected: Bool,
        entitiesByID: [String: EntitySummary]
    ) -> some View {
        let allLines = DaySchedulePresentation.splitSegmentsByLine(
            InkLinkMapping.segments(from: event.text, entitiesByID: entitiesByID))
        let firstSegments = allLines.first ?? []
        let subLines = Array(allLines.dropFirst())
        let barColor = Self.scheduleBarColor(for: firstSegments)

        HStack(alignment: .top, spacing: 10) {
            Capsule()
                .fill(barColor)
                .frame(width: InkSize.timelineBar)
                .frame(maxHeight: .infinity)
                .accessibilityHidden(true)

            Image(systemName: "pencil")
                .font(.ink.meta)
                .foregroundStyle(Color.ink.accent)
                .frame(width: 20, height: 20)
                .background(
                    RoundedRectangle(cornerRadius: 5, style: .continuous)
                        .fill(Color.ink.accentSoft)
                )
                .padding(.top, 2)
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 4) {
                InkLinkedText(
                    segments: firstSegments, font: .ink.content,
                    openURL: { openScheduleLink($0) }
                )
                .frame(maxWidth: .infinity, alignment: .leading)

                Text(
                    verbatim: scheduleEventMeta(
                        subLineCount: subLines.count, isSelected: isSelected)
                )
                .font(.ink.meta)
                .foregroundStyle(Color.ink.secondaryText)

                if isSelected, !subLines.isEmpty {
                    VStack(alignment: .leading, spacing: 4) {
                        ForEach(Array(subLines.enumerated()), id: \.offset) { _, subSegments in
                            InkLinkedText(
                                segments: subSegments, font: .ink.contentSmall,
                                isMuted: true, openURL: { openScheduleLink($0) })
                        }
                    }
                    .padding(.leading, 10)
                    .overlay(alignment: .leading) {
                        Rectangle()
                            .fill(Color.ink.line)
                            .frame(width: 2)
                            .accessibilityHidden(true)
                    }
                    .padding(.top, 4)
                }
            }
        }
        .padding(InkSpacing.cardPadding)
        .background {
            RoundedRectangle(cornerRadius: InkCorner.card, style: .continuous)
                .fill(isSelected ? Color.ink.accentSoft : Color.ink.surface)
        }
        .overlay {
            RoundedRectangle(cornerRadius: InkCorner.card, style: .continuous)
                .stroke(
                    isSelected ? Color.ink.accent : Color.ink.rule,
                    lineWidth: InkStroke.hairline(scale: displayScale))
        }
        .contentShape(Rectangle())
        .onTapGesture {
            if selectedScheduleItemID == entryID {
                editingScheduleEvent = EventEditorModel(store: store, day: date, row: event)
            } else {
                selectedScheduleItemID = entryID
            }
        }
        .contextMenu {
            Button {
                editingScheduleEvent = EventEditorModel(store: store, day: date, row: event)
            } label: {
                Label("Metni düzenle", systemImage: "pencil")
            }
            Button(role: .destructive) {
                deletingScheduleEvent = event
            } label: {
                Label("Sil", systemImage: "trash")
            }
        }
    }

    @ViewBuilder
    private func scheduleTaskCard(
        entryID: String, task: TaskRow, isTimed: Bool, isSelected: Bool,
        entitiesByID: [String: EntitySummary]
    ) -> some View {
        let box = TaskBoxPresentation(row: task, isCompleted: tasksModel.completed.contains(task.id))
        let isCompleted = box.state.isCompleted
        let segments = scheduleTaskSegments(for: task, isTimed: isTimed, entitiesByID: entitiesByID)
        let canToggle = !tasksModel.completing.contains(task.id) && !store.isWriting && store.canAddEvent

        HStack(alignment: .top, spacing: 10) {
            Capsule()
                .fill(isCompleted ? Color.ink.control : Color.ink.accent)
                .frame(width: InkSize.timelineBar)
                .frame(maxHeight: .infinity)
                .accessibilityHidden(true)

            TaskBox(
                state: box.state,
                action: canToggle ? { Task { await tasksModel.complete(task) } } : nil,
                accessibilityLabel: isCompleted ? "Görevi yeniden aç" : "Görevi tamamla"
            )

            VStack(alignment: .leading, spacing: 4) {
                InkLinkedText(
                    segments: segments, font: .ink.content, isMuted: isCompleted,
                    openURL: { openScheduleLink($0) }
                )
                .frame(maxWidth: .infinity, alignment: .leading)

                Text(verbatim: scheduleTaskMeta(for: task, isCompleted: isCompleted))
                    .font(.ink.meta)
                    .foregroundStyle(Color.ink.secondaryText)
            }
        }
        .padding(InkSpacing.cardPadding)
        .background {
            RoundedRectangle(cornerRadius: InkCorner.card, style: .continuous)
                .fill(isSelected ? Color.ink.accentSoft : Color.ink.surface)
        }
        .overlay {
            RoundedRectangle(cornerRadius: InkCorner.card, style: .continuous)
                .stroke(
                    isSelected ? Color.ink.accent : Color.ink.rule,
                    lineWidth: InkStroke.hairline(scale: displayScale))
        }
        .opacity(isCompleted ? 0.72 : 1)
        .contentShape(Rectangle())
        .onTapGesture {
            if selectedScheduleItemID == entryID {
                editingScheduleTask = TaskEditorModel(store: store, row: task)
            } else {
                selectedScheduleItemID = entryID
            }
        }
        .contextMenu {
            Button {
                editingScheduleTask = TaskEditorModel(store: store, row: task)
            } label: {
                Label("Metni düzenle", systemImage: "pencil")
            }
            Button(role: .destructive) {
                deletingScheduleTask = task
            } label: {
                Label("Sil", systemImage: "trash")
            }
        }
    }

    private static func scheduleBarColor(for segments: [InkLinkSegment]) -> Color {
        if segments.contains(where: { $0.kind == .person }) {
            return .ink.person
        }
        if segments.contains(where: { $0.kind == .place }) {
            return .ink.place
        }
        return .ink.accent
    }

    private func scheduleEventMeta(subLineCount: Int, isSelected: Bool) -> String {
        let base = String(
            localized: "Olay", bundle: PresentationLocalization.bundle(locale), locale: locale)
        guard !isSelected, subLineCount > 0 else { return base }
        let suffix = String(
            localized: "\(subLineCount) alt satır",
            bundle: PresentationLocalization.bundle(locale), locale: locale)
        return "\(base) · \(suffix)"
    }

    private func scheduleTaskMeta(for task: TaskRow, isCompleted: Bool) -> String {
        var parts = [
            String(
                localized: "Görev", bundle: PresentationLocalization.bundle(locale), locale: locale)
        ]
        if let project = task.project {
            parts.append(project)
        }
        if isCompleted {
            parts.append(
                String(
                    localized: "Tamamlandı",
                    bundle: PresentationLocalization.bundle(locale), locale: locale))
        }
        return parts.joined(separator: " · ")
    }

    private func scheduleTaskSegments(
        for task: TaskRow, isTimed: Bool, entitiesByID: [String: EntitySummary]
    ) -> [InkLinkSegment] {
        var raw = InkLinkMapping.segments(from: task.text, entitiesByID: entitiesByID)
        if isTimed, let first = raw.first, first.kind == .plain {
            let stripped = DaySchedulePresentation.strippingLeadingTime(from: first.text)
            if stripped.isEmpty {
                raw.removeFirst()
            } else {
                raw[0] = InkLinkSegment(
                    id: first.id, text: stripped, kind: first.kind,
                    target: first.target, path: first.path)
            }
        }
        return DaySchedulePresentation.splitSegmentsByLine(raw).first ?? raw
    }

    private func openScheduleLink(_ url: URL) {
        scheduleLinkDestination = EntityLinkDestination.from(
            url: url, entities: store.content.entities)
    }

    /// Accent row with chevron; no thin rule (Şafak).
    private var closeDayEntry: some View {
        Button {
            closeDayRoute = CloseDayRoute(step: .tasks)
        } label: {
            HStack {
                Text("Günü kapat")
                    .font(.ink.byline)
                    .foregroundStyle(Color.ink.accent)
                Spacer(minLength: 0)
                Image(systemName: "chevron.right")
                    .font(.body.weight(.semibold))
                    .foregroundStyle(Color.ink.accent)
            }
            .frame(maxWidth: .infinity, minHeight: TapTarget.minimumLength)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("button.closeDay")
    }

    @ViewBuilder private var journalSection: some View {
        VStack(alignment: .leading, spacing: InkSpacing.row) {
            SectionHeader(
                title: String(
                    localized: "Günlük yazısı",
                    bundle: PresentationLocalization.bundle(locale), locale: locale))
            #if os(iOS)
                Button {
                    journalPresented.wrappedValue = true
                } label: {
                    InkCard { journalPreview }
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Günlük yazısını düzenle")
            #else
                NavigationLink {
                    JournalView(store: store, date: date)
                } label: {
                    InkCard { journalPreview }
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Günlük yazısını düzenle")
            #endif
        }
    }

    private var journalPreview: some View {
        DayJournalPreview(isLoaded: day != nil, preview: day?.preview)
    }
}

/// Dawn glow only on Today's scroll content (past days stay flat).
private struct TodayGlowBackground: ViewModifier {
    var isToday: Bool

    func body(content: Content) -> some View {
        if isToday {
            content.inkGlow()
        } else {
            content
        }
    }
}

/// One row on the past-day timed schedule (`DaySchedulePresentation`).
struct DayScheduleEntry: Identifiable, Sendable {
    enum Kind: Sendable {
        case event(EventRow)
        case task(TaskRow)
    }

    let id: String
    let time: EventTime?
    let fileOrder: Int
    let kind: Kind

    init(id: String, time: EventTime?, fileOrder: Int, kind: Kind) {
        self.id = id
        self.time = time
        self.fileOrder = fileOrder
        self.kind = kind
    }
}

/// Pure chronological sorting for a past day's schedule: timed items sorted by `EventTime`
/// (ties preserve vault file order), untimed items grouped at the end in vault file order.
struct DaySchedulePresentation: Sendable {
    let timed: [DayScheduleEntry]
    let untimed: [DayScheduleEntry]

    var isEmpty: Bool {
        timed.isEmpty && untimed.isEmpty
    }

    var allOrdered: [DayScheduleEntry] {
        timed + untimed
    }

    init(entries: [DayScheduleEntry]) {
        let withTime = entries.filter { $0.time != nil }
        let withoutTime = entries.filter { $0.time == nil }
        timed = withTime.sorted { lhs, rhs in
            guard let lt = lhs.time, let rt = rhs.time else {
                return lhs.fileOrder < rhs.fileOrder
            }
            if lt.hour != rt.hour {
                return lt.hour < rt.hour
            }
            if lt.minute != rt.minute {
                return lt.minute < rt.minute
            }
            return lhs.fileOrder < rhs.fileOrder
        }
        untimed = withoutTime.sorted { $0.fileOrder < $1.fileOrder }
    }

    init(events: [EventRow], tasks: [TaskRow]) {
        var combined: [DayScheduleEntry] = []
        var order = 0
        for event in events {
            combined.append(
                DayScheduleEntry(
                    id: "event-\(event.id)-\(event.sourceLine)",
                    time: event.time,
                    fileOrder: order,
                    kind: .event(event)
                )
            )
            order += 1
        }
        for task in tasks {
            let extracted = Self.extractLeadingTime(from: task.text.plainText)
            combined.append(
                DayScheduleEntry(
                    id: "task-\(task.id)",
                    time: extracted,
                    fileOrder: order,
                    kind: .task(task)
                )
            )
            order += 1
        }
        self.init(entries: combined)
    }

    static func extractLeadingTime(from text: String) -> EventTime? {
        let trimmed = text.trimmingCharacters(in: .whitespaces)
        guard trimmed.count >= 5 else { return nil }
        let prefix = String(trimmed.prefix(5))
        let rest = trimmed.dropFirst(5)
        guard rest.isEmpty || rest.first == " " else { return nil }
        return RawDocument(bytes: Array("## Events\n- \(prefix) item".utf8)).bodyLines.events.first?.time
    }

    static func strippingLeadingTime(from text: String) -> String {
        let trimmed = text.trimmingCharacters(in: .whitespaces)
        guard extractLeadingTime(from: trimmed) != nil else { return text }
        return String(trimmed.dropFirst(5)).trimmingCharacters(in: .whitespaces)
    }

    static func splitSegmentsByLine(_ segments: [InkLinkSegment]) -> [[InkLinkSegment]] {
        var lines: [[InkLinkSegment]] = [[]]
        for segment in segments {
            if segment.kind == .plain, segment.text.contains("\n") {
                let parts = segment.text.split(separator: "\n", omittingEmptySubsequences: false)
                for (index, part) in parts.enumerated() {
                    if index > 0 {
                        lines.append([])
                    }
                    let text: String
                    if index > 0 {
                        text = String(part).replacingOccurrences(
                            of: #"^\s*(?:[-*]\s+)?"#, with: "", options: .regularExpression)
                    } else {
                        text = String(part)
                    }
                    if !text.isEmpty {
                        lines[lines.count - 1].append(
                            InkLinkSegment(id: "\(segment.id)-\(index)", text: text, kind: .plain))
                    }
                }
            } else {
                lines[lines.count - 1].append(segment)
            }
        }
        let nonEmpty = lines.filter { !$0.isEmpty }
        return nonEmpty.isEmpty ? [[]] : nonEmpty
    }
}

/// The Günlük yazısı section's button label: the opening of the day's text and "Devamını yaz",
/// or the placeholder. Nothing until the day is loaded.
struct DayJournalPreview: View {
    let isLoaded: Bool
    let preview: String?
    @Environment(\.locale) private var locale

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            if isLoaded, let preview {
                Text(verbatim: preview)
                    .font(.ink.content)
                    .foregroundStyle(Color.ink.text)
                    .lineLimit(4)
                    .inkJournalParagraph()
                    .frame(maxWidth: .infinity, alignment: .leading)
                Text(
                    verbatim: String(
                        localized: "Devamını yaz",
                        bundle: PresentationLocalization.bundle(locale), locale: locale)
                )
                .font(.ink.byline)
                .foregroundStyle(Color.ink.accent)
            } else if isLoaded {
                Text(
                    verbatim: String(
                        localized: "Günlük yazısı ekle…",
                        bundle: PresentationLocalization.bundle(locale), locale: locale)
                )
                .font(.ink.placeholder)
                .foregroundStyle(Color.ink.secondaryText)
                // One line of placeholder is shorter than a finger: on iOS the row is a 44 pt
                // touch target, the text centred in it.
                .frame(maxWidth: .infinity, minHeight: Self.placeholderMinHeight, alignment: .leading)
            }
        }
        // The empty part of the row opens the editor too.
        .contentShape(Rectangle())
    }

    private static var placeholderMinHeight: CGFloat? {
        #if os(iOS)
            TapTarget.minimumLength
        #else
            nil
        #endif
    }
}

/// Recomputes the local day across midnight without reopening the app.
struct TodayView: View {
    let store: IndexStore
    @Environment(\.clockNow) private var clockNow

    var body: some View {
        TimelineView(.periodic(from: .now, by: 60)) { _ in
            DayView(store: store, date: LocalDay.today(at: clockNow()), isToday: true)
        }
    }
}

/// When the day page offers its own graph (the manşet's Graph icon).
enum DayGraphEntry {
    /// Pure rule (unit-tested): the day links at least one entity, so its graph has a node besides
    /// the day itself.
    static func isOffered(_ input: GraphInput, on date: CalendarDate) -> Bool {
        let graph = GraphModel.compute(input: input, filter: GraphFilter(scope: .day(date)), today: date)
        return graph.nodes.contains { $0.kind != .day }
    }
}

/// Numbers shown at the top of the close-day sheet.
struct CloseDaySummary: Equatable, Sendable {
    var events: Int
    var completedTasks: Int
    var remainingTasks: Int
}

