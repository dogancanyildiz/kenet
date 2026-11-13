import GoalTracking
import SwiftUI
import VaultFormat

extension DayView {
    /// iPad (regular width) and the Mac draw a past day as the wide drawing (`j-mac2`): the
    /// column beside it already holds the calendar, so no week strip; goal cards, then one
    /// "Program" card. The iPhone keeps its week strip and its "Saatsiz" list.
    var usesProgramLayout: Bool {
        #if os(macOS)
            true
        #else
            horizontalSizeClass == .regular
        #endif
    }

    @ViewBuilder
    func pastDayScrollContent(
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
    func programDayContent(
        presented: TodayPresentation, schedule: DaySchedulePresentation,
        entitiesByID: [String: EntitySummary], day: DaySummary?, isEmptyDay: Bool, todayInstant: Date
    ) -> some View {
        VStack(alignment: .leading, spacing: InkSpacing.section) {
            InkScrolledMasthead(mastheadBlock(presented, todayInstant: todayInstant))

            dayStatusChrome(isEmptyDay: isEmptyDay, emptyCopy: "Bu gün henüz bir şey yazılmadı.")

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
    func compactPastDayContent(
        presented: TodayPresentation, schedule: DaySchedulePresentation,
        entitiesByID: [String: EntitySummary], day: DaySummary?, isEmptyDay: Bool, todayInstant: Date
    ) -> some View {
        VStack(alignment: .leading, spacing: InkSpacing.section) {
            InkScrolledMasthead(mastheadBlock(presented, todayInstant: todayInstant))

            dayStatusChrome(isEmptyDay: isEmptyDay, emptyCopy: "Bu gün henüz bir şey yazılmadı.")

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
}
