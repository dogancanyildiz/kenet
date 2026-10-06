import GoalTracking
import SwiftUI
import VaultFormat

struct GoalHeatmap: View {
    let goal: GoalDefinition
    let logs: [GoalLog]
    let today: CalendarDate
    let select: (CalendarDate) -> Void

    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @ScaledMetric(relativeTo: .caption2) private var cellSize: CGFloat = 14

    private var weekCount: Int { dynamicTypeSize.isAccessibilitySize ? 6 : 12 }
    private var spacing: CGFloat { 3 }

    var body: some View {
        let weeks = heatmapWeeks
        let marks = GoalProgress.heatmap(
            definition: goal, logs: logs, from: weeks.first?.first ?? today, to: today)
        ScrollView(.horizontal, showsIndicators: false) {
            VStack(alignment: .leading, spacing: spacing) {
                monthLabels(weeks: weeks)
                HStack(alignment: .top, spacing: spacing) {
                    weekdayColumn
                    HStack(alignment: .top, spacing: spacing) {
                        ForEach(Array(weeks.enumerated()), id: \.offset) { _, week in
                            VStack(spacing: spacing) {
                                ForEach(week, id: \.self) { day in
                                    cell(day: day, marks: marks)
                                }
                            }
                        }
                    }
                }
                legend
            }
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

    private var weekdayColumn: some View {
        let symbols = weekdaySymbols
        return VStack(spacing: spacing) {
            ForEach(0..<7, id: \.self) { index in
                Text(verbatim: symbols[index])
                    .font(.ink.meta)
                    .foregroundStyle(Color.ink.secondaryText)
                    .frame(width: max(cellSize, 18), height: cellSize, alignment: .trailing)
                    .accessibilityHidden(true)
            }
        }
    }

    private func monthLabels(weeks: [[CalendarDate]]) -> some View {
        HStack(alignment: .bottom, spacing: spacing) {
            Color.clear.frame(width: max(cellSize, 18), height: cellSize)
            ForEach(Array(weeks.enumerated()), id: \.offset) { index, week in
                let label = monthLabel(for: week, previous: index > 0 ? weeks[index - 1] : nil)
                Text(verbatim: label)
                    .font(.ink.meta)
                    .foregroundStyle(Color.ink.secondaryText)
                    .frame(width: cellSize, alignment: .leading)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
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

    private func cell(day: CalendarDate, marks: [CalendarDate: GoalDayMark]) -> some View {
        let isFuture = day > today
        let mark = marks[day] ?? .none
        let kind: HeatmapCellKind
        if isFuture {
            kind = .future
        } else {
            kind = mark.heatmapKind
        }
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
        }
        .buttonStyle(.plain)
        .disabled(isFuture)
        .help(
            isFuture
                ? Text(verbatim: "")
                : Text(LocalDay.instant(for: day), format: .dateTime.day().month().year()))
    }

    private var legend: some View {
        HStack(spacing: 12) {
            ForEach([GoalDayMark.none, .partial, .full], id: \.rawValue) { mark in
                HStack(spacing: 4) {
                    HeatmapCell(
                        kind: mark.heatmapKind, size: 10, accessibilityValue: Text(mark.title),
                        accessibilityLabel: Text(mark.title))
                    Text(mark.title)
                        .font(.ink.meta)
                        .foregroundStyle(Color.ink.secondaryText)
                }
            }
        }
        .accessibilityElement(children: .combine)
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
