import GoalTracking
import SwiftUI
import VaultFormat

/// Pure heatmap layout math (unit-tested; kept off MainActor).
enum GoalHeatmapMetrics {
    static let spacing: CGFloat = 3
    static let weekdayColumnMin: CGFloat = 18
    static let minimumCellSize: CGFloat = 14
    /// Tap target height approaches the 44 pt floor while staying dense enough for a week column.
    static let tapHeight: CGFloat = 44

    static func weekCount(isAccessibilitySize: Bool) -> Int {
        isAccessibilitySize ? 6 : 12
    }

    static func cellSize(availableWidth: CGFloat, weekCount: Int) -> CGFloat {
        guard weekCount > 0, availableWidth > 0 else { return minimumCellSize }
        let gaps = CGFloat(weekCount) * spacing
        let usable = availableWidth - weekdayColumnMin - gaps
        return max(minimumCellSize, floor(usable / CGFloat(weekCount)))
    }

    static func columnWidth(cellSize: CGFloat) -> CGFloat {
        cellSize + spacing
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
    @State private var availableWidth: CGFloat = 358

    private var weekCount: Int {
        GoalHeatmapMetrics.weekCount(isAccessibilitySize: dynamicTypeSize.isAccessibilitySize)
    }

    private var cellSize: CGFloat {
        GoalHeatmapMetrics.cellSize(availableWidth: availableWidth, weekCount: weekCount)
    }

    var body: some View {
        let weeks = heatmapWeeks
        let marks = GoalProgress.heatmap(
            definition: goal, logs: logs, from: weeks.first?.first ?? today, to: today)
        ScrollView(.horizontal, showsIndicators: false) {
            VStack(alignment: .leading, spacing: GoalHeatmapMetrics.spacing) {
                monthLabels(weeks: weeks, cellSize: cellSize)
                HStack(alignment: .top, spacing: GoalHeatmapMetrics.spacing) {
                    weekdayColumn(cellSize: cellSize)
                    HStack(alignment: .top, spacing: GoalHeatmapMetrics.spacing) {
                        ForEach(Array(weeks.enumerated()), id: \.offset) { _, week in
                            VStack(spacing: 0) {
                                ForEach(week, id: \.self) { day in
                                    cell(day: day, marks: marks, cellSize: cellSize)
                                }
                            }
                        }
                    }
                }
                legend
            }
            .frame(minWidth: max(availableWidth, 1), alignment: .leading)
        }
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
        let width = max(cellSize, GoalHeatmapMetrics.weekdayColumnMin)
        return VStack(spacing: 0) {
            ForEach(0..<7, id: \.self) { index in
                Text(verbatim: symbols[index])
                    .font(.ink.meta)
                    .foregroundStyle(Color.ink.secondaryText)
                    .frame(
                        width: width, height: GoalHeatmapMetrics.tapHeight,
                        alignment: .trailing
                    )
                    .accessibilityHidden(true)
            }
        }
    }

    private func monthLabels(weeks: [[CalendarDate]], cellSize: CGFloat) -> some View {
        let column = GoalHeatmapMetrics.columnWidth(cellSize: cellSize)
        let weekdayWidth = max(cellSize, GoalHeatmapMetrics.weekdayColumnMin)
        return HStack(alignment: .bottom, spacing: GoalHeatmapMetrics.spacing) {
            Color.clear.frame(width: weekdayWidth, height: 14)
            ForEach(Array(weeks.enumerated()), id: \.offset) { index, week in
                let label = monthLabel(for: week, previous: index > 0 ? weeks[index - 1] : nil)
                Text(verbatim: label)
                    .font(.ink.meta)
                    .foregroundStyle(Color.ink.secondaryText)
                    .fixedSize()
                    .frame(width: column, alignment: .leading)
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
        let column = GoalHeatmapMetrics.columnWidth(cellSize: cellSize)
        return Button {
            if !isFuture { select(day) }
        } label: {
            HeatmapCell(
                kind: kind,
                size: cellSize,
                isToday: day == today,
                accessibilityValue: Text(mark.title),
                accessibilityLabel: isFuture
                    ? nil
                    : Text(LocalDay.instant(for: day), format: .dateTime.day().month().year())
            )
            .frame(width: column, height: GoalHeatmapMetrics.tapHeight)
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
                kind: mark.heatmapKind, size: 10, accessibilityValue: Text(mark.title),
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
