import GoalTracking
import SwiftUI
import VaultFormat

extension DayView {
    @ViewBuilder
    func mastheadBlock(_ presented: TodayPresentation, todayInstant: Date) -> some View {
        if isToday {
            todayHeader(presented, compact: false)
        } else {
            pastDayHeaderBlock(presented, todayInstant: todayInstant)
        }
    }

    /// Today's manşet: the day header with the goal ring.
    func todayHeader(_ presented: TodayPresentation, compact: Bool) -> some View {
        let total = presented.goalCount
        return dayHeader(
            presented,
            progress: TodayDayRing.progress(completed: presented.completedGoalCount, total: total),
            remaining: TodayDayRing.remaining(completed: presented.completedGoalCount, total: total),
            total: total, compact: compact,
            instant: LocalDay.instant(for: date, timeZone: calendarValue.timeZone))
    }

    func dayHeader(
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
    var usesWideMasthead: Bool {
        #if os(iOS)
            horizontalSizeClass == .regular
        #else
            false
        #endif
    }

    /// Today's pinned one-line manşet once the page scrolls (drawing): a small ring without its
    /// number, "20 Eylül" with the weekday in secondary ink, and search alone.
    func todayCompactHeader(_ presented: TodayPresentation) -> some View {
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

    func compactTitle(_ instant: Date) -> some View {
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

    func weekStrip(todayInstant: Date) -> some View {
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

    func handleWeekDay(_ picked: CalendarDate, today: CalendarDate) {
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

    var chipRow: some View {
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
    var monthPickerButton: some View {
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
    func pastDayCounts(_ presented: TodayPresentation) -> String? {
        guard day != nil else { return nil }
        let tasks = tasksModel.rows?.count ?? 0
        guard presented.eventCount > 0 || tasks > 0 else { return nil }
        return String(
            localized: "\(presented.eventCount) olay · \(tasks) görev",
            bundle: PresentationLocalization.bundle(locale), locale: locale)
    }

    func pastDayHeaderBlock(_ presented: TodayPresentation, todayInstant: Date) -> some View {
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
    func wideDayTitleBlock(_ presented: TodayPresentation) -> some View {
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
    var goalRecordCount: Int {
        let model = goalModels.model(store: store, day: date)
        return model.goals.filter { model.value(for: $0) != nil }.count
    }

    func wideDayCounts(_ presented: TodayPresentation) -> Text? {
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
    func compactPastDayHeader(_ presented: TodayPresentation, todayInstant: Date) -> some View {
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

    func pastDayTitle(_ presented: TodayPresentation) -> some View {
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
}
