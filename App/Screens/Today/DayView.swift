import GoalTracking
import SwiftUI
import VaultFormat

/// Stable identity for ``GoalStripView`` so ``GoalDayModel`` rebuilds per day/vault.
enum GoalStripIdentity {
    static func key(day: CalendarDate, vaultPath: String?) -> String {
        day.description + (vaultPath ?? "")
    }
}

/// The same editable layout serves today and a selected historical day.
struct DayView: View {
    let store: IndexStore
    let date: CalendarDate
    var isToday = false
    @Environment(NotificationService.self) private var notifications
    @Environment(CalendarService.self) private var calendar
    @Environment(\.locale) private var locale
    @Environment(\.calendar) private var calendarValue
    @Environment(\.clockNow) private var clockNow
    @Environment(\.openSettings) private var openSettings
    @State private var showsJournal = false
    @State private var tasksModel: DayTasksModel
    @State private var isCarriedOverExpanded = false
    @State private var isCompletedExpanded = false

    init(store: IndexStore, date: CalendarDate, isToday: Bool = false) {
        self.store = store
        self.date = date
        self.isToday = isToday
        _tasksModel = State(initialValue: DayTasksModel(store: store, day: date, isToday: isToday))
    }

    private var day: DaySummary { store.content.day(on: date) }

    private func makePresentation() -> TodayPresentation {
        let today = isToday ? date : LocalDay.today(at: clockNow())
        let statuses = TodayPresentation.goalStatuses(
            goals: store.content.goals, logs: store.content.goalLogs, day: date)
        return TodayPresentation(
            day: day, groups: tasksModel.groups, goals: store.content.goals, goalStatuses: statuses,
            goalStatusesDay: date, today: today, locale: locale, calendar: calendarValue,
            completedTasks: tasksModel.completedTasksForPresentation,
            completedTaskIDs: tasksModel.completed,
            isCarriedOverExpanded: isCarriedOverExpanded, isCompletedExpanded: isCompletedExpanded)
    }

    var body: some View {
        let presented = makePresentation()
        let entitiesByID = InkLinkMapping.entityIndex(store.content.entities)
        let isEmptyDay =
            day.events.isEmpty && day.journal.isEmpty && tasksModel.groups.isEmpty
            && !day.hasGoalRecords && presented.completedTaskCount == 0
        ScrollView {
            VStack(alignment: .leading, spacing: InkSpacing.section) {
                headlineBlock(presented)

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

                GoalStripView(
                    store: store, day: date, countedGoalIDs: presented.countedGoalIDs,
                    counter: presented.counter(for: .goals)
                )
                .id(GoalStripIdentity.key(day: date, vaultPath: store.vaultURL?.path))

                DayTasksView(
                    store: store, date: date, isToday: isToday, model: tasksModel,
                    presentation: presented, entityIndex: entitiesByID,
                    onExpandCarriedOver: { isCarriedOverExpanded = true },
                    onExpandCompleted: { isCompletedExpanded = true })

                DayCalendarView(date: date)

                if !day.events.isEmpty {
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
            }
            .padding(.horizontal, InkSpacing.margin)
            .padding(.top, 8)
            // `safeAreaInset` already reserves the capsule; only a small page pad here.
            .padding(.bottom, 8)
            .inkPageColumn()
        }
        .inkPage()
        .safeAreaInset(edge: .bottom) {
            QuickEntryBar(
                store: store, isEnabled: true, day: isToday ? nil : date,
                focusRequest: isToday && notifications.navigationRequest?.destination == .journal
                    ? notifications.navigationRequest?.id : nil, acceptsPeopleMentions: isToday
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
        .task(id: date) {
            if AppLaunchPolicy.allowsAutomaticStart() { await calendar.load(date) }
        }
        .onChange(of: date) { _, newDate in
            tasksModel = DayTasksModel(store: store, day: newDate, isToday: isToday)
            isCarriedOverExpanded = false
            isCompletedExpanded = false
        }
        .sheet(isPresented: $showsJournal) {
            NavigationStack { JournalView(store: store, date: date) }
        }
    }

    /// Manşet row: Settings (Today, phone only) then search, rightmost. A past day keeps only
    /// search; its bar holds nothing but the back button.
    private func headlineBlock(_ presented: TodayPresentation) -> some View {
        InkPageHeader(
            verbatim: presented.headline, shortTitle: presented.shortHeadline,
            byline: presented.byline, fitsOneLine: isToday
        ) {
            if isToday, let openSettings {
                InkHeaderAction("Ayarlar", systemImage: "gearshape", identifier: "button.settings") {
                    openSettings()
                }
            }
            SearchButton()
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
                    showsJournal = true
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

    @ViewBuilder private var journalPreview: some View {
        VStack(alignment: .leading, spacing: 6) {
            if let preview = day.preview {
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
            } else {
                Text(
                    verbatim: String(
                        localized: "Günlük yazısı ekle…",
                        bundle: PresentationLocalization.bundle(locale), locale: locale)
                )
                .font(.ink.placeholder)
                .foregroundStyle(Color.ink.secondaryText)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
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
