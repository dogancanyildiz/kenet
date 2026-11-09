import Summaries
import SwiftUI

/// A headline number card with its title and the change in words under it.
struct SummaryMetric: View {
    let title: LocalizedStringKey
    let valueText: String
    /// "önceki haftaya göre +4": already localized. No arrow; the sign and the words carry it.
    let change: String

    init(title: LocalizedStringKey, value: Int, change: String) {
        self.title = title
        self.valueText = value.formatted()
        self.change = change
    }

    init(title: LocalizedStringKey, valueText: String, change: String) {
        self.title = title
        self.valueText = valueText
        self.change = change
    }

    var body: some View {
        InkCard {
            VStack(alignment: .leading, spacing: 2) {
                LargeNumberText(verbatim: valueText)
                    .lineLimit(1)
                    .minimumScaleFactor(0.5)
                Text(title)
                    .font(.ink.byline)
                    .foregroundStyle(Color.ink.text)
                Text(verbatim: change)
                    .font(.ink.meta)
                    .monospacedDigit()
                    .foregroundStyle(Color.ink.secondaryText)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .accessibilityElement(children: .combine)
    }
}

/// Month summary 30-day square grid: full (events), partial (journal only), empty (`well`),
/// or future (no square, only dimmed day numeral).
struct MonthWritingRhythmView: View {
    let rhythm: MonthWritingRhythm
    @Environment(\.locale) private var locale
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    private var bundle: Bundle { PresentationLocalization.bundle(locale) }

    var body: some View {
        InkCard {
            VStack(alignment: .leading, spacing: 12) {
                SectionHeader(
                    title: String(localized: "Ritim", bundle: bundle, locale: locale),
                    counter:
                        "\(rhythm.writtenDayCount)/\(rhythm.measuredDayCount)"
                )
                LazyVGrid(
                    columns: Array(repeating: GridItem(.flexible(), spacing: 6), count: 7),
                    spacing: 8
                ) {
                    ForEach(rhythm.days) { day in
                        dayCell(day)
                    }
                }
                legend
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text(verbatim: String(localized: "Ritim", bundle: bundle, locale: locale)))
        .accessibilityValue(
            Text(
                verbatim: String(
                    localized:
                        "\(rhythm.measuredDayCount) günün \(rhythm.writtenDayCount)'sinde yazıldı",
                    bundle: bundle, locale: locale))
        )
    }

    @ViewBuilder
    private func dayCell(_ day: MonthRhythmDay) -> some View {
        switch day.state {
        case .future:
            Text(day.date.day, format: .number)
                .font(.ink.meta)
                .monospacedDigit()
                .foregroundStyle(Color.ink.tertiaryText)
                .frame(maxWidth: .infinity, minHeight: 26)
        case .empty:
            ZStack {
                HeatmapCell(
                    kind: .empty, size: 24, isToday: day.isToday,
                    accessibilityValue: Text(verbatim: ""))
                Text(day.date.day, format: .number)
                    .font(.ink.meta)
                    .monospacedDigit()
                    .foregroundStyle(day.isToday ? Color.ink.accent : Color.ink.secondaryText)
            }
            .frame(maxWidth: .infinity, minHeight: 26)
        case .partial:
            ZStack {
                HeatmapCell(
                    kind: .partial, size: 24, isToday: day.isToday,
                    accessibilityValue: Text(verbatim: ""))
                Text(day.date.day, format: .number)
                    .font(.ink.meta)
                    .monospacedDigit()
                    .foregroundStyle(Color.ink.text)
            }
            .frame(maxWidth: .infinity, minHeight: 26)
        case .full:
            ZStack {
                HeatmapCell(
                    kind: .full, size: 24, isToday: day.isToday,
                    accessibilityValue: Text(verbatim: ""))
                Text(day.date.day, format: .number)
                    .font(.ink.meta)
                    .monospacedDigit()
                    .foregroundStyle(Color.ink.onAccent)
            }
            .frame(maxWidth: .infinity, minHeight: 26)
        }
    }

    private var legend: some View {
        let layout =
            dynamicTypeSize.isAccessibilitySize
            ? AnyLayout(VStackLayout(alignment: .leading, spacing: 6))
            : AnyLayout(InkFlowLayout(spacing: 12, lineSpacing: 6))
        return layout {
            legendItem(.full, "Olaylı gün")
            legendItem(.partial, "Günlük yazısı")
            legendItem(.empty, "Yazılmadı")
        }
    }

    private func legendItem(_ kind: HeatmapCellKind, _ title: LocalizedStringKey) -> some View {
        HStack(spacing: 4) {
            HeatmapCell(kind: kind, size: 10, accessibilityValue: Text(verbatim: ""))
                .accessibilityHidden(true)
            Text(title)
                .font(.ink.meta)
                .foregroundStyle(Color.ink.secondaryText)
        }
    }
}

/// Created tasks, open inventory by unit, then the completed, carried and undated task bar.
struct SummaryTaskSection: View {
    let counts: SummaryCounts
    let change: String
    var taskFlow: TaskFlowSeries? = nil
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    var body: some View {
        InkCard {
            VStack(alignment: .leading, spacing: 12) {
                SectionHeader(title: String(localized: "Görevler"))
                let layout =
                    dynamicTypeSize.isAccessibilitySize
                    ? AnyLayout(VStackLayout(alignment: .leading, spacing: 4))
                    : AnyLayout(HStackLayout(alignment: .firstTextBaseline, spacing: 8))
                layout {
                    Text("\(counts.createdTasks) görev oluşturuldu")
                        .font(.ink.byline)
                        .foregroundStyle(Color.ink.text)
                    if !dynamicTypeSize.isAccessibilitySize { Spacer(minLength: 8) }
                    Text(verbatim: change)
                        .font(.ink.meta)
                        .monospacedDigit()
                        .foregroundStyle(Color.ink.secondaryText)
                }
                .accessibilityElement(children: .combine)
                if let taskFlow {
                    TaskFlowChart(series: taskFlow)
                }
                InkSegmentBar(segments: [
                    .init(id: 0, title: String(localized: "Tamamlanan"), value: counts.completedTasks, style: .done),
                    .init(id: 1, title: String(localized: "Devreden"), value: counts.overdueTasks, style: .carried),
                    .init(id: 2, title: String(localized: "Tarihsiz açık"), value: counts.undatedTasks, style: .outline),
                ])
            }
        }
    }
}
