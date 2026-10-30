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
    // Optional: hosted tests build the screen without the app's navigation object.
    @Environment(IntentNavigation.self) private var intentNavigation: IntentNavigation?
    @Environment(NotificationService.self) private var notifications
    @Environment(CalendarService.self) private var calendar
    @Environment(\.locale) private var locale
    @Environment(\.calendar) private var calendarValue
    @Environment(\.clockNow) private var clockNow
    @Environment(\.openSettings) private var openSettings
    @Environment(\.displayScale) private var displayScale
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

    init(store: IndexStore, date: CalendarDate, isToday: Bool = false) {
        self.store = store
        self.date = date
        self.isToday = isToday
        _tasksModel = State(initialValue: DayTasksModel(store: store, day: date, isToday: isToday))
    }

    /// The queried day, once it is this date's. Until then the day's own sections are not drawn,
    /// so the page never shows an empty day that is still loading.
    private var day: DaySummary? { loadedDay?.date == date && tasksModel.isLoaded ? loadedDay : nil }

    private func makePresentation() -> TodayPresentation {
        let today = isToday ? date : LocalDay.today(at: clockNow())
        let goals = loadedGoals?.day == date ? loadedGoals : nil
        // A goal marked on this page counts from the strip's model until an answer has the mark.
        let statuses = goals.map { goalModels.model(store: store, day: date).shownStatuses($0.statuses) }
        return TodayPresentation(
            day: day ?? DaySummary(empty: date), groups: tasksModel.groups, goals: goals?.goals ?? [],
            goalStatuses: statuses ?? [:], goalStatusesDay: goals?.day, today: today, locale: locale,
            calendar: calendarValue,
            completedTasks: tasksModel.completedTasksForPresentation,
            completedTaskIDs: tasksModel.completed,
            isCarriedOverExpanded: isCarriedOverExpanded, isCompletedExpanded: isCompletedExpanded)
    }

    var body: some View {
        let presented = makePresentation()
        let goalModel = goalModels.model(store: store, day: date)
        let entitiesByID = InkLinkMapping.entityIndex(store.content.entities)
        let day = self.day
        let isEmptyDay =
            day.map { $0.events.isEmpty && $0.journal.isEmpty && !$0.hasGoalRecords } == true
            && tasksModel.groups.isEmpty && presented.completedTaskCount == 0
        ScrollView {
            VStack(alignment: .leading, spacing: InkSpacing.section) {
                InkScrolledMasthead(headlineBlock(presented))

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
                    onExpandCompleted: { isCompletedExpanded = true })

                DayCalendarView(date: date)

                if let day, !day.events.isEmpty {
                    VStack(alignment: .leading, spacing: InkSpacing.row) {
                        SectionHeader(
                            title: String(
                                localized: "Olaylar",
                                bundle: PresentationLocalization.bundle(locale), locale: locale),
                            counter: presented.counter(for: .events))
                        ForEach(day.events) { event in
                            DayEventView(
                                store: store, day: date, event: event, entityIndex: entitiesByID)
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
        }
        // The stack's own top pad stays under the pinned strip: the gap below the manşet is the same.
        .inkPinnedMasthead(
            headlineBlock(presented),
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
        }
        // The strip's goals and history, for the page's day and publish.
        .task(id: DayRequest(date: date, updated: store.lastUpdated)) {
            await goalModels.model(store: store, day: date).load()
        }
        .task(id: DayTasksRequest(model: ObjectIdentifier(tasksModel), updated: store.lastUpdated)) {
            await tasksModel.load()
        }
        .onChange(of: date) { _, newDate in
            tasksModel = DayTasksModel(store: store, day: newDate, isToday: isToday)
            isCarriedOverExpanded = false
            isCompletedExpanded = false
        }
        .navigationDestination(isPresented: $showsDayGraph) {
            GraphView(store: store, scope: .day(date))
        }
        .navigationDestination(item: $goalDestination) { route in
            // As the Goals list opens it: the page's own day is today.
            GoalDetailView(store: store, goal: route.goal, day: LocalDay.today(at: clockNow()))
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
                    goals: goalModels.model(store: store, day: date), step: route.step)
            }
            .inkAdaptiveFormPresentation()
        }
        .onChange(of: notifications.navigationRequest?.id, initial: true) { openCloseDayFromReminder() }
        .onChange(of: store.lastUpdated == nil) { openCloseDayFromReminder() }
        .onChange(of: tasksModel.isCurrent) { openCloseDayFromReminder() }
        .onChange(of: goalModel.isCurrent) { openCloseDayFromReminder() }
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

    /// Manşet row: the day's graph (while the day links an entity), Settings (Today, phone only),
    /// then search, rightmost. A past day keeps the graph and search; its bar holds nothing but the
    /// back button.
    private func headlineBlock(_ presented: TodayPresentation) -> some View {
        InkPageHeader(
            verbatim: presented.headline, shortTitle: presented.shortHeadline,
            byline: day == nil ? nil : presented.byline, fitsOneLine: isToday
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

    /// A link row under a thin rule; no section title of its own.
    private var closeDayEntry: some View {
        VStack(alignment: .leading, spacing: 0) {
            Rectangle()
                .fill(Color.ink.rule)
                .frame(height: InkStroke.hairline(scale: displayScale))
                .accessibilityHidden(true)
            Button("Günü kapat") { closeDayRoute = CloseDayRoute(step: .tasks) }
                .buttonStyle(InkTextButtonStyle())
                .accessibilityIdentifier("button.closeDay")
        }
    }

    @ViewBuilder private var journalSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            SectionHeader(
                title: String(
                    localized: "Günlük yazısı",
                    bundle: PresentationLocalization.bundle(locale), locale: locale))
            #if os(iOS)
                Button {
                    journalPresented.wrappedValue = true
                } label: {
                    journalPreview
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Günlük yazısını düzenle")
            #else
                NavigationLink {
                    JournalView(store: store, date: date)
                } label: {
                    journalPreview
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
