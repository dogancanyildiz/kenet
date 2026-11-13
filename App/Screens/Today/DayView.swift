import GoalTracking
import Summaries
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
    /// The shell's bridge: the diary editor's presence and the drafts live there, so a shell
    /// rebuilt by the iPhone Duo shows the same page with the same text. Nil when the page is
    /// hosted without a shell (tests).
    @Environment(ShellNavigationState.self) private var navigation: ShellNavigationState?
    #if os(macOS)
        @Environment(\.todayDeskChrome) private var todayDeskChrome: TodayDeskChrome?
    #endif
    @State private var showsDiary = false
    /// On screen (`onAppear`): a page in another tab or under a pushed page is not, and leaves
    /// the diary editor route to the page the user sees.
    @State private var isVisible = false
    @State private var closeDayRoute: CloseDayRoute?
    @State private var tasksModel: DayTasksModel
    @State private var isCarriedOverExpanded = false
    @State private var isCompletedExpanded = false
    @State private var isTasksExpanded = false
    /// Nil until the first query returns; a reload keeps the previous day until then.
    @State private var loadedDay: DaySummary?
    /// The request the page's main load last finished for (``DayPageReadyKey``).
    @State private var loadedRequest: DayRequest?
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
    /// The schedule card's leading icon box (the drawing's 32 pt square).
    @ScaledMetric(relativeTo: .body) private var scheduleIconBox: CGFloat = 32
    /// The pinned manşet's small ring (the drawing's 30 pt).
    @ScaledMetric(relativeTo: .body) private var compactRingSide: CGFloat = 30
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
    /// Bumped to the injected clock when the scene becomes active so the greeting tracks the
    /// hour. Starts in the distant past, not at the wall clock: `clockNow` alone decides the
    /// first greeting, so a frozen clock (previews, references) is never overridden by `Date()`.
    @State private var greetingTick = Date.distantPast

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

    /// Mac desk shell draws "Günü kapat" in the panel / folded block.
    private var showsInlineCloseDay: Bool {
        #if os(macOS)
            todayDeskChrome == nil
        #else
            true
        #endif
    }

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

    @ViewBuilder
    private func todayScrollContent(
        presented: TodayPresentation, goalModel: GoalDayModel,
        entitiesByID: [String: EntitySummary], day: DaySummary?, isEmptyDay: Bool, todayInstant: Date,
        deskPlan: TodayDeskPlan?
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

            #if os(macOS)
                if let desk = todayDeskChrome, let deskPlan {
                    TodayDeskTimeline(
                        store: store, plan: deskPlan, day: date, today: date,
                        onSelectEvent: { editingScheduleEvent = EventEditorModel(store: store, day: date, row: $0) },
                        onSelectTask: { editingScheduleTask = TaskEditorModel(store: store, row: $0) },
                        completingTaskIDs: tasksModel.completing,
                        onCompleteTask: store.canAddEvent
                            ? { row in Task { await tasksModel.complete(row) } } : nil)
                    if !desk.showsPanel {
                        deskPanelSections(
                            presented: presented, goalModel: goalModel, day: day, deskPlan: deskPlan,
                            onThisDay: desk.onThisDay, isFolded: true)
                    }
                }
            #endif

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
                // A past day's card opens the page on that day (`amountDay`): a quick step there
                // writes to the day on screen, not to today.
                onOpen: { goalDestination = GoalDetailRoute(goal: $0, amountDay: date) },
                onEnterAmount: { goalDestination = GoalDetailRoute(goal: $0, focusesAmount: true, amountDay: date) }
            )
            .id(GoalStripIdentity.key(day: date, vaultPath: store.vaultURL?.path))

            DayTasksView(
                store: store, date: date, isToday: isToday, model: tasksModel,
                presentation: presented, entityIndex: entitiesByID,
                onExpandCarriedOver: { isCarriedOverExpanded = true },
                onExpandTasks: { isTasksExpanded = true },
                onExpandCompleted: { isCompletedExpanded = true },
                deskPlan: deskPlan)

            DayCalendarView(date: date)

            // On the Mac desk the hour grid owns the timed events; this list keeps the untimed ones.
            if let day, case let listed = deskPlan?.dayListEvents ?? day.events, !listed.isEmpty {
                VStack(alignment: .leading, spacing: InkSpacing.row) {
                    SectionHeader(
                        title: String(
                            localized: "Olaylar",
                            bundle: PresentationLocalization.bundle(locale), locale: locale),
                        counter: deskPlan == nil
                            ? presented.counter(for: .events)
                            : listed.count.formatted(.number.locale(presented.locale)))
                    InkCard(padded: true) {
                        ForEach(Array(listed.enumerated()), id: \.element.id) { index, event in
                            if index > 0 { InkCardDivider() }
                            DayEventView(
                                store: store, day: date, event: event,
                                entityIndex: entitiesByID)
                        }
                    }
                }
            }

            diarySection
                .dayContext(store: store, today: isToday ? date : nil)
                .dayBacklinks(store: store, date: date)

            // Last on the page: above the fold it would push the first event out of sight. The
            // flow decides its goal step from the strip's model, so it waits for its goals.
            if showsInlineCloseDay, let day, goalModel.hasLoaded,
                CloseDayEntry.isOffered(
                    isToday: isToday, presentation: presented, hasDiary: CloseDayEntry.hasDiary(day))
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

    /// iPad (regular width) and the Mac draw a past day as the wide drawing (`j-mac2`): the
    /// column beside it already holds the calendar, so no week strip; goal cards, then one
    /// "Program" card. The iPhone keeps its week strip and its "Saatsiz" list.
    private var usesProgramLayout: Bool {
        #if os(macOS)
            true
        #else
            horizontalSizeClass == .regular
        #endif
    }

    @ViewBuilder
    private func pastDayScrollContent(
        presented: TodayPresentation, goalModel: GoalDayModel,
        entitiesByID: [String: EntitySummary], day: DaySummary?, isEmptyDay: Bool,
        todayInstant: Date
    ) -> some View {
        let schedule = DaySchedulePresentation(
            events: day?.events ?? [],
            tasks: day == nil ? [] : (tasksModel.rows ?? []),
            dayFile: TodayDayPath.file(for: date)
        )
        if usesProgramLayout {
            programDayContent(
                presented: presented, schedule: schedule, entitiesByID: entitiesByID, day: day,
                isEmptyDay: isEmptyDay, todayInstant: todayInstant)
        } else {
            compactPastDayContent(
                presented: presented, schedule: schedule, entitiesByID: entitiesByID, day: day,
                isEmptyDay: isEmptyDay, todayInstant: todayInstant)
        }
    }

    /// The wide past day: manşet, goal cards, the "Program" card, the calendar, the diary.
    private func programDayContent(
        presented: TodayPresentation, schedule: DaySchedulePresentation,
        entitiesByID: [String: EntitySummary], day: DaySummary?, isEmptyDay: Bool, todayInstant: Date
    ) -> some View {
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

            GoalStripView(
                model: goalModels.model(store: store, day: date),
                countedGoalIDs: presented.countedGoalIDs,
                counter: loadedGoals?.day == date ? presented.counter(for: .goals) : nil,
                onOpen: { goalDestination = GoalDetailRoute(goal: $0, amountDay: date) },
                onEnterAmount: { goalDestination = GoalDetailRoute(goal: $0, focusesAmount: true, amountDay: date) }
            )
            .id(GoalStripIdentity.key(day: date, vaultPath: store.vaultURL?.path))

            if day != nil, !schedule.isEmpty {
                programCard(schedule, presented: presented, entitiesByID: entitiesByID)
            }

            DayCalendarView(date: date)

            diarySection
                .dayBacklinks(store: store, date: date)
        }
        .padding(.horizontal, InkSpacing.margin)
        .padding(.top, 8)
        .padding(.bottom, 8)
        .inkPageColumn()
    }

    @ViewBuilder
    private func compactPastDayContent(
        presented: TodayPresentation, schedule: DaySchedulePresentation,
        entitiesByID: [String: EntitySummary], day: DaySummary?, isEmptyDay: Bool, todayInstant: Date
    ) -> some View {
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

            // The strip, the diary and the backlinks draw their own cards; a day without goals
            // draws no goal card at all.
            GoalStripView(
                model: goalModels.model(store: store, day: date),
                countedGoalIDs: presented.countedGoalIDs,
                counter: loadedGoals?.day == date ? presented.counter(for: .goals) : nil,
                // A past day's card opens the page on that day (`amountDay`): a quick step there
                // writes to the day on screen, not to today.
                onOpen: { goalDestination = GoalDetailRoute(goal: $0, amountDay: date) },
                onEnterAmount: { goalDestination = GoalDetailRoute(goal: $0, focusesAmount: true, amountDay: date) }
            )
            .id(GoalStripIdentity.key(day: date, vaultPath: store.vaultURL?.path))

            diarySection
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
            if usesWideMasthead {
                // iPad drawing: bare icons, the day's graph, settings, then search.
                Group {
                    dayGraphAction(alwaysShown: isToday)
                    settingsAction
                    SearchButton()
                }
                .environment(\.inkHeaderActionChrome, .bare)
            } else {
                dayGraphAction
                // iPhone drawing order: search, then settings.
                SearchButton()
                settingsAction
            }
        }
    }

    @ViewBuilder private var settingsAction: some View {
        if isToday, let openSettings {
            InkHeaderAction("Ayarlar", systemImage: "gearshape", identifier: "button.settings") {
                openSettings()
            }
        }
    }

    /// The regular-width iOS page (iPad) draws its manşet icons as the iPad drawing does.
    private var usesWideMasthead: Bool {
        #if os(iOS)
            horizontalSizeClass == .regular
        #else
            false
        #endif
    }

    /// Today's pinned one-line manşet once the page scrolls (drawing): a small ring without its
    /// number, "20 Eylül" with the weekday in secondary ink, and search alone.
    private func todayCompactHeader(_ presented: TodayPresentation) -> some View {
        let total = presented.goalCount
        let completed = presented.completedGoalCount
        let instant = LocalDay.instant(for: date, timeZone: calendarValue.timeZone)
        return HStack(alignment: .center, spacing: 10) {
            if TodayDayRing.showsRing(total: total) {
                GoalRing(
                    progress: TodayDayRing.progress(completed: completed, total: total),
                    diameter: compactRingSide, emphasizesArc: true
                )
                .accessibilityLabel(
                    Text(
                        verbatim: TodayDayRing.accessibilityLabel(
                            remaining: TodayDayRing.remaining(completed: completed, total: total),
                            locale: locale)))
            }
            ViewThatFits(in: .horizontal) {
                compactTitle(instant).fixedSize()
                    .font(.ink.section)
                Text(verbatim: presented.shortHeadline)
                    .font(.ink.section)
                    .foregroundStyle(Color.ink.text)
                    .lineLimit(1)
            }
            .accessibilityElement(children: .combine)
            .accessibilityAddTraits(.isHeader)
            Spacer(minLength: 0)
            SearchButton()
                .buttonStyle(InkHeaderButtonStyle())
                .environment(\.inkHeaderActionChrome, .bare)
        }
        .accessibilityElement(children: .contain)
    }

    private func compactTitle(_ instant: Date) -> some View {
        let resolved = PresentationLocalization.resolvedLocale(locale)
        let style = Date.FormatStyle(locale: resolved, calendar: calendarValue, timeZone: calendarValue.timeZone)
        return HStack(alignment: .firstTextBaseline, spacing: 5) {
            Text(verbatim: instant.formatted(style.day().month(.wide)))
                .foregroundStyle(Color.ink.text)
            Text(verbatim: instant.formatted(style.weekday(.wide)))
                .foregroundStyle(Color.ink.secondaryText)
        }
        .lineLimit(1)
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

    /// "Eylül 2026 ⌄": opens the month picker; it heads the page with the graph and search.
    private var monthPickerButton: some View {
        Button {
            showsMonthPicker = true
        } label: {
            HStack(spacing: 4) {
                Text(LocalDay.instant(for: date), format: .dateTime.month(.wide))
                    .font(.ink.section)
                    .foregroundStyle(.ink.text)
                Text(LocalDay.instant(for: date), format: .dateTime.year())
                    .font(.ink.section)
                    .foregroundStyle(.ink.secondaryText)
                Image(systemName: "chevron.down")
                    .font(.ink.meta.weight(.semibold))
                    .foregroundStyle(.ink.secondaryText)
                    .accessibilityHidden(true)
            }
            .tapTarget()
        }
        .buttonStyle(.plain)
        .accessibilityHint(Text("Ay seç"))
        .accessibilityIdentifier("button.dayMonthPicker")
    }

    @ViewBuilder private var dayGraphAction: some View { dayGraphAction(alwaysShown: false) }

    /// The manşet's Graph icon, while the day links an entity. `alwaysShown` (the iPad Today
    /// manşet, drawing `c-pad`) keeps the icon in its place and dims it until there is a graph.
    @ViewBuilder private func dayGraphAction(alwaysShown: Bool) -> some View {
        let isOffered = dayGraph.map { $0.date == date && $0.isOffered } ?? false
        if isOffered || alwaysShown {
            InkHeaderAction(
                "Günün grafiği", systemImage: "point.3.connected.trianglepath.dotted",
                identifier: "button.dayGraph"
            ) {
                showsDayGraph = true
            }
            .disabled(!isOffered)
        }
    }

    /// "3 olay · 2 görev" beside the day's title.
    private func pastDayCounts(_ presented: TodayPresentation) -> String? {
        guard day != nil else { return nil }
        let tasks = tasksModel.rows?.count ?? 0
        guard presented.eventCount > 0 || tasks > 0 else { return nil }
        return String(
            localized: "\(presented.eventCount) olay · \(tasks) görev",
            bundle: PresentationLocalization.bundle(locale), locale: locale)
    }

    private func pastDayHeaderBlock(_ presented: TodayPresentation, todayInstant: Date) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            #if os(macOS)
                // Mac (drawing `j-mac2`): "17 Eylül Perşembe" and its counts, the icons beside them.
                HStack(alignment: .top, spacing: 8) {
                    wideDayTitleBlock(presented)
                    Spacer(minLength: 8)
                    dayGraphAction
                    SearchButton()
                }
            #else
                if usesProgramLayout {
                    // iPad: the navigation row keeps the back chip and the icons; the column
                    // beside the page holds the calendar, so no month picker or week strip.
                    InkNavigationRow(backShowsTitle: false) {
                        EmptyView()
                    } actions: {
                        dayGraphAction
                        SearchButton()
                    }
                    wideDayTitleBlock(presented)
                } else {
                    compactPastDayHeader(presented, todayInstant: todayInstant)
                }
            #endif
        }
    }

    /// "17 Eylül" with the weekday in secondary ink, then "3 olay · 2 görev · 2 hedef kaydı" with
    /// its numbers in the text colour (drawing `j-mac2`).
    private func wideDayTitleBlock(_ presented: TodayPresentation) -> some View {
        let resolved = PresentationLocalization.resolvedLocale(locale)
        let instant = LocalDay.instant(for: date, timeZone: calendarValue.timeZone)
        var style = Date.FormatStyle(locale: resolved, calendar: calendarValue, timeZone: calendarValue.timeZone)
            .day().month(.wide)
        if date.year != LocalDay.today(at: clockNow()).year { style = style.year() }
        let weekday = Date.FormatStyle(locale: resolved, calendar: calendarValue, timeZone: calendarValue.timeZone)
            .weekday(.wide)
        let title = Text(
            "\(Text(verbatim: instant.formatted(style)).foregroundStyle(Color.ink.text)) \(Text(verbatim: instant.formatted(weekday)).foregroundStyle(Color.ink.secondaryText))"
        )
        return VStack(alignment: .leading, spacing: 4) {
            title
                .font(.ink.subpageTitle)
                .accessibilityAddTraits(.isHeader)
            if let counts = wideDayCounts(presented) {
                counts
                    .font(.ink.pageByline)
                    .foregroundStyle(Color.ink.secondaryText)
                    .lineLimit(2)
            }
        }
    }

    /// The goals with a record on this day (the drawing's "2 hedef kaydı").
    private var goalRecordCount: Int {
        let model = goalModels.model(store: store, day: date)
        return model.goals.filter { model.value(for: $0) != nil }.count
    }

    private func wideDayCounts(_ presented: TodayPresentation) -> Text? {
        guard day != nil else { return nil }
        let tasks = tasksModel.rows?.count ?? 0
        let goals = goalRecordCount
        guard presented.eventCount > 0 || tasks > 0 || goals > 0 else { return nil }
        let events = Self.countNumber(presented.eventCount, locale: locale)
        let taskText = Self.countNumber(tasks, locale: locale)
        if goals > 0 {
            let goalText = Self.countNumber(goals, locale: locale)
            return Text("\(events) olay · \(taskText) görev · \(goalText) hedef kaydı")
        }
        return Text("\(events) olay · \(taskText) görev")
    }

    /// A count in a künye: semibold in the text colour, the words stay secondary.
    static func countNumber(_ value: Int, locale: Locale) -> Text {
        Text(verbatim: value.formatted(.number.locale(locale))).fontWeight(.semibold).foregroundStyle(Color.ink.text)
    }

    /// iPhone (drawing): one navigation row with the back chip, the month picker in the middle
    /// and the icons; then the week strip and the day's full date with its counts on the
    /// trailing side. In the tab shell the row hides the system bar (InkNavigationRow).
    private func compactPastDayHeader(_ presented: TodayPresentation, todayInstant: Date) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            InkNavigationRow(backShowsTitle: false) {
                monthPickerButton
            } actions: {
                dayGraphAction
                SearchButton()
            }
            weekStrip(todayInstant: todayInstant)
                .frame(maxWidth: .infinity)
            ViewThatFits(in: .horizontal) {
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    pastDayTitle(presented)
                    Spacer(minLength: 8)
                    pastDayCountsText(presented)
                }
                VStack(alignment: .leading, spacing: 2) {
                    pastDayTitle(presented)
                    pastDayCountsText(presented)
                }
            }
        }
    }

    private func pastDayTitle(_ presented: TodayPresentation) -> some View {
        Text(verbatim: presented.headline)
            .font(.ink.dayName.weight(.bold))
            .foregroundStyle(.ink.text)
            .fixedSize(horizontal: false, vertical: true)
            .accessibilityAddTraits(.isHeader)
    }

    @ViewBuilder private func pastDayCountsText(_ presented: TodayPresentation) -> some View {
        if let counts = pastDayCounts(presented) {
            Text(verbatim: counts)
                .font(.ink.meta)
                .foregroundStyle(.ink.secondaryText)
                .lineLimit(1)
        }
    }

    @ViewBuilder
    private func scheduleRow(
        entry: DayScheduleEntry, isTimedSection: Bool, entitiesByID: [String: EntitySummary]
    ) -> some View {
        let isSelected = selectedScheduleItemID == entry.id
        let time = entry.time.map { EventTimeFormat.string(for: $0, locale: locale) }
        HStack(alignment: .top, spacing: 8) {
            // The card reads its time itself; the column is for the eye.
            Text(verbatim: isTimedSection ? (time ?? "") : "")
                .font(.ink.meta.weight(.semibold))
                .monospacedDigit()
                .foregroundStyle(Color.ink.secondaryText)
                .frame(width: 52, alignment: .leading)
                .padding(.top, InkSpacing.cardPadding + 2)
                .accessibilityHidden(true)

            switch entry.kind {
            case .event(let event):
                scheduleEventCard(
                    entryID: entry.id, event: event, time: time, isSelected: isSelected,
                    entitiesByID: entitiesByID)
            case .task(let task):
                scheduleTaskCard(
                    entryID: entry.id, task: task, time: time, isSelected: isSelected,
                    entitiesByID: entitiesByID)
            }
        }
    }

    /// The wide past day's one "Program" card (drawing `j-mac2`): a small title with the counts,
    /// then every entry in time order, untimed ones last with "—" in the time column.
    private func programCard(
        _ schedule: DaySchedulePresentation, presented: TodayPresentation,
        entitiesByID: [String: EntitySummary]
    ) -> some View {
        let tasks = schedule.allOrdered.filter { if case .task = $0.kind { true } else { false } }.count
        let events = schedule.allOrdered.count - tasks
        return InkCard {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text("Program")
                    .font(.ink.meta.weight(.semibold))
                    .foregroundStyle(Color.ink.secondaryText)
                    .accessibilityAddTraits(.isHeader)
                    // A section title, as ``SectionHeader``'s: not a page manşet.
                    .accessibilityIdentifier(SectionHeader.titleIdentifier)
                Spacer(minLength: 8)
                Text(
                    "\(Self.countNumber(events, locale: locale)) olay · \(Self.countNumber(tasks, locale: locale)) görev"
                )
                .font(.ink.meta)
                .foregroundStyle(Color.ink.secondaryText)
            }
            VStack(alignment: .leading, spacing: 8) {
                ForEach(schedule.allOrdered) { entry in
                    programRow(entry: entry, entitiesByID: entitiesByID)
                }
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("day.program")
    }

    @ViewBuilder
    private func programRow(entry: DayScheduleEntry, entitiesByID: [String: EntitySummary]) -> some View {
        let isSelected = selectedScheduleItemID == entry.id
        let time = entry.time.map { EventTimeFormat.string(for: $0, locale: locale) }
        HStack(alignment: .top, spacing: 10) {
            Text(verbatim: time ?? "—")
                .font(.ink.meta)
                .monospacedDigit()
                .foregroundStyle(Color.ink.secondaryText)
                .frame(width: 44, alignment: .trailing)
                .padding(.top, 12)
                .accessibilityHidden(true)
            switch entry.kind {
            case .event(let event):
                programEventCard(
                    entryID: entry.id, event: event, time: time, isSelected: isSelected,
                    entitiesByID: entitiesByID)
            case .task(let task):
                programTaskCard(
                    entryID: entry.id, task: task, time: time, isSelected: isSelected,
                    entitiesByID: entitiesByID)
            }
        }
    }

    /// "Olay" / "Görev": the program card's small outlined kind label.
    private func programKind(_ key: LocalizedStringKey) -> some View {
        Text(key)
            .font(.caption)
            .foregroundStyle(Color.ink.secondaryText)
            .padding(.horizontal, 8)
            .padding(.vertical, 2)
            .overlay(Capsule().stroke(Color.ink.line, lineWidth: 1))
            .fixedSize()
            .accessibilityHidden(true)
    }

    /// "1 kişi · 1 konum": the people and places an event links, as the drawing's meta line.
    private func programEventMeta(_ segments: [InkLinkSegment], subLineCount: Int, isSelected: Bool) -> String? {
        let bundle = PresentationLocalization.bundle(locale)
        let people = Set(segments.filter { $0.kind == .person }.map { $0.target ?? $0.text }).count
        let places = Set(segments.filter { $0.kind == .place }.map { $0.target ?? $0.text }).count
        var parts: [String] = []
        if people > 0 { parts.append(String(localized: "\(people) kişi", bundle: bundle, locale: locale)) }
        if places > 0 { parts.append(String(localized: "\(places) konum", bundle: bundle, locale: locale)) }
        if !isSelected, subLineCount > 0 {
            parts.append(String(localized: "\(subLineCount) alt satır", bundle: bundle, locale: locale))
        }
        return parts.isEmpty ? nil : parts.joined(separator: " · ")
    }

    /// The bar's colour: a person's link wins, then a place's; an unlinked event stays neutral.
    private static func programBar(_ segments: [InkLinkSegment]) -> Color {
        if segments.contains(where: { $0.kind == .person }) { return Color.ink.person }
        if segments.contains(where: { $0.kind == .place }) { return Color.ink.place }
        return Color.ink.control
    }

    @ViewBuilder
    private func programEventCard(
        entryID: String, event: EventRow, time: String?, isSelected: Bool,
        entitiesByID: [String: EntitySummary]
    ) -> some View {
        let segments = InkLinkMapping.segments(from: event.text, entitiesByID: entitiesByID)
        let allLines = DaySchedulePresentation.splitSegmentsByLine(segments)
        let firstSegments = allLines.first ?? []
        let subLines = Array(allLines.dropFirst())
        let meta = programEventMeta(segments, subLineCount: subLines.count, isSelected: isSelected)
        let kind = PresentationLocalization.string(localized: "Olay", locale: locale)
        let edit = { editingScheduleEvent = EventEditorModel(store: store, day: date, row: event) }

        HStack(alignment: .center, spacing: 12) {
            VStack(alignment: .leading, spacing: 3) {
                InkLinkedText(
                    segments: firstSegments, font: .ink.content,
                    openURL: { openScheduleLink($0) }
                )
                .frame(maxWidth: .infinity, alignment: .leading)
                if let meta {
                    Text(verbatim: meta)
                        .font(.ink.meta)
                        .foregroundStyle(Color.ink.secondaryText)
                }
                if isSelected, !subLines.isEmpty {
                    ForEach(Array(subLines.enumerated()), id: \.offset) { _, subSegments in
                        InkLinkedText(
                            segments: subSegments, font: .ink.contentSmall,
                            isMuted: true, openURL: { openScheduleLink($0) })
                    }
                    .padding(.top, 2)
                }
            }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(
                Text(verbatim: Self.scheduleSpokenLabel(time: time, text: firstSegments.map(\.text).joined()))
            )
            .accessibilityValue(
                Text(
                    verbatim: ([kind] + [meta].compactMap { $0 }
                        + (isSelected ? subLines.map { $0.map(\.text).joined() } : []))
                        .joined(separator: ", "))
            )
            .accessibilityAddTraits(isSelected ? [.isButton, .isSelected] : .isButton)
            .accessibilityAction { tapScheduleCard(entryID, edit: edit) }
            .accessibilityAction(named: Text("Metni düzenle"), edit)
            .accessibilityAction(named: Text("Sil")) { deletingScheduleEvent = event }

            programKind("Olay")
        }
        .modifier(
            ProgramRowChrome(
                bar: Self.programBar(segments), isSelected: isSelected, isFinished: false,
                hairline: InkStroke.hairline(scale: displayScale))
        )
        .onTapGesture { tapScheduleCard(entryID, edit: edit) }
        .contextMenu {
            Button(action: edit) {
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
    private func programTaskCard(
        entryID: String, task: TaskRow, time: String?, isSelected: Bool,
        entitiesByID: [String: EntitySummary]
    ) -> some View {
        let box = TaskBoxPresentation(row: task, isCompleted: tasksModel.completed.contains(task.id))
        let isCompleted = box.state.isCompleted
        let segments = scheduleTaskSegments(for: task, isTimed: time != nil, entitiesByID: entitiesByID)
        let canToggle =
            !isCompleted && !tasksModel.completing.contains(task.id) && !store.isWriting && store.canAddEvent
        let meta = scheduleTaskMeta(for: task, isCompleted: isCompleted)
        let dates = isSelected ? scheduleTaskDates(task) : nil
        let edit = { editingScheduleTask = TaskEditorModel(store: store, row: task) }

        HStack(alignment: .center, spacing: 12) {
            TaskBox(
                state: box.state,
                action: canToggle ? { Task { await tasksModel.complete(task) } } : nil,
                accessibilityLabel: isCompleted ? "Tamamlandı" : "Görevi tamamla"
            )

            VStack(alignment: .leading, spacing: 3) {
                InkLinkedText(
                    segments: segments, font: .ink.content, isMuted: isCompleted,
                    openURL: { openScheduleLink($0) }
                )
                .frame(maxWidth: .infinity, alignment: .leading)
                Text(verbatim: meta)
                    .font(.ink.meta)
                    .foregroundStyle(Color.ink.secondaryText)
                if let dates {
                    Text(verbatim: dates)
                        .font(.ink.meta)
                        .foregroundStyle(Color.ink.secondaryText)
                }
            }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(
                Text(verbatim: Self.scheduleSpokenLabel(time: time, text: segments.map(\.text).joined()))
            )
            .accessibilityValue(Text(verbatim: [meta, dates].compactMap { $0 }.joined(separator: ", ")))
            .accessibilityAddTraits(isSelected ? [.isButton, .isSelected] : .isButton)
            .accessibilityAction { tapScheduleCard(entryID, edit: edit) }
            .accessibilityAction(named: Text("Metni düzenle"), edit)
            .accessibilityAction(named: Text("Sil")) { deletingScheduleTask = task }

            programKind("Görev")
        }
        .modifier(
            ProgramRowChrome(
                bar: isCompleted ? Color.ink.tertiaryText : Color.ink.accent, isSelected: isSelected,
                isFinished: isCompleted, hairline: InkStroke.hairline(scale: displayScale))
        )
        .onTapGesture { tapScheduleCard(entryID, edit: edit) }
        .contextMenu {
            Button(action: edit) {
                Label("Metni düzenle", systemImage: "pencil")
            }
            Button(role: .destructive) {
                deletingScheduleTask = task
            } label: {
                Label("Sil", systemImage: "trash")
            }
        }
    }

    private var scheduleChevron: some View {
        Image(systemName: "chevron.right")
            .font(.ink.meta.weight(.semibold))
            .foregroundStyle(Color.ink.tertiaryText)
            .accessibilityHidden(true)
    }

    /// First tap selects the card, the second opens its editor.
    private func tapScheduleCard(_ entryID: String, edit: () -> Void) {
        if selectedScheduleItemID == entryID { edit() } else { selectedScheduleItemID = entryID }
    }

    /// The card's frame: `accentSoft` and an accent rule while selected.
    private func scheduleCardChrome(isSelected: Bool) -> some ViewModifier {
        ScheduleCardChrome(isSelected: isSelected, hairline: InkStroke.hairline(scale: displayScale))
    }

    /// The card's spoken label: its time (when it has one), then its text. The meta line is its value.
    static func scheduleSpokenLabel(time: String?, text: String) -> String {
        ([time].compactMap { $0 } + [text]).joined(separator: ", ")
    }

    @ViewBuilder
    private func scheduleEventCard(
        entryID: String, event: EventRow, time: String?, isSelected: Bool,
        entitiesByID: [String: EntitySummary]
    ) -> some View {
        let allLines = DaySchedulePresentation.splitSegmentsByLine(
            InkLinkMapping.segments(from: event.text, entitiesByID: entitiesByID))
        let firstSegments = allLines.first ?? []
        let subLines = Array(allLines.dropFirst())
        let meta = scheduleEventMeta(subLineCount: subLines.count, isSelected: isSelected)
        let edit = { editingScheduleEvent = EventEditorModel(store: store, day: date, row: event) }

        // The drawing's card: an icon box on the leading side, "›" on the trailing one, no rule.
        HStack(alignment: .center, spacing: 12) {
            Image(systemName: "pencil")
                .font(.ink.meta.weight(.semibold))
                .foregroundStyle(isSelected ? Color.ink.accent : Color.ink.text)
                .frame(width: scheduleIconBox, height: scheduleIconBox)
                .background(
                    RoundedRectangle(cornerRadius: InkCorner.xs, style: .continuous)
                        .fill(isSelected ? Color.ink.surface : Color.ink.well)
                )
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 4) {
                InkLinkedText(
                    segments: firstSegments, font: .ink.content,
                    openURL: { openScheduleLink($0) }
                )
                .frame(maxWidth: .infinity, alignment: .leading)

                Text(verbatim: meta)
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
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(
                Text(
                    verbatim: Self.scheduleSpokenLabel(
                        time: time, text: firstSegments.map(\.text).joined()))
            )
            .accessibilityValue(
                Text(
                    verbatim: ([meta] + (isSelected ? subLines.map { $0.map(\.text).joined() } : []))
                        .joined(separator: ", "))
            )
            .accessibilityAddTraits(isSelected ? [.isButton, .isSelected] : .isButton)
            .accessibilityAction { tapScheduleCard(entryID, edit: edit) }
            .accessibilityAction(named: Text("Metni düzenle"), edit)
            .accessibilityAction(named: Text("Sil")) { deletingScheduleEvent = event }

            scheduleChevron
        }
        .modifier(scheduleCardChrome(isSelected: isSelected))
        .onTapGesture { tapScheduleCard(entryID, edit: edit) }
        .contextMenu {
            Button(action: edit) {
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
        entryID: String, task: TaskRow, time: String?, isSelected: Bool,
        entitiesByID: [String: EntitySummary]
    ) -> some View {
        let box = TaskBoxPresentation(row: task, isCompleted: tasksModel.completed.contains(task.id))
        let isCompleted = box.state.isCompleted
        let segments = scheduleTaskSegments(for: task, isTimed: time != nil, entitiesByID: entitiesByID)
        // The box only closes a task: completing again does nothing, so a closed box has no action.
        let canToggle =
            !isCompleted && !tasksModel.completing.contains(task.id) && !store.isWriting && store.canAddEvent
        let meta = scheduleTaskMeta(for: task, isCompleted: isCompleted)
        let dates = isSelected ? scheduleTaskDates(task) : nil
        let edit = { editingScheduleTask = TaskEditorModel(store: store, row: task) }

        HStack(alignment: .center, spacing: 12) {
            TaskBox(
                state: box.state,
                action: canToggle ? { Task { await tasksModel.complete(task) } } : nil,
                accessibilityLabel: isCompleted ? "Tamamlandı" : "Görevi tamamla"
            )

            VStack(alignment: .leading, spacing: 4) {
                InkLinkedText(
                    segments: segments, font: .ink.content, isMuted: isCompleted,
                    openURL: { openScheduleLink($0) }
                )
                .frame(maxWidth: .infinity, alignment: .leading)

                Text(verbatim: meta)
                    .font(.ink.meta)
                    .foregroundStyle(Color.ink.secondaryText)

                // The selected card's note line: the task's dates.
                if let dates {
                    Text(verbatim: dates)
                        .font(.ink.meta)
                        .foregroundStyle(Color.ink.secondaryText)
                }
            }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(
                Text(verbatim: Self.scheduleSpokenLabel(time: time, text: segments.map(\.text).joined()))
            )
            .accessibilityValue(Text(verbatim: [meta, dates].compactMap { $0 }.joined(separator: ", ")))
            .accessibilityAddTraits(isSelected ? [.isButton, .isSelected] : .isButton)
            .accessibilityAction { tapScheduleCard(entryID, edit: edit) }
            .accessibilityAction(named: Text("Metni düzenle"), edit)
            .accessibilityAction(named: Text("Sil")) { deletingScheduleTask = task }

            scheduleChevron
        }
        .modifier(scheduleCardChrome(isSelected: isSelected))
        .onTapGesture { tapScheduleCard(entryID, edit: edit) }
        .contextMenu {
            Button(action: edit) {
                Label("Metni düzenle", systemImage: "pencil")
            }
            Button(role: .destructive) {
                deletingScheduleTask = task
            } label: {
                Label("Sil", systemImage: "trash")
            }
        }
    }

    /// "Bitiş: 1 Eki · Başlangıç: 28 Eyl"; nil when the task carries no date.
    private func scheduleTaskDates(_ task: TaskRow) -> String? {
        let bundle = PresentationLocalization.bundle(locale)
        func day(_ value: CalendarDate) -> String {
            LocalDay.instant(for: value).formatted(Date.FormatStyle(locale: locale).day().month(.abbreviated))
        }
        var parts: [String] = []
        if let start = task.start {
            parts.append(String(localized: "Başlangıç: \(day(start))", bundle: bundle, locale: locale))
        }
        if let due = task.due { parts.append(String(localized: "Bitiş: \(day(due))", bundle: bundle, locale: locale)) }
        if let done = task.done {
            parts.append(String(localized: "Tamamlandı: \(day(done))", bundle: bundle, locale: locale))
        }
        return parts.isEmpty ? nil : parts.joined(separator: " · ")
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

    /// Mac Today desk: the right panel beside the page when the detail column is wide enough.
    private func deskPanel(
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
        private func deskPanelSections(
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
        private func deskCloseDayLabel(
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
    private var closeDayEntry: some View {
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

    @ViewBuilder private var diarySection: some View {
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

    private var diaryPreview: some View {
        DayDiaryPreview(isLoaded: day != nil, preview: day?.preview)
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

    /// Events are the day file's; tasks written in `dayFile` take their place among them by line,
    /// so "Saatsiz" follows the file. Tasks from other files (due on the day) come after, in the
    /// order given.
    init(events: [EventRow], tasks: [TaskRow], dayFile: String? = nil) {
        var combined: [DayScheduleEntry] = events.map { event in
            DayScheduleEntry(
                id: "event-\(event.id)-\(event.sourceLine)", time: event.time,
                fileOrder: event.sourceLine, kind: .event(event))
        }
        let lastLine = (events.map(\.sourceLine) + tasks.map(\.sourceLine)).max() ?? 0
        for (index, task) in tasks.enumerated() {
            let inDayFile = dayFile != nil && task.file == dayFile
            combined.append(
                DayScheduleEntry(
                    id: "task-\(task.id)", time: Self.extractLeadingTime(from: task.text.plainText),
                    fileOrder: inDayFile ? task.sourceLine : lastLine + 1 + index, kind: .task(task)))
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
struct DayDiaryPreview: View {
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
                    .inkDiaryParagraph()
                    .frame(maxWidth: .infinity, alignment: .leading)
                Label {
                    Text(
                        verbatim: String(
                            localized: "Devamını yaz",
                            bundle: PresentationLocalization.bundle(locale), locale: locale))
                } icon: {
                    Image(systemName: "pencil")
                }
                .font(.subheadline.weight(.semibold))
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

/// The short date a page pushed from a past day shows on its back item (unit-tested): day and
/// abbreviated month ("17 Eyl"), with the year when it is not this year's.
enum DayBackLabel {
    static func text(for date: CalendarDate, today: CalendarDate, locale: Locale, calendar: Calendar) -> String {
        let resolved = PresentationLocalization.resolvedLocale(locale)
        var style = Date.FormatStyle(locale: resolved, calendar: calendar, timeZone: calendar.timeZone)
            .day().month(.abbreviated)
        if date.year != today.year { style = style.year() }
        return LocalDay.instant(for: date, timeZone: calendar.timeZone).formatted(style)
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

/// A past-day schedule card's frame: surface and a hairline, `accentSoft` and an accent rule while
/// selected.
private struct ScheduleCardChrome: ViewModifier {
    let isSelected: Bool
    let hairline: CGFloat

    func body(content: Content) -> some View {
        content
            .padding(InkSpacing.cardPadding)
            .background {
                RoundedRectangle(cornerRadius: InkCorner.card, style: .continuous)
                    .fill(isSelected ? Color.ink.accentSoft : Color.ink.surface)
            }
            .overlay {
                RoundedRectangle(cornerRadius: InkCorner.card, style: .continuous)
                    .stroke(isSelected ? Color.ink.accent : Color.ink.rule, lineWidth: hairline)
            }
            .contentShape(Rectangle())
    }
}

/// A "Program" row's frame (drawing `j-mac2`): a well with a hairline and a 4 pt coloured bar on
/// the leading edge; a finished task is dashed on the paper; the selected row takes the accent.
private struct ProgramRowChrome: ViewModifier {
    let bar: Color
    let isSelected: Bool
    let isFinished: Bool
    let hairline: CGFloat

    func body(content: Content) -> some View {
        let shape = RoundedRectangle(cornerRadius: InkCorner.xs, style: .continuous)
        content
            .padding(.vertical, 10)
            .padding(.leading, 22)
            .padding(.trailing, 14)
            .frame(maxWidth: .infinity, minHeight: TapTarget.minimumLength, alignment: .leading)
            .background {
                shape.fill(isSelected ? Color.ink.accentSoft : (isFinished ? Color.clear : Color.ink.well))
            }
            .overlay {
                if isFinished && !isSelected {
                    shape.stroke(Color.ink.line, style: StrokeStyle(lineWidth: 1, dash: [4, 3]))
                } else {
                    shape.stroke(isSelected ? Color.ink.accent : Color.ink.rule, lineWidth: hairline)
                }
            }
            .overlay(alignment: .leading) {
                Capsule()
                    .fill(bar)
                    .frame(width: 4)
                    .padding(.vertical, 10)
                    .padding(.leading, 8)
                    .accessibilityHidden(true)
            }
            .contentShape(Rectangle())
    }
}

/// Mac Today desk: the page and, when the detail is wide enough, the right panel beside it. The
/// page keeps its identity when the panel comes and goes. Elsewhere the page alone.
private struct TodayDeskColumns: ViewModifier {
    let panel: AnyView?

    func body(content: Content) -> some View {
        #if os(macOS)
            HStack(spacing: 0) {
                content
                if let panel { panel }
            }
        #else
            content
        #endif
    }
}

#if os(iOS)
    /// Today hides the navigation bar; a past day adds nothing of its own.
    private struct TodayHiddenBar: ViewModifier {
        let isToday: Bool

        @ViewBuilder func body(content: Content) -> some View {
            if isToday {
                content.toolbar(.hidden, for: .navigationBar)
            } else {
                content
            }
        }
    }
#endif

/// Pages pushed from a past day show its short date on their back item ("‹ 17 Eyl", drawing);
/// the destinations sit outside the day's own title modifier, so they would read the tab's name.
private struct DayBackTitle: ViewModifier {
    let title: String?

    @ViewBuilder func body(content: Content) -> some View {
        if let title {
            content.environment(\.inkBackTitle, Text(verbatim: title))
        } else {
            content
        }
    }
}
