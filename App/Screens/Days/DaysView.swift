import SwiftUI
import VaultFormat

/// Reverse chronological summaries lead into the shared day layout.
struct DaysView: View {
    let store: IndexStore
    var previewSelectedDay: CalendarDate? = nil
    @Environment(\.clockNow) private var clockNow
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @Environment(\.displayScale) private var displayScale
    @Environment(\.locale) private var locale
    @Environment(ShellNavigationState.self) private var navigation: ShellNavigationState?
    @State private var selectedDay: CalendarDate?
    @State private var showsSummaries = false
    @State private var showsWeeklyReview = false
    @State private var weeklyReviewNotice: WeeklyReviewNotice?
    /// Nil until the first query returns; a reload keeps the previous rows until then.
    @State private var days: [DayOverview]?

    private var today: CalendarDate {
        LocalDay.today(at: clockNow())
    }

    private var visibleDays: [DayOverview]? {
        guard let days else { return nil }
        return DayOverview.listed(days, fragments: store.content.fragments)
    }

    var body: some View {
        List {
            InkPageTitleRow("Günlük") {
                SearchButton()
            }
            topChipsRow
                .inkListRow()
            if let notice = weeklyReviewNotice {
                InfoBand(kind: notice.kind, verbatim: notice.text, onDismiss: { weeklyReviewNotice = nil })
                    .inkListRow()
            }
            Section {
                DaysCalendarView(
                    store: store, selected: selectedDay ?? previewSelectedDay, style: .card
                ) { selectedDay = $0 }
                .inkListRow()
            }
            // One card per month (Şafak çizimi: ayraçlı satırlar, sağda "›"). The month heads its
            // card only when it is not the current one, so a row never repeats its month.
            let lookup = LinkedTextInk.lookup(entities: store.content.entities)
            ForEach(DayListMonth.grouped(visibleDays ?? [])) { group in
                if group.id != DayListMonth.key(today) {
                    SectionHeader(title: group.title(locale: locale))
                        .inkListRow()
                }
                ForEach(Array(group.days.enumerated()), id: \.element.id) { index, day in
                    let segment = InkCardSegment.position(index, of: group.days.count)
                    Button {
                        selectedDay = day.date
                    } label: {
                        DayRow(
                            day: day, isToday: day.date == today, showsMonth: false,
                            showsChevron: true, entityLookup: lookup
                        )
                        .padding(.horizontal, InkSpacing.cardPadding)
                        .padding(.top, segment.roundsTop ? 12 : 6)
                        .padding(.bottom, segment.roundsBottom ? 12 : 6)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .inkListRow(cardSegment: segment)
                }
            }
            if visibleDays?.isEmpty == true {
                EmptyState("Henüz gün yok")
                    .inkListRow()
            }
        }
        .listStyle(.plain)
        .inkPage()
        .inkGlow()
        .inkPageScrollColumn()
        .navigationDestination(isPresented: $showsSummaries) { SummariesView(store: store) }
        .navigationDestination(item: $selectedDay) { day in
            DayView(
                store: store, date: day,
                onReplaceDay: { selectedDay = $0 },
                onReturnToToday: {
                    selectedDay = nil
                    #if os(macOS)
                        navigation?.goToToday(shell: .split)
                    #else
                        navigation?.todayPath = NavigationPath()
                        navigation?.goToToday(shell: .tabs)
                    #endif
                })
        }
        .weeklyReviewSheet(isPresented: $showsWeeklyReview, store: store) { weeklyReviewNotice = $0 }
        .task(id: DayRangeRequest(from: nil, to: nil, updated: store.lastUpdated)) {
            if let loaded = try? await store.computeDaySummaries() { days = loaded }
        }
        .inkRootPageNavigationTitle("Günlük")
        .accessibilityIdentifier("screen.days")
    }

    /// Özetler and Haftalık inceleme: two content-wide capsules on the leading edge (Şafak
    /// çizimi), stacked at accessibility sizes.
    @ViewBuilder
    private var topChipsRow: some View {
        let layout =
            dynamicTypeSize.isAccessibilitySize
            ? AnyLayout(VStackLayout(alignment: .leading, spacing: 8))
            : AnyLayout(HStackLayout(spacing: 8))
        layout {
            Button {
                showsSummaries = true
            } label: {
                chipLabel(systemImage: "chart.bar") {
                    Text("Özetler")
                }
            }
            .buttonStyle(.borderless)
            .accessibilityIdentifier("button.summaries")

            Button {
                showsWeeklyReview = true
            } label: {
                chipLabel(systemImage: "checklist") {
                    Text("Haftalık inceleme")
                    WeeklyReviewEntryStatus()
                }
            }
            .buttonStyle(.borderless)
            .accessibilityIdentifier("button.weeklyReview")
            if !dynamicTypeSize.isAccessibilitySize {
                Spacer(minLength: 0)
            }
        }
        .padding(.vertical, 2)
    }

    private func chipLabel<Content: View>(
        systemImage: String, @ViewBuilder content: () -> Content
    ) -> some View {
        HStack(spacing: 6) {
            Image(systemName: systemImage)
                .font(.ink.meta)
                .foregroundStyle(.ink.accent)
                .accessibilityHidden(true)
            content()
                .font(.subheadline)
                .foregroundStyle(.ink.text)
                // The capsule is as wide as its words: never truncated (audit "Text clipped").
                .fixedSize(horizontal: !dynamicTypeSize.isAccessibilitySize, vertical: false)
        }
        .padding(.horizontal, 16)
        .frame(minHeight: 44)
        .background(
            Capsule(style: .continuous)
                .fill(Color.ink.surface)
        )
        .overlay(
            Capsule(style: .continuous)
                .strokeBorder(Color.ink.rule, lineWidth: InkStroke.hairline(scale: displayScale))
        )
        .contentShape(Capsule(style: .continuous))
    }
}

/// The days of one month in the iPhone day list: one card.
struct DayListMonth: Identifiable {
    /// `year * 12 + month`, so groups compare and sort as months.
    let id: Int
    let days: [DayOverview]

    static func key(_ date: CalendarDate) -> Int { date.year * 12 + date.month }

    /// Consecutive days of the same month, in the list's order (newest first).
    static func grouped(_ days: [DayOverview]) -> [DayListMonth] {
        var result: [DayListMonth] = []
        var current: [DayOverview] = []
        for day in days {
            if let last = current.last, key(last.date) != key(day.date) {
                result.append(DayListMonth(id: key(last.date), days: current))
                current = []
            }
            current.append(day)
        }
        if let last = current.last {
            result.append(DayListMonth(id: key(last.date), days: current))
        }
        return result
    }

    func title(locale: Locale) -> String {
        guard let first = days.first else { return "" }
        return LocalDay.instant(for: first.date).formatted(
            .dateTime.month(.wide).year().locale(locale))
    }
}

struct DayRow: View {
    let day: DayOverview
    var isToday: Bool = false
    var showsCard: Bool = false
    /// The Mac column runs back across months without headers, so each row names its month; the
    /// iPhone list heads each month's card instead.
    var showsMonth: Bool = true
    var showsChevron: Bool = false
    /// When set, people and places in the first event's line are drawn underlined (not tappable:
    /// the whole row opens the day).
    var entityLookup: [String: EntitySummary]? = nil
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @Environment(\.locale) private var locale
    @Environment(\.clockNow) private var clockNow
    @Environment(\.accessibilityDifferentiateWithoutColor) private var differentiateWithoutColor
    @Environment(\.colorSchemeContrast) private var contrast

    var body: some View {
        Group {
            if showsCard {
                InkCard {
                    rowContent
                }
            } else {
                rowContent
                    .padding(.vertical, showsChevron ? 0 : 6)
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text(verbatim: VoiceOverCopy.dayRowLabel(day)))
    }

    @ViewBuilder
    private var rowContent: some View {
        if showsMonth && !showsChevron {
            columnRowContent
        } else {
            listRowContent
        }
    }

    /// The Günlük column of the iPad and the Mac (drawings c-mac, j-mac2): the full date in bold
    /// with the counts on the trailing side, the day's opening line under it.
    private var columnRowContent: some View {
        VStack(alignment: .leading, spacing: 3) {
            let layout =
                dynamicTypeSize.isAccessibilitySize
                ? AnyLayout(VStackLayout(alignment: .leading, spacing: 2))
                : AnyLayout(HStackLayout(alignment: .firstTextBaseline, spacing: 8))
            layout {
                Text(verbatim: Self.columnTitle(day.date, today: today, locale: locale))
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(isToday ? .ink.accent : .ink.text)
                    .fixedSize(horizontal: false, vertical: true)
                if !dynamicTypeSize.isAccessibilitySize {
                    Spacer(minLength: 0)
                }
                // Today is named in words too, not by the accent alone.
                dayCountsMeta(todayAccent: true, showsMonth: false)
                    .lineLimit(1)
                    .fixedSize()
            }
            if let preview = day.displayPreview {
                previewText(preview)
                    .foregroundStyle(.ink.secondaryText)
                    .lineLimit(1)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.vertical, 4)
    }

    private var today: CalendarDate { LocalDay.today(at: clockNow()) }

    /// "20 Eylül Pazar"; another year's day adds its year (unit-tested).
    nonisolated static func columnTitle(_ date: CalendarDate, today: CalendarDate, locale: Locale) -> String {
        let resolved = PresentationLocalization.resolvedLocale(locale)
        var style = Date.FormatStyle(locale: resolved).day().month(.wide).weekday(.wide)
        if date.year != today.year { style = style.year() }
        return LocalDay.instant(for: date).formatted(style)
    }

    @ViewBuilder
    private var listRowContent: some View {
        let layout =
            dynamicTypeSize.isAccessibilitySize
            ? AnyLayout(VStackLayout(alignment: .leading, spacing: 6))
            : AnyLayout(HStackLayout(alignment: .center, spacing: 12))
        layout {
            VStack(spacing: 1) {
                Text(day.date.day, format: .number)
                    .font(showsChevron ? .title2.bold() : .ink.dayName)
                    .monospacedDigit()
                    .foregroundStyle(isToday ? .ink.accent : .ink.text)
                Text(LocalDay.instant(for: day.date), format: .dateTime.weekday(.abbreviated))
                    .font(showsChevron ? .caption : .ink.meta)
                    .foregroundStyle(.ink.secondaryText)
            }
            .frame(minWidth: dynamicTypeSize.isAccessibilitySize ? nil : 44)

            HStack(spacing: 8) {
                VStack(alignment: .leading, spacing: 2) {
                    metaLine
                    if let preview = day.displayPreview {
                        previewText(preview)
                            .foregroundStyle(.ink.text)
                            .lineLimit(1)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                if showsChevron {
                    Image(systemName: "chevron.right")
                        .font(.footnote.weight(.semibold))
                        .foregroundStyle(.ink.tertiaryText)
                        .accessibilityHidden(true)
                }
            }
        }
    }

    private var metaLine: some View {
        dayCountsMeta(todayAccent: showsMonth, showsMonth: showsMonth)
    }

    /// Shared "Bugün · N olay · M görev" (and optional month) for list and column rows.
    @ViewBuilder
    private func dayCountsMeta(todayAccent: Bool, showsMonth: Bool) -> some View {
        HStack(spacing: 4) {
            if isToday {
                Text("Bugün")
                    .foregroundStyle(todayAccent ? .ink.accent : .ink.secondaryText)
                Text(verbatim: "·")
            }
            if showsMonth {
                // The list runs back across months: each row names its own month.
                Text(LocalDay.instant(for: day.date), format: .dateTime.month(.wide).year())
                Text(verbatim: "·")
            }
            Text("\(day.eventCount) olay · \(day.taskCount) görev")
        }
        .font(.ink.meta)
        .monospacedDigit()
        .foregroundStyle(.ink.secondaryText)
    }

    private func previewText(_ preview: String) -> Text {
        let font: Font = showsChevron ? .system(.subheadline, design: Font.ink.contentDesign) : .ink.contentSmall
        guard let entityLookup, let spans = day.displayPreviewSpans else {
            return Text(verbatim: VaultDisplayText.line(preview)).font(font)
        }
        var segments = LinkedTextInk.segments(
            LinkedText(spans: spans.map(\.linkedSpan)), byPath: entityLookup)
        // The last plain run drops a trailing block id the way `VaultDisplayText.line` does.
        if let last = segments.last, last.kind == .plain {
            segments[segments.count - 1] = InkLinkSegment(
                id: last.id, text: VaultDisplayText.line(last.text), kind: .plain)
        }
        var attributed = InkLinkTextBuilder.attributed(
            segments: segments, highContrast: contrast == .increased || differentiateWithoutColor)
        // The whole row opens the day; a link inside it would take the tap.
        for run in attributed.runs where run.link != nil {
            attributed[run.range].link = nil
        }
        return Text(attributed).font(font)
    }
}
