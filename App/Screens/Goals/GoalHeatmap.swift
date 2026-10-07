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
    let select: (CalendarDate) -> Void

    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @ScaledMetric(relativeTo: .footnote) private var legendMarkSize = 10
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
            definition: goal, logs: logs, from: weeks.first?.first ?? today, to: today)
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
                legend
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
        let symbols = weekdaySymbols
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
                Text(verbatim: label)
                    .font(.ink.meta)
                    .foregroundStyle(Color.ink.secondaryText)
                    .fixedSize()
                    .frame(width: tap, alignment: .leading)
                    .accessibilityHidden(label.isEmpty)
            }
        }
    }

    private func monthLabel(for week: [CalendarDate], previous: [CalendarDate]?) -> String {
        guard let first = week.first else { return "" }
        if let previous, let prior = previous.first, prior.month == first.month, prior.year == first.year {
            return ""
        }
        return LocalDay.instant(for: first).formatted(.dateTime.month(.abbreviated))
    }

    private func cell(day: CalendarDate, marks: [CalendarDate: GoalDayMark], cellSize: CGFloat)
        -> some View
    {
        let isFuture = day > today
        let mark = marks[day] ?? .none
        let kind: HeatmapCellKind = isFuture ? .future : mark.heatmapKind
        let visual = GoalHeatmapMetrics.displaySize(cellSize: cellSize)
        let tap = GoalHeatmapMetrics.tapSize(cellSize: cellSize)
        return Button {
            if !isFuture { select(day) }
        } label: {
            HeatmapCell(
                kind: kind,
                size: visual,
                isToday: day == today,
                accessibilityValue: Text(mark.title),
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

    private var legend: some View {
        let marks = [GoalDayMark.none, .partial, .full]
        return Group {
            if dynamicTypeSize.isAccessibilitySize {
                VStack(alignment: .leading, spacing: 8) {
                    ForEach(marks, id: \.rawValue) { mark in
                        legendItem(mark)
                    }
                }
            } else {
                HStack(spacing: 12) {
                    ForEach(marks, id: \.rawValue) { mark in
                        legendItem(mark)
                    }
                }
            }
        }
        .accessibilityElement(children: .combine)
    }

    private func legendItem(_ mark: GoalDayMark) -> some View {
        HStack(spacing: 4) {
            HeatmapCell(
                kind: mark.heatmapKind, size: legendMarkSize, accessibilityValue: Text(mark.title),
                accessibilityLabel: Text(mark.title))
            Text(mark.title)
                .font(.ink.meta)
                .foregroundStyle(Color.ink.secondaryText)
                .fixedSize(horizontal: true, vertical: false)
        }
    }

    private var weekdaySymbols: [String] {
        var calendar = Calendar(identifier: .gregorian)
        calendar.locale = .current
        // CalendarDate weeks start Monday; system symbols are Sunday-first.
        let symbols = calendar.veryShortStandaloneWeekdaySymbols
        return Array(symbols[1...]) + [symbols[0]]
    }
}

extension GoalDayMark {
    var heatmapKind: HeatmapCellKind {
        switch self {
        case .none: .empty
        case .partial: .partial
        case .full: .full
        }
    }
}
