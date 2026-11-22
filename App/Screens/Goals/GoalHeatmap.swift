import GoalTracking
import SwiftUI
import VaultFormat

/// Pure heatmap layout math (unit-tested; kept off MainActor).
enum GoalHeatmapMetrics {
    static let spacing: CGFloat = 3
    /// Base weekday gutter at default Dynamic Type; views scale with `@ScaledMetric`.
    static let weekdayColumnWidth: CGFloat = 18
    static let minimumCellSize: CGFloat = 14

    static func weekCount(isAccessibilitySize: Bool) -> Int {
        isAccessibilitySize ? 6 : 12
    }

    /// Square side that fits `weekCount` week columns plus the weekday gutter and gaps.
    static func cellSize(
        availableWidth: CGFloat, weekCount: Int,
        weekdayColumnWidth: CGFloat = Self.weekdayColumnWidth
    ) -> CGFloat {
        guard weekCount > 0, availableWidth > 0 else { return minimumCellSize }
        // Gaps: weekday|week × weekCount (one after the gutter, then between weeks).
        let gaps = CGFloat(weekCount) * spacing
        let usable = availableWidth - weekdayColumnWidth - gaps
        let raw = floor(usable / CGFloat(weekCount))
        return max(minimumCellSize, raw)
    }

    /// Row/column pitch: visual square plus the inter-cell gap.
    static func step(cellSize: CGFloat) -> CGFloat {
        cellSize + spacing
    }

    /// Hit target matches the grid step (no overlap with neighbors).
    static func tapSize(cellSize: CGFloat) -> CGFloat {
        step(cellSize: cellSize)
    }

    /// Total width of gutter + week columns + inter-column gaps.
    static func contentWidth(
        weekCount: Int, cellSize: CGFloat,
        weekdayColumnWidth: CGFloat = Self.weekdayColumnWidth
    ) -> CGFloat {
        weekdayColumnWidth + CGFloat(weekCount) * step(cellSize: cellSize)
    }

    static func contentFits(
        availableWidth: CGFloat, weekCount: Int,
        weekdayColumnWidth: CGFloat = Self.weekdayColumnWidth
    ) -> Bool {
        let size = cellSize(
            availableWidth: availableWidth, weekCount: weekCount,
            weekdayColumnWidth: weekdayColumnWidth)
        return contentWidth(
            weekCount: weekCount, cellSize: size, weekdayColumnWidth: weekdayColumnWidth)
            <= availableWidth
    }

    /// Room a month label leaves before the next label, so two never read as one ("Ağu Eyl").
    static let monthLabelGap: CGFloat = 10
    /// Room the last label leaves at the grid's edge.
    static let lastMonthLabelGap: CGFloat = 4

    /// The gap after a month label: ``monthLabelGap`` before another label, less at the edge.
    static func monthLabelGap(isLast: Bool) -> CGFloat {
        isLast ? lastMonthLabelGap : monthLabelGap
    }

    /// The width a month label may take over `weeks` week columns; a wider label is left out. A
    /// month with one week in view (27 pt cells) has no room for "Ağu" and its neighbour's gap.
    static func monthLabelWidth(weeks: Int, step: CGFloat, isLast: Bool) -> CGFloat {
        max(0, CGFloat(weeks) * step - monthLabelGap(isLast: isLast))
    }

    /// One letter per weekday in the locale's language, Monday first (`CalendarDate` weeks start
    /// on Monday; the calendar's symbols start on Sunday).
    static func weekdaySymbols(locale: Locale) -> [String] {
        var calendar = Calendar(identifier: .gregorian)
        calendar.locale = locale
        let symbols = calendar.veryShortStandaloneWeekdaySymbols
        return Array(symbols[1...]) + [symbols[0]]
    }

    /// Visual square side (same as the fitted cell).
    static func displaySize(cellSize: CGFloat) -> CGFloat {
        cellSize
    }

    /// Spacing between tap-sized row frames. Always ≥ 0; pitch gap lives inside `tapSize`.
    static func rowSpacing(cellSize _: CGFloat) -> CGFloat {
        0
    }
}

private struct HeatmapWidthKey: PreferenceKey {
    static let defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = nextValue()
    }
}

struct GoalHeatmap: View {
    let goal: GoalDefinition
    let logs: [GoalLog]
    let today: CalendarDate
    /// Days a spent chain day covered (``GoalStatus/graceSpentDays``): drawn with the chain-day mark.
    var graceSpentDays: Set<CalendarDate> = []
    let select: (CalendarDate) -> Void

    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @Environment(\.locale) private var locale
    @ScaledMetric(relativeTo: .footnote) private var weekdayColumnWidth =
        GoalHeatmapMetrics.weekdayColumnWidth
    @State private var availableWidth: CGFloat = 358

    private var weekCount: Int {
        GoalHeatmapMetrics.weekCount(isAccessibilitySize: dynamicTypeSize.isAccessibilitySize)
    }

    private var cellSize: CGFloat {
        GoalHeatmapMetrics.cellSize(
            availableWidth: availableWidth, weekCount: weekCount,
            weekdayColumnWidth: weekdayColumnWidth)
    }

    private var contentFits: Bool {
        GoalHeatmapMetrics.contentFits(
            availableWidth: availableWidth, weekCount: weekCount,
            weekdayColumnWidth: weekdayColumnWidth)
    }

    var body: some View {
        let weeks = heatmapWeeks
        let marks = GoalProgress.heatmap(
            definition: goal, logs: logs, from: weeks.first?.first ?? today, to: today, today: today)
        // The legend stays under the grid, outside its scroll: scrolled with the weeks, a long title
        // ("Partial contribution") was out of view.
        VStack(alignment: .leading, spacing: GoalHeatmapMetrics.spacing) {
            ScrollView(.horizontal, showsIndicators: false) {
                VStack(alignment: .leading, spacing: GoalHeatmapMetrics.spacing) {
                    monthLabels(weeks: weeks, cellSize: cellSize)
                    // Week columns abut: each cell's tap frame is `step` wide (gap inside the frame).
                    HStack(alignment: .top, spacing: 0) {
                        weekdayColumn(cellSize: cellSize)
                        ForEach(Array(weeks.enumerated()), id: \.offset) { _, week in
                            VStack(spacing: GoalHeatmapMetrics.rowSpacing(cellSize: cellSize)) {
                                ForEach(week, id: \.self) { day in
                                    cell(day: day, marks: marks, cellSize: cellSize)
                                }
                            }
                        }
                    }
                }
                .frame(minWidth: max(availableWidth, 1), alignment: .leading)
            }
            // Overflow: open on the current week. Fits: no scroll range, anchor unused.
            .defaultScrollAnchor(contentFits ? .leading : .trailing)
            .background(
                GeometryReader { geo in
                    Color.clear.preference(key: HeatmapWidthKey.self, value: geo.size.width)
                }
            )
            .onPreferenceChange(HeatmapWidthKey.self) { width in
                if width > 0 { availableWidth = width }
            }
            GoalHeatmapLegend(
                period: goal.period,
                showsGrace: GraceDayPresentation.showsLegend(days: weeks.flatMap { $0 }, spent: graceSpentDays))
        }
        .accessibilityElement(children: .contain)
    }

    private var heatmapWeeks: [[CalendarDate]] {
        guard let todayStart = today.startOfWeek,
            let rangeStart = todayStart.addingDays(-(weekCount - 1) * 7)
        else { return [] }
        return (0..<weekCount).compactMap { week in
            guard let weekStart = rangeStart.addingDays(week * 7) else { return nil }
            return (0..<7).compactMap { weekStart.addingDays($0) }
        }
    }

    private func weekdayColumn(cellSize: CGFloat) -> some View {
        let symbols = GoalHeatmapMetrics.weekdaySymbols(locale: locale)
        let visual = GoalHeatmapMetrics.displaySize(cellSize: cellSize)
        let tap = GoalHeatmapMetrics.tapSize(cellSize: cellSize)
        return VStack(spacing: GoalHeatmapMetrics.rowSpacing(cellSize: cellSize)) {
            ForEach(0..<7, id: \.self) { index in
                Text(verbatim: symbols[index])
                    .font(.ink.meta)
                    .foregroundStyle(Color.ink.secondaryText)
                    .frame(width: weekdayColumnWidth, height: visual, alignment: .trailing)
                    .frame(width: weekdayColumnWidth, height: tap, alignment: .center)
                    .accessibilityHidden(true)
            }
        }
    }

    private func monthLabels(weeks: [[CalendarDate]], cellSize: CGFloat) -> some View {
        let tap = GoalHeatmapMetrics.tapSize(cellSize: cellSize)
        return HStack(alignment: .bottom, spacing: 0) {
            Color.clear.frame(width: weekdayColumnWidth, height: 14)
            ForEach(Array(weeks.enumerated()), id: \.offset) { index, week in
                let label = monthLabel(for: week, previous: index > 0 ? weeks[index - 1] : nil)
                if !label.isEmpty {
                    let next =
                        weeks.indices.dropFirst(index + 1).first { candidate in
                            !monthLabel(for: weeks[candidate], previous: weeks[candidate - 1]).isEmpty
                        } ?? weeks.count
                    ViewThatFits(in: .horizontal) {
                        Text(verbatim: label)
                            .font(.ink.meta)
                            .foregroundStyle(Color.ink.secondaryText)
                            .fixedSize()
                        Color.clear.frame(height: 14)
                    }
                    .frame(
                        width: GoalHeatmapMetrics.monthLabelWidth(
                            weeks: next - index, step: tap, isLast: next == weeks.count),
                        alignment: .leading
                    )
                    .padding(.trailing, GoalHeatmapMetrics.monthLabelGap(isLast: next == weeks.count))
                    // VoiceOver reads every month, also one whose label did not fit.
                    .accessibilityElement(children: .ignore)
                    .accessibilityLabel(Text(verbatim: monthName(for: week)))
                }
            }
        }
    }

    private func monthName(for week: [CalendarDate]) -> String {
        week.first.map { LocalDay.instant(for: $0).formatted(.dateTime.month(.wide).year().locale(locale)) } ?? ""
    }

    private func monthLabel(for week: [CalendarDate], previous: [CalendarDate]?) -> String {
        guard let first = week.first else { return "" }
        if let previous, let prior = previous.first, prior.month == first.month, prior.year == first.year {
            return ""
        }
        return LocalDay.instant(for: first).formatted(.dateTime.month(.abbreviated).locale(locale))
    }

    private func cell(day: CalendarDate, marks: [CalendarDate: GoalDayMark], cellSize: CGFloat)
        -> some View
    {
        let isFuture = day > today
        let mark = marks[day] ?? .none
        let isSpent = !isFuture && graceSpentDays.contains(day)
        let kind: HeatmapCellKind = isFuture ? .future : GraceDayPresentation.kind(mark: mark, isSpent: isSpent)
        let visual = GoalHeatmapMetrics.displaySize(cellSize: cellSize)
        let tap = GoalHeatmapMetrics.tapSize(cellSize: cellSize)
        return Button {
            if !isFuture { select(day) }
        } label: {
            HeatmapCell(
                kind: kind,
                size: visual,
                isToday: day == today,
                accessibilityValue: Text(GraceDayPresentation.title(mark: mark, isSpent: isSpent)),
                accessibilityLabel: isFuture
                    ? nil
                    : Text(LocalDay.instant(for: day), format: .dateTime.day().month().year())
            )
            .frame(width: visual, height: visual)
            .frame(width: tap, height: tap, alignment: .center)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(isFuture)
        .help(
            isFuture
                ? Text(verbatim: "")
                : Text(LocalDay.instant(for: day), format: .dateTime.day().month().year()))
    }

}

/// The kinds a goal's heatmap can draw, under the weeks and outside their scroll. The chain-day
/// item comes only while a covered day is in view, on a line of its own.
struct GoalHeatmapLegend: View {
    let period: GoalPeriod
    var showsGrace: Bool

    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @ScaledMetric(relativeTo: .footnote) private var legendMarkSize = 10

    var body: some View {
        let marks: [GoalDayMark] =
            period == .day ? [.none, .partial, .full, .forgiven] : [.none, .partial, .full]
        // Accessibility sizes: one kind per line. Otherwise a row that wraps when the card is
        // narrower than its four kinds (xxxL on a 320 pt screen); outside the scroll it cannot run on.
        let stacks = dynamicTypeSize.isAccessibilitySize
        let row =
            stacks
            ? AnyLayout(VStackLayout(alignment: .leading, spacing: 8))
            : AnyLayout(InkFlowLayout(spacing: 12, lineSpacing: 8))
        VStack(alignment: .leading, spacing: 8) {
            row {
                ForEach(marks, id: \.rawValue) { mark in
                    legendItem(mark.heatmapKind, title: mark.title)
                }
            }
            if showsGrace { legendItem(.graceSpent, title: "Zincir günü") }
        }
        .accessibilityElement(children: .combine)
    }

    private func legendItem(_ kind: HeatmapCellKind, title: LocalizedStringKey) -> some View {
        HStack(spacing: 4) {
            HeatmapCell(
                kind: kind, size: legendMarkSize, accessibilityValue: Text(title),
                accessibilityLabel: Text(title))
            Text(title)
                .font(.ink.meta)
                .foregroundStyle(Color.ink.secondaryText)
                // One line beside the mark; at accessibility sizes a long title wraps inside the card.
                .fixedSize(
                    horizontal: !dynamicTypeSize.isAccessibilitySize,
                    vertical: dynamicTypeSize.isAccessibilitySize)
        }
    }
}

extension GoalDayMark {
    var heatmapKind: HeatmapCellKind {
        switch self {
        case .none: .empty
        case .partial: .partial
        case .full: .full
        case .forgiven: .forgiven
        case .forgivenPartial: .forgivenPartial
        }
    }
}
