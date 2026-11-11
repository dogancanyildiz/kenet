import Summaries
import SwiftUI
import VaultFormat

/// True once the shown period's summary is loaded and no load runs (snapshot readiness).
struct SummariesReadyKey: PreferenceKey {
    static let defaultValue = false
    static func reduce(value: inout Bool, nextValue: () -> Bool) {
        value = value || nextValue()
    }
}

/// Rhythm strip, the year's written days, weekday written-day ratios, four headline numbers, name
/// chips, goal rows and one stacked task bar. iPhone: one column. Mac: rhythm, written days,
/// weekdays, numbers and goals on the left; people, places and tasks on the right.
struct SummariesView: View {
    let store: IndexStore
    @State private var model: SummariesModel
    @State private var taskFlow: TaskFlowSeries?
    @State private var taskFlowRequest: String?
    @State private var taskFlowError: String?
    /// The year map of the shown year; `yearRequest` is the request key it was read for.
    @State private var yearCalendar: YearWritingCalendar?
    @State private var yearRequest: String?
    @State private var yearError: String?
    /// The weekday written-day ratios of the month or year `weekdaysRange` names; `weekdaysRequest`
    /// is its request key.
    @State private var weekdayDistribution: WeekdayDistribution?
    @State private var weekdaysRange: ClosedRange<CalendarDate>?
    @State private var weekdaysRequest: String?
    private let today: () -> CalendarDate
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @Environment(\.locale) private var locale

    /// Widest Mac page: two columns side by side, not a reading column.
    private static let macPageWidth: CGFloat = 1120

    init(
        store: IndexStore, today: @escaping () -> CalendarDate = { LocalDay.today() },
        period: SummaryPeriod = .week, day: CalendarDate? = nil
    ) {
        self.store = store
        self.today = today
        _model = State(initialValue: SummariesModel(store: store, today: today, period: period, day: day))
    }

    private var masthead: InkPageTitle<some View> {
        InkPageTitle("Özetler") {
            SearchButton()
        }
    }

    var body: some View {
        ScrollView {
            // No gap after the manşet row: the tabs sit right under it (pattern 4).
            VStack(alignment: .leading, spacing: 0) {
                InkScrolledMasthead(masthead)
                VStack(alignment: .leading, spacing: 28) {
                    controls
                    if model.summary == nil, model.isLoading {
                        InkProgress(kind: .indeterminate(label: "Yükleniyor…"))
                    }
                    if let error = model.errorText {
                        InfoBand(kind: .error, verbatim: error)
                    }
                    if let summary = model.summary {
                        if summary.isEmpty {
                            emptyPeriod(summary)
                        } else {
                            content(summary)
                        }
                    }
                }
                .padding(.horizontal, InkSpacing.margin)
            }
            .padding(.bottom, InkSpacing.margin)
            .frame(maxWidth: pageWidth, alignment: .leading)
            .frame(maxWidth: .infinity, alignment: .center)
        }
        .inkPinnedMasthead(masthead, columnWidth: pageWidth)
        .inkPage()
        .inkPageNavigationTitle("Özetler")
        .preference(
            key: SummariesReadyKey.self,
            value: model.summary != nil && !model.isLoading && isYearReady && isWeekdaysReady
                && taskFlowRequest == model.requestKey
        )
        .background {
            // Ticks each minute so the key sees a new day; the page loads again past midnight.
            TimelineView(.periodic(from: .now, by: 60)) { _ in
                Color.clear.task(id: model.requestKey) {
                    await model.load()
                    await loadYear()
                    await loadWeekdays()
                    await loadTaskFlow()
                }
            }
            .accessibilityHidden(true)
        }
        .onChange(of: store.vaultURL) { _, _ in
            model.reset()
            taskFlow = nil
            taskFlowRequest = nil
            taskFlowError = nil
            yearCalendar = nil
            yearRequest = nil
            yearError = nil
            weekdayDistribution = nil
            weekdaysRange = nil
            weekdaysRequest = nil
        }
        #if os(iOS)
            .simultaneousGesture(swipe)
        #endif
    }

    private var pageWidth: CGFloat {
        #if os(macOS)
            Self.macPageWidth
        #else
            InkSpacing.macPageWidth
        #endif
    }

    #if os(iOS)
        /// A horizontal swipe changes the period: to the left goes forward, to the right goes back.
        private var swipe: some Gesture {
            DragGesture(minimumDistance: 24).onEnded { value in
                let dx = value.translation.width
                guard abs(dx) > 60, abs(dx) > abs(value.translation.height) * 2 else { return }
                if dx < 0 { model.next() } else { model.previous() }
            }
        }
    #endif

    // MARK: Controls

    private var controls: some View {
        VStack(alignment: .leading, spacing: 6) {
            InkTabs(
                selection: $model.period,
                items: [
                    InkTabItem("Hafta", value: SummaryPeriod.week, identifier: "tab.summaries.week"),
                    InkTabItem("Ay", value: SummaryPeriod.month, identifier: "tab.summaries.month"),
                    InkTabItem("Yıl", value: SummaryPeriod.year, identifier: "tab.summaries.year"),
                ], identifier: "tabs.summaries.period",
                accessibilityLabelPrefix: PresentationLocalization.string(localized: "Dönem", locale: locale))
            HStack(spacing: 4) {
                Button {
                    model.previous()
                } label: {
                    Image(systemName: "chevron.left")
                        .foregroundStyle(model.canGoPrevious ? Color.ink.accent : Color.ink.control)
                        .tapTarget()
                }
                .accessibilityLabel("Önceki dönem").disabled(!model.canGoPrevious)
                #if os(macOS)
                    .buttonStyle(.plain)
                #endif
                Spacer(minLength: 0)
                // Back to the current period beside the title, not on a row of its own (Şafak
                // çizimi: nothing between the period row and the first card).
                HStack(spacing: 8) {
                    periodTitle
                        .font(.ink.section)
                        .foregroundStyle(Color.ink.text)
                        .multilineTextAlignment(.center)
                    if !model.isCurrent {
                        Button {
                            model.current()
                        } label: {
                            Text(currentTitle)
                                .font(.footnote.weight(.semibold))
                                .foregroundStyle(Color.ink.accent)
                                .padding(.horizontal, 10)
                                .padding(.vertical, 4)
                                .background(Capsule(style: .continuous).fill(Color.ink.accentSoft))
                                .frame(minHeight: TapTarget.minimumLength)
                                .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                    }
                }
                Spacer(minLength: 0)
                Button {
                    model.next()
                } label: {
                    Image(systemName: "chevron.right")
                        .foregroundStyle(model.canGoNext ? Color.ink.accent : Color.ink.control)
                        .tapTarget()
                }
                .accessibilityLabel("Sonraki dönem").disabled(!model.canGoNext)
                #if os(macOS)
                    .buttonStyle(.plain)
                #endif
            }
        }
        #if os(macOS)
            .frame(maxWidth: 520, alignment: .leading)
        #endif
    }

    @ViewBuilder private var periodTitle: some View {
        let range = model.range
        switch model.period {
        case .week:
            Text(
                verbatim: LocalDay.instant(for: range.lowerBound).formatted(
                    Date.FormatStyle(locale: locale).day().month(.abbreviated)) + " – "
                    + LocalDay.instant(for: range.upperBound).formatted(
                        Date.FormatStyle(locale: locale).day().month(.abbreviated).year()))
        case .month:
            Text(
                verbatim: LocalDay.instant(for: range.lowerBound).formatted(
                    Date.FormatStyle(locale: locale).month(.wide).year()))
        case .year:
            Text(verbatim: String(range.lowerBound.year))
        }
    }

    private var currentTitle: LocalizedStringKey {
        switch model.period {
        case .week: "Bu hafta"
        case .month: "Bu ay"
        case .year: "Bu yıl"
        }
    }

    // MARK: Content

    /// One sentence, the open tasks the period hands on, and a way back. Other zero sections are not drawn.
    private func emptyPeriod(_ summary: PeriodSummary) -> some View {
        VStack(spacing: 12) {
            EmptyState("Bu dönemde kayıt yok.")
            if summary.counts.overdueTasks + summary.counts.undatedTasks > 0 {
                Text(
                    verbatim: SummaryPresentation.carried(
                        overdue: summary.counts.overdueTasks, undated: summary.counts.undatedTasks, locale: locale)
                )
                .font(.ink.meta)
                .foregroundStyle(Color.ink.secondaryText)
                .multilineTextAlignment(.center)
                .frame(maxWidth: .infinity)
            }
            if model.canGoPrevious {
                Button {
                    model.previous()
                } label: {
                    // A body-sized link under the sentence, not a title-sized one (drawing: 15 pt
                    // page text); the text button style's own font is the larger byline.
                    Text("Önceki döneme git")
                        .font(.subheadline.weight(.semibold))
                        .tapTarget()
                }
                .buttonStyle(InkTextButtonStyle())
            }
        }
        .frame(maxWidth: .infinity)
    }

    @ViewBuilder
    private func content(_ summary: PeriodSummary) -> some View {
        let kpiColumns = dynamicTypeSize.isAccessibilitySize ? 1 : 3
        #if os(macOS)
            HStack(alignment: .top, spacing: 48) {
                VStack(alignment: .leading, spacing: 20) {
                    stats(summary, columns: kpiColumns)
                    rhythm(summary)
                    writtenDays(summary)
                    weekdays(summary)
                }
                .frame(maxWidth: .infinity, alignment: .topLeading)
                VStack(alignment: .leading, spacing: 20) {
                    tasks(summary)
                    names(summary)
                }
                .frame(maxWidth: .infinity, alignment: .topLeading)
            }
        #else
            VStack(alignment: .leading, spacing: 20) {
                stats(summary, columns: kpiColumns)
                rhythm(summary)
                writtenDays(summary)
                weekdays(summary)
                tasks(summary)
                names(summary)
            }
        #endif
    }

    @ViewBuilder
    private func rhythm(_ summary: PeriodSummary) -> some View {
        if summary.period == .month,
            let yearCalendar,
            yearCalendar.year == summary.range.lowerBound.year
        {
            MonthWritingRhythmView(
                rhythm: MonthWritingRhythm(
                    month: summary.range.lowerBound,
                    calendar: yearCalendar,
                    today: today()
                )
            )
        } else {
            let items = SummaryPresentation.rhythm(summary, locale: locale)
            InkCard {
                VStack(alignment: .leading, spacing: 12) {
                    SectionHeader(title: PresentationLocalization.string(localized: "Ritim", locale: locale))
                    RhythmStrip(
                        items: items,
                        legend: SummaryPresentation.legend(summary.period, locale: locale)
                    )
                    .accessibilityElement(children: .contain)
                    .accessibilityLabel(Text("Ritim"))

                    if summary.period == .week {
                        VStack(alignment: .leading, spacing: 6) {
                            ForEach(items) { item in
                                HStack(spacing: 8) {
                                    Text(verbatim: item.label)
                                        .font(.ink.meta)
                                        .foregroundStyle(Color.ink.secondaryText)
                                        .frame(width: 40, alignment: .leading)
                                    Text("\(item.value) olay")
                                        .font(.ink.value)
                                        .foregroundStyle(
                                            item.mark == .notStarted
                                                ? Color.ink.secondaryText : Color.ink.text)
                                    Spacer(minLength: 8)
                                    if let previous = item.previous {
                                        Text("önceki dönemde \(previous)")
                                            .font(.ink.meta)
                                            .monospacedDigit()
                                            .foregroundStyle(Color.ink.secondaryText)
                                    }
                                }
                                .padding(.vertical, 2)
                            }
                        }
                    }
                }
            }
        }
    }

    /// The year's day-by-day map under its monthly rhythm; a week or a month has none.
    @ViewBuilder
    private func writtenDays(_ summary: PeriodSummary) -> some View {
        if summary.period == .year {
            if let yearError {
                InfoBand(kind: .error, verbatim: yearError)
            } else if let yearCalendar, yearCalendar.year == summary.range.lowerBound.year {
                InkCard {
                    YearWritingHeatmap(calendar: yearCalendar, today: today())
                }
            }
        }
    }

    /// A month or year page is ready once its year calendar has been read too, or has failed.
    private var isYearReady: Bool {
        model.period == .week || yearRequest == model.requestKey
    }

    /// Reads the year map after the summary, for the same request; a newer request drops the answer.
    private func loadYear() async {
        guard model.period != .week else { return }
        let request = model.requestKey
        let year = model.range.lowerBound.year
        do {
            let result = try await store.computeYearWritingCalendar(year: year, today: today())
            guard request == model.requestKey, !Task.isCancelled else { return }
            yearCalendar = result
            yearError = nil
            yearRequest = request
        } catch is CancellationError {
        } catch {
            guard request == model.requestKey else { return }
            yearError = DayEditError.message(for: error)
            yearRequest = request
        }
    }

    /// Written-day ratios by weekday for a month or a year; a week has none. The answer of an
    /// earlier period is not drawn under a newer summary.
    @ViewBuilder
    private func weekdays(_ summary: PeriodSummary) -> some View {
        if summary.period != .week,
            let weekdayDistribution, weekdaysRange == summary.range,
            weekdayDistribution.entries.contains(where: { $0.totalDays > 0 })
        {
            InkCard {
                WeekdayDistributionView(distribution: weekdayDistribution)
            }
        }
    }

    private var isWeekdaysReady: Bool {
        model.period == .week || weekdaysRequest == model.requestKey
    }

    /// Reads the weekday rows after the summary, for the same request; a newer request drops the answer.
    private func loadWeekdays() async {
        guard model.period != .week else { return }
        let request = model.requestKey
        let period = model.period
        let day = model.day
        let today = today()
        let range = period.bounds(containing: day)
        do {
            let input = try await store.weeklyReviewInput(from: range.lowerBound, to: range.upperBound)
            guard request == model.requestKey, !Task.isCancelled else { return }
            weekdayDistribution = WeekdayDistribution.compute(
                days: input.days, period: period, containing: day, today: today)
            weekdaysRange = range
            weekdaysRequest = request
        } catch is CancellationError {
        } catch {
            guard request == model.requestKey else { return }
            weekdaysRequest = request
        }
    }

    /// Three equal-height number cards side by side (one column at accessibility sizes) and the
    /// three changes in one line under them (Şafak çizimi).
    private func stats(_ summary: PeriodSummary, columns: Int) -> some View {
        let layout =
            columns == 1
            ? AnyLayout(VStackLayout(alignment: .leading, spacing: 8))
            : AnyLayout(HStackLayout(alignment: .top, spacing: 8))
        return VStack(alignment: .leading, spacing: 8) {
            layout {
                SummaryMetric(
                    title: "Yazılan gün",
                    valueText: SummaryPresentation.writtenDaysValueText(summary, locale: locale))
                SummaryMetric(title: "Olay", value: summary.counts.events)
                SummaryMetric(title: "Biten görev", value: summary.counts.completedTasks)
            }
            .fixedSize(horizontal: false, vertical: true)
            Text(changeLine(summary))
                .font(.caption)
                .monospacedDigit()
                .foregroundStyle(Color.ink.secondaryText)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    /// The change line with its changes in ink.
    private func changeLine(_ summary: PeriodSummary) -> AttributedString {
        var line = SummaryPresentation.changeLine(summary, locale: locale)
        for run in line.runs where run.inlinePresentationIntent == .stronglyEmphasized {
            line[run.range].foregroundColor = Color.ink.text
        }
        return line
    }

    @ViewBuilder
    private func names(_ summary: PeriodSummary) -> some View {
        if summary.counts.peopleMentions > 0 {
            SummaryEntitySection(
                store: store, title: PresentationLocalization.string(localized: "En çok görüşülen", locale: locale),
                entities: summary.people,
                mentions: summary.counts.peopleMentions, firsts: summary.firstPeople, kind: .person)
        }
        if summary.counts.placeMentions > 0 {
            SummaryEntitySection(
                store: store, title: PresentationLocalization.string(localized: "En çok gidilen", locale: locale),
                entities: summary.places,
                mentions: summary.counts.placeMentions, firsts: summary.firstPlaces, kind: .place)
        }
    }

    @ViewBuilder
    private func tasks(_ summary: PeriodSummary) -> some View {
        let counts = summary.counts
        if counts.createdTasks + counts.completedTasks + counts.overdueTasks + counts.undatedTasks > 0 {
            SummaryTaskSection(
                counts: counts, change: change(summary.change.createdTasks, summary),
                taskFlow: taskFlowRequest == model.requestKey ? taskFlow : nil)
            if taskFlowRequest == model.requestKey, let taskFlowError {
                InfoBand(kind: .error, verbatim: taskFlowError)
            }
        }
    }

    private func loadTaskFlow() async {
        let key = model.requestKey
        guard model.errorText == nil, model.summary != nil else {
            taskFlow = nil
            taskFlowError = nil
            taskFlowRequest = key
            return
        }
        let period = model.period
        let day = model.day
        let measuredToday = today()
        do {
            let tasks = try await store.summaryTasks()
            try Task.checkCancellation()
            guard key == model.requestKey else { return }
            taskFlow = TaskFlowSeries.compute(
                tasks: tasks, period: period, containing: day, today: measuredToday)
            taskFlowError = nil
            taskFlowRequest = key
        } catch is CancellationError {
        } catch {
            guard key == model.requestKey else { return }
            taskFlow = nil
            taskFlowError = DayEditError.message(for: error)
            taskFlowRequest = key
        }
    }

    private func change(_ value: Int, _ summary: PeriodSummary) -> String {
        SummaryPresentation.change(value, period: summary.period, isRunning: summary.isRunning, locale: locale)
    }
}
