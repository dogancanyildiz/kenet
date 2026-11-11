import SwiftUI
import VaultFormat

/// Seven small day squares under a daily goal card: filled / empty / forgiven; today outlined.
struct GoalTallyStrip: View {
    let days: [GoalTallyDay]
    @ScaledMetric(relativeTo: .caption) private var cell: CGFloat = 14
    @Environment(\.locale) private var locale

    var body: some View {
        HStack(spacing: 4) {
            ForEach(Array(days.enumerated()), id: \.offset) { _, day in
                HeatmapCell(
                    kind: day.heatmapKind,
                    size: cell,
                    isToday: day.isToday,
                    accessibilityValue: Text(accessibilityValue(day)),
                    accessibilityLabel: Text(
                        LocalDay.instant(for: day.day), format: .dateTime.weekday(.abbreviated))
                )
                .accessibilityHidden(true)
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text("Son 7 gün"))
        .accessibilityValue(
            Text(verbatim: GoalListPresentation.tallySummary(days, locale: locale)))
    }

    private func accessibilityValue(_ day: GoalTallyDay) -> LocalizedStringKey {
        switch day.fill {
        case .filled: "Tam katkı"
        case .partial: "Kısmi katkı"
        case .empty: "Katkı yok"
        case .forgiven: "Affedildi"
        }
    }
}

/// Twelve mini bars for a yearly goal card; future months are dashed traces.
struct GoalYearMiniBars: View {
    let bars: [GoalYearMonthBar]
    @ScaledMetric(relativeTo: .caption) private var maxHeight: CGFloat = 28
    @ScaledMetric(relativeTo: .caption) private var barWidth: CGFloat = 6
    @Environment(\.locale) private var locale

    var body: some View {
        HStack(alignment: .bottom, spacing: 3) {
            ForEach(Array(bars.enumerated()), id: \.offset) { _, bar in
                Group {
                    if bar.isFuture {
                        Capsule()
                            .strokeBorder(
                                Color.ink.control,
                                style: StrokeStyle(lineWidth: 1, dash: [2, 2])
                            )
                            .frame(width: barWidth, height: max(4, maxHeight * 0.25))
                    } else {
                        Capsule()
                            .fill(Color.ink.accent)
                            .frame(
                                width: barWidth,
                                height: max(2, maxHeight * CGFloat(bar.fraction)))
                    }
                }
                .frame(height: maxHeight, alignment: .bottom)
                .accessibilityHidden(true)
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text("Aylara göre"))
        .accessibilityValue(
            Text(verbatim: GoalListPresentation.yearBarsSummary(bars, locale: locale)))
    }
}
