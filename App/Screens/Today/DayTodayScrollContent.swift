import GoalTracking
import SwiftUI
import VaultFormat

extension DayView {
    @ViewBuilder
    func todayScrollContent(
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

            dayStatusChrome(
                isEmptyDay: isEmptyDay,
                emptyCopy: isToday
                    ? "Gününden bir an yaz; @ ile kişi ekle"
                    : "Bu gün henüz bir şey yazılmadı.")

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

    /// Index progress, error band, and empty-day copy shared by today and past-day scroll bodies.
    @ViewBuilder
    func dayStatusChrome(isEmptyDay: Bool, emptyCopy: LocalizedStringKey) -> some View {
        if store.isProcessing && !store.isWriting {
            InkProgress(kind: .indeterminate(label: "İndeks güncelleniyor…"))
        }
        if let error = store.errorText {
            InfoBand(kind: .error, verbatim: error)
        }
        if isEmptyDay { EmptyState(emptyCopy) }
    }
}
