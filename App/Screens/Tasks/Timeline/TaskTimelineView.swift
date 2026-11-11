import SwiftUI
import VaultFormat
import VaultIndex

struct TaskTimelineView: View {
    @State private var model: TimelineModel
    @State private var selected: TaskRow?
    @State private var editor: TimelineDateSelection?
    @State private var sourceDay: CalendarDate?
    @State private var todayRequest = UUID()
    @State private var periodRequest: TimelinePeriodRequest?
    @State private var selectionAnswer = TaskSelectionAnswer()
    @State private var availableWidth: CGFloat = 0
    @State private var selectedDay: CalendarDate
    @State private var daySummary: DaySummary?
    @State private var weekSummaries: [DaySummary] = []
    @State private var eventEditor: EventEditorModel?
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @Environment(\.shellKind) private var shellKind
    @Environment(\.calendar) private var calendar
    /// `true` when the Mac shell hosts the timeline full-width (outside ``TasksView``).
    let showsFilters: Bool
    let openDay: (String) -> Void

    init(tasks: TasksModel, showsFilters: Bool = false, openDay: @escaping (String) -> Void = { _ in }) {
        _model = State(initialValue: TimelineModel.board(for: tasks))
        _selectedDay = State(initialValue: tasks.day)
        self.showsFilters = showsFilters
        self.openDay = openDay
    }
    var body: some View {
        VStack(spacing: 0) {
            if style == .desktop {
                desktop
            } else {
                detailSheet(mobileContent, item: $selected)
            }
        }
        // No paper here: the page's ``View/inkPage()`` draws it, with the glow on the tab shell.
        #if os(iOS)
            .onGeometryChange(for: CGFloat.self) {
                $0.size.width
            } action: {
                availableWidth = $0
            }
        #endif
        .boardNavigationTitle(showsFilters ? "Zaman çizelgesi" : nil)
        .sheet(item: $editor) { selection in
            NavigationStack { TimelineDateEditor(model: model, selection: selection) }
                .frame(minWidth: 320, minHeight: 200).inkAdaptiveSheetPresentation(fitsContent: true)
        }
        .sheet(item: $eventEditor) { event in
            NavigationStack { EventTextEditor(model: event) }
                .inkAdaptiveSheetPresentation()
                .frame(minWidth: 320, minHeight: 200)
        }
        .onChange(of: model.store.vaultURL) { _, _ in
            model.clearInteraction()
            selected = nil
            editor = nil
            sourceDay = nil
        }
        .onChange(of: selected?.id) { _, _ in sourceDay = nil }
        .task(id: model.request) { await model.load() }
        .task(id: TimelineDayRequest(date: selectedDay, updated: model.store.lastUpdated, scale: model.scale)) {
            guard model.scale == .day else {
                daySummary = nil
                return
            }
            daySummary = nil
            daySummary = try? await model.store.computeDay(on: selectedDay)
        }
        .task(id: TimelineWeekRequest(date: selectedDay, updated: model.store.lastUpdated, scale: model.scale)) {
            guard model.scale == .week else {
                weekSummaries = []
                return
            }
            var loaded: [DaySummary] = []
            for date in weekDates {
                guard !Task.isCancelled else { return }
                if let summary = try? await model.store.computeDay(on: LocalDay.today(at: date)) {
                    loaded.append(summary)
                }
            }
            weekSummaries = loaded
        }
        .task(id: TaskSelectionRequest(id: selected?.id, updated: model.store.lastUpdated)) {
            let request = TaskSelectionRequest(id: selected?.id, updated: model.store.lastUpdated)
            if let answer = await TaskSelectionAnswer.load(request, store: model.store) { selectionAnswer = answer }
        }
    }

    private var style: TimelineLayoutStyle { TimelineLayoutStyle.resolve(shell: shellKind) }

    private var usesPanel: Bool { TimelineDetailPlacement.usesPanel(shell: shellKind, width: availableWidth) }

    /// The chart with the detail panel beside it: the Mac window, and the split iOS shell while
    /// the panel fits (narrower, the detail opens in a sheet as on the phone).
    @ViewBuilder private var desktop: some View {
        TasksPageTop(
            tasks: model.tasks, current: .timeline, byline: showsFilters ? hostedByline : byline,
            title: showsFilters ? "Zaman çizelgesi" : "Görevler", showsTabs: !showsFilters,
            titleAccessory: showsFilters ? AnyView(periodPill) : nil
        ) {
            // Gün and Hafta boards are not grouped (screens.md "Mac gruplama": Hafta-Çeyrek chart).
            if model.scale.showsGrouping { groupingMenu }
        } menu: {
            controls
        }
        if let error = model.errorText {
            InfoBand(kind: .error, verbatim: error)
                .padding(.horizontal, InkSpacing.margin)
        }
        #if os(macOS)
            chartWithPanel(showsPanel: true)
        #else
            // One branch whatever the width: crossing the panel threshold keeps the chart (and
            // its scroll position); only the panel comes and goes.
            detailSheet(
                chartWithPanel(showsPanel: usesPanel),
                item: Binding(
                    get: { availableWidth > 0 && !usesPanel ? selected : nil },
                    set: { if !usesPanel { selected = $0 } }))
        #endif
    }

    private var chart: some View {
        Group {
            if model.scale == .day {
                ScrollView(.vertical) { dayBoard }
            } else if model.scale == .week {
                ScrollView(.vertical) { weekBoard }
            } else {
                TimelineDesktopView(model: model, todayRequest: todayRequest, periodRequest: periodRequest) {
                    selected = $0
                } edit: {
                    editor = TimelineDateSelection(row: $0, edge: $1, root: model.store.vaultURL)
                }
            }
        }
    }

    private var dayBoard: some View {
        TimelineDayBoard(
            store: model.store, day: selectedDay, today: model.today,
            events: daySummary?.events ?? [], tasks: dayRows,
            selectTask: { selected = $0 },
            selectEvent: { eventEditor = EventEditorModel(store: model.store, day: selectedDay, row: $0) },
            selectDay: { selectedDay = $0 })
    }

    private var dayRows: [TaskRow] {
        (model.rows ?? []).filter { row in
            guard row.rawStatus != "-", let span = TimelineDates(row).span(on: model.today) else { return false }
            return span.first <= selectedDay && selectedDay <= span.last
        }
    }

    private var weekDates: [Date] {
        InkWeekStrip.daysInWeek(containing: LocalDay.instant(for: selectedDay), calendar: calendar)
    }

    private var weekBoard: some View {
        TimelineWeekBoard(
            store: model.store, week: weekDates, summaries: weekSummaries, rows: model.rows ?? [], today: model.today,
            selectTask: { selected = $0 },
            selectEvent: { day, event in eventEditor = EventEditorModel(store: model.store, day: day, row: event) })
    }

    private func chartWithPanel(showsPanel: Bool) -> some View {
        HStack(spacing: 0) {
            chart
            if showsPanel, let row = selectedTask {
                Divider().overlay(Color.ink.rule)
                VStack {
                    HStack {
                        Spacer()
                        Button {
                            selected = nil
                        } label: {
                            Label("Kapat", systemImage: "xmark")
                                .labelStyle(.iconOnly)
                                .tapTarget()
                        }
                        .buttonStyle(InkTextButtonStyle())
                    }.padding()
                    // As on the Kanban panel: the stack hides no bar; the column's bar is the shell's.
                    NavigationStack {
                        TaskDetailView(store: model.store, row: row, openDay: openDay)
                    }
                }.frame(width: TimelineDetailPlacement.panelWidth)
            }
        }
    }

    /// The phone's task sheet, also the narrow split shell's: the stack opens the source day itself.
    private func detailSheet(_ content: some View, item: Binding<TaskRow?>) -> some View {
        #if os(iOS)
            content.sheet(item: item) { selection in
                NavigationStack {
                    if let row = selectionAnswer.row(for: selection.id, listed: selection) {
                        TaskDetailView(store: model.store, row: row) { path in
                            sourceDay = CalendarDate(String(path.dropFirst("journal/".count).dropLast(3)))
                        }
                        .navigationDestination(item: $sourceDay) { DayView(store: model.store, date: $0) }
                        .inkSheet("Görev", onClose: { selected = nil })
                    }
                }.inkAdaptiveSheetPresentation()
            }
        #else
            content
        #endif
    }

    private var selectedTask: TaskRow? { selectionAnswer.row(for: selected?.id, listed: selected) }
    /// Second layer of the view selector ("Ölçek") with the period controls on the same row;
    /// they stack at accessibility sizes.
    private var controls: some View {
        Group {
            if dynamicTypeSize.isAccessibilitySize {
                VStack(alignment: .leading, spacing: 0) {
                    scaleTabs
                    HStack(spacing: 8) {
                        todayButton
                        Spacer(minLength: 0)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            } else if style == .desktop {
                // The menu alone sets the row height (the text button is taller on Mac), so
                // the row sits where the other views' menu rows sit. The Çeyrek chart scrolls
                // through the periods itself; Gün and Hafta step a week at a time.
                // A hosted board moves its period from the manşet's pill.
                scaleTabs
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .overlay(alignment: .trailing) {
                        HStack(spacing: 4) {
                            if model.scale != .quarter && !showsFilters { periodButtons }
                            todayButton
                        }
                    }
            } else {
                // Phone: "Ölçek", the scale tabs and "Bugün" on one row (the Çeyrek chart scrolls
                // itself; Gün and Hafta keep the week arrows while they fit beside it).
                ViewThatFits(in: .horizontal) {
                    phoneControlsRow(showsPeriodButtons: model.scale != .quarter)
                    phoneControlsRow(showsPeriodButtons: false)
                    VStack(alignment: .leading, spacing: 0) {
                        scaleTabs
                        HStack {
                            todayButton
                            Spacer()
                            if model.scale != .quarter { periodButtons }
                        }
                    }
                }
            }
        }
    }

    private func phoneControlsRow(showsPeriodButtons: Bool) -> some View {
        // One text baseline for "Ölçek", the scale words and "Bugün" (fark3 P5): centered, the
        // label sat higher than the tab words, which stand at the bottom of their touch target.
        HStack(alignment: .firstTextBaseline, spacing: 10) {
            Text("Ölçek")
                .font(.ink.pageByline)
                .foregroundStyle(.ink.secondaryText)
                .fixedSize()
                .accessibilityHidden(true)
            scaleTabs.fixedSize(horizontal: true, vertical: false)
            Spacer(minLength: 4)
            if showsPeriodButtons { periodButtons }
            todayButton
        }
    }

    private var scaleTabs: some View {
        InkTabs(
            selection: Binding(get: { model.scale }, set: { model.choose($0) }),
            items: [
                InkTabItem("Gün", value: TimelineModel.Scale.day),
                InkTabItem("Hafta", value: TimelineModel.Scale.week),
                InkTabItem("Çeyrek", value: TimelineModel.Scale.quarter),
            ], identifier: "tasks.timeline.scale")
    }

    /// How the chart's rows are grouped: a manşet-row icon, so the menu row holds "Ölçek" alone.
    /// Accent while the grouping is not the default. The phone list groups by day.
    private var groupingMenu: some View {
        InkHeaderMenu(
            "Grupla", systemImage: "rectangle.3.group",
            isActive: model.grouping != TimelineModel.defaultGrouping,
            identifier: "tasks.timeline.grouping"
        ) {
            Picker("Grupla", selection: $model.grouping) {
                Text("Proje").tag(TimelineModel.Grouping.project)
                Text("Kişi").tag(TimelineModel.Grouping.person)
                Text("Yok").tag(TimelineModel.Grouping.none)
            }
            .pickerStyle(.inline)
        }
    }

    private var todayButton: some View {
        Button {
            model.showToday()
            selectedDay = model.today
            todayRequest = UUID()
        } label: {
            // The control row's size (15 pt), as the scale tabs beside it; the label's own font
            // wins over the style's.
            Text("Bugün").font(.ink.pageByline.weight(.semibold))
        }
        .buttonStyle(InkTextButtonStyle())
        .fixedSize(horizontal: true, vertical: false)
        .lineLimit(1)
    }

    /// The hosted chart's period (Şafak drawing: "‹ Eylül – Ekim 2026 ›" beside the manşet
    /// icons): the week on Gün and Hafta, the months on screen on Çeyrek.
    private var periodPill: some View {
        HStack(spacing: 0) {
            periodStep(-1)
            Text(verbatim: periodTitle)
                .font(.ink.pageByline.weight(.semibold))
                .foregroundStyle(.ink.text)
                .monospacedDigit()
                .lineLimit(1)
                .fixedSize()
            periodStep(1)
        }
        .padding(.horizontal, 2)
        .background(Capsule().fill(Color.ink.surface))
        .overlay(Capsule().strokeBorder(Color.ink.line, lineWidth: InkStroke.rule))
        .accessibilityElement(children: .contain)
    }

    private func periodStep(_ direction: Int) -> some View {
        Button {
            shiftPeriod(by: direction)
        } label: {
            Image(systemName: direction < 0 ? "chevron.left" : "chevron.right")
                .font(.ink.meta.weight(.semibold))
                .foregroundStyle(.ink.secondaryText)
                .tapTarget()
        }
        .buttonStyle(.plain)
        .accessibilityLabel(direction < 0 ? Text("Önceki dönem") : Text("Sonraki dönem"))
    }

    private var periodTitle: String {
        switch model.scale {
        case .day, .week:
            guard let first = weekDates.first, let last = weekDates.last else { return "" }
            return (first..<last).formatted(.interval.day().month(.wide).year())
        case .month, .quarter:
            let range = model.visibleRange
            return (LocalDay.instant(for: range.lowerBound)..<LocalDay.instant(for: range.upperBound))
                .formatted(.interval.month(.wide).year())
        }
    }

    /// Künye of the hosted chart: "**8** tarihli görev · 6 proje" on Çeyrek (the months are in
    /// the period pill), the day and its count on Gün, the week's count on Hafta.
    private var hostedByline: Text? {
        switch model.scale {
        case .day:
            return byline
        case .week:
            return Text("\(TasksByline.number(weekRowCount)) görev")
        case .month, .quarter:
            let rows = model.groups.flatMap(\.rows)
            let projects = Set(rows.compactMap { $0.project.map(VaultIndex.projectKey) }).count
            return Text("\(TasksByline.number(rows.count)) tarihli görev · \(projects) proje")
        }
    }

    /// Gün and Hafta move the selected day by a week (the week strip shows one week); the phone
    /// list (Çeyrek) moves the model's window by its period.
    private func shiftPeriod(by direction: Int) {
        switch model.scale {
        case .day, .week:
            selectedDay = selectedDay.addingDays(7 * direction) ?? selectedDay
        case .month, .quarter:
            if style == .desktop {
                // The chart scrolls through the periods itself: a step scrolls it by a month.
                let target = model.visibleRange.lowerBound.addingDays(direction * 30) ?? model.today
                let clamped = min(max(target, model.bounds.lowerBound), model.bounds.upperBound)
                periodRequest = TimelinePeriodRequest(start: clamped)
            } else {
                model.shiftWindow(by: direction * model.scale.daysAcross)
            }
        }
    }

    private var periodButtons: some View {
        HStack(spacing: 4) {
            Button {
                shiftPeriod(by: -1)
            } label: {
                Image(systemName: "chevron.left")
                    .tapTarget()
            }
            .accessibilityLabel("Önceki dönem")
            .buttonStyle(InkTextButtonStyle())
            Button {
                shiftPeriod(by: 1)
            } label: {
                Image(systemName: "chevron.right")
                    .tapTarget()
            }
            .accessibilityLabel("Sonraki dönem")
            .buttonStyle(InkTextButtonStyle())
        }
    }

    private var mobileDayPage: some View {
        VStack(spacing: 0) {
            TasksPageTop(tasks: model.tasks, current: .timeline, byline: byline) { controls }
            if let error = model.errorText {
                InfoBand(kind: .error, verbatim: error)
                    .padding(.horizontal, InkSpacing.margin)
            }
            ScrollView { dayBoard }
        }
        .inkPage()
    }

    @ViewBuilder private var mobileContent: some View {
        if model.scale == .day {
            mobileDayPage
        } else if model.scale == .week {
            mobileWeekPage
        } else {
            mobileChartPage
        }
    }

    /// Çeyrek on the phone: the page top stays, the chart sits in a card under it with the
    /// undated tasks below (screens.md "Çeyrek ölçeği": kartlı Gantt).
    private var mobileChartPage: some View {
        VStack(spacing: 0) {
            TasksPageTop(tasks: model.tasks, current: .timeline, byline: byline) { controls }
            if let error = model.errorText {
                InfoBand(kind: .error, verbatim: error)
                    .padding(.horizontal, InkSpacing.margin)
            }
            TimelineDesktopView(model: model, todayRequest: todayRequest, compact: true) {
                selected = $0
            } edit: {
                editor = TimelineDateSelection(row: $0, edge: $1, root: model.store.vaultURL)
            }
        }
        .inkPage()
    }

    /// Künye under the manşet: the day and its task count (Gün), the week (Hafta), the
    /// months on screen (Çeyrek).
    private var byline: Text? {
        switch model.scale {
        case .day:
            let date = LocalDay.instant(for: selectedDay).formatted(
                .dateTime.day().month(.wide).year().weekday(.wide))
            return Text("\(date) · \(TasksByline.number(dayRows.count)) görev")
        case .week:
            guard let first = weekDates.first, let last = weekDates.last else { return nil }
            let count = weekRowCount
            return Text(
                "\((first..<last).formatted(.interval.day().month(.wide).year())) · \(TasksByline.number(count)) görev")
        case .month, .quarter:
            let range = model.visibleRange
            let start = LocalDay.instant(for: range.lowerBound)
            let end = LocalDay.instant(for: range.upperBound)
            return Text(verbatim: (start..<end).formatted(.interval.month(.wide).year()))
        }
    }

    /// Dated tasks whose span meets the week on screen (Hafta künyesi).
    private var weekRowCount: Int {
        guard let first = weekDates.first.map({ LocalDay.today(at: $0) }),
            let last = weekDates.last.map({ LocalDay.today(at: $0) })
        else { return 0 }
        return (model.rows ?? []).filter { row in
            guard row.rawStatus != "-", let span = TimelineDates(row).span(on: model.today) else { return false }
            return span.first <= last && first <= span.last
        }.count
    }

    private var mobileWeekPage: some View {
        VStack(spacing: 0) {
            TasksPageTop(tasks: model.tasks, current: .timeline, byline: byline) { controls }
            if let error = model.errorText {
                InfoBand(kind: .error, verbatim: error)
                    .padding(.horizontal, InkSpacing.margin)
            }
            ScrollView { weekBoard }
        }
        .inkPage()
    }
}

/// Which timeline the shell draws (unit-tested). The chart, Mac window and split iOS shell
/// (iPad, iPhone Duo inner screen): bars on a day axis that scrolls through the periods, the
/// grouping menu on the manşet row, the detail beside the chart (``TimelineDetailPlacement``).
/// The list, tab shell: rows by day, period buttons beside "Ölçek", the detail in a sheet.
enum TimelineLayoutStyle: Equatable, Sendable {
    case desktop
    case list

    static func resolve(shell: ShellKind) -> Self {
        #if os(macOS)
            .desktop
        #else
            shell == .split ? .desktop : .list
        #endif
    }
}

/// Where the chart's selected task goes (unit-tested). Mac: always the panel. The split iOS
/// shell: the panel while the label column and a readable chart still fit beside it,
/// otherwise the sheet. Tabs: the list's sheet.
enum TimelineDetailPlacement {
    static let panelWidth: CGFloat = 340
    /// The label column plus the narrowest chart ``TimelineDesktopView`` draws.
    static let minimumChartWidth: CGFloat = TimelineDesktopMetrics.labelColumnWidth + 200

    static func usesPanel(shell: ShellKind, width: CGFloat) -> Bool {
        #if os(macOS)
            true
        #else
            shell == .split && width >= panelWidth + minimumChartWidth
        #endif
    }
}

/// A step of the hosted chart's period pill: the first day the chart scrolls to.
struct TimelinePeriodRequest: Equatable {
    let id = UUID()
    let start: CalendarDate
}
