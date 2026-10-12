import GoalTracking
import Summaries
import SwiftUI
import VaultFormat

/// The Goals screen's row for each goal, measured over the period. A daily goal of a week or a month
/// also shows its days as one row of heatmap cells.
struct SummaryGoalSection: View {
    let summary: PeriodSummary
    @Environment(\.locale) private var locale
    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            SectionHeader(title: String(localized: "Hedefler"), count: summary.goals.count)
            ForEach(summary.goals, id: \.definition.id) { goal in
                VStack(alignment: .leading, spacing: 6) {
                    InkGoalRow(
                        name: goal.definition.name, progress: SummaryPresentation.goalFraction(goal),
                        isBoolean: goal.definition.kind == .milestone
                            || (goal.definition.kind == .boolean && goal.definition.target <= 1),
                        meta: SummaryPresentation.goalMeta(goal, isRunning: summary.isRunning, locale: locale),
                        barFraction: goal.definition.kind == .milestone
                            ? nil : SummaryPresentation.goalFraction(goal),
                        valueText: SummaryPresentation.goalValue(goal, locale: locale))
                    if let change = SummaryPresentation.goalChange(
                        goal, period: summary.period, isRunning: summary.isRunning, locale: locale)
                    {
                        Text(verbatim: change)
                            .font(.ink.meta)
                            .monospacedDigit()
                            .foregroundStyle(Color.ink.secondaryText)
                            .padding(.leading, InkSpacing.gutter + 10)
                    }
                    if summary.period != .year, !goal.dayMarks.isEmpty {
                        GoalDayStrip(days: days(goal))
                            .padding(.leading, InkSpacing.gutter + 10)
                    }
                }
            }
        }
    }

    /// Every day of the period; a day after the measured range has not come yet.
    private func days(_ goal: SummaryGoal) -> [GoalDayStrip.Day] {
        var result: [GoalDayStrip.Day] = []
        var cursor: CalendarDate? = summary.range.lowerBound
        while let day = cursor, day <= summary.range.upperBound {
            let measured = summary.measuredRange.contains(day)
            result.append(.init(date: day, mark: measured ? goal.dayMarks[day] ?? GoalDayMark.none : nil))
            cursor = day.addingDays(1)
        }
        return result
    }
}

/// The days of a week or a month for one daily goal: the Goals heatmap cells in one row.
struct GoalDayStrip: View {
    struct Day: Identifiable, Equatable {
        let date: CalendarDate
        /// Nil for a day that has not come.
        let mark: GoalDayMark?
        var id: CalendarDate { date }
    }
    let days: [Day]
    private var cap: CGFloat { days.count > 10 ? 12 : 18 }
    var body: some View {
        GeometryReader { geo in
            let spacing: CGFloat = days.count > 10 ? 2 : 4
            let count = CGFloat(max(1, days.count))
            let size = min(cap, floor((geo.size.width - spacing * (count - 1)) / count))
            HStack(spacing: spacing) {
                ForEach(days) { day in
                    HeatmapCell(
                        kind: day.mark?.heatmapKind ?? .future, size: size,
                        accessibilityValue: day.mark.map { Text($0.title) } ?? Text(verbatim: ""),
                        accessibilityLabel: day.mark == nil
                            ? nil : Text(LocalDay.instant(for: day.date), format: .dateTime.day().month()))
                }
            }
        }
        .frame(height: cap)
    }
}
