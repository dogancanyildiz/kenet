import Summaries
import SwiftUI

/// A headline number card with its title and the change in words under it.
struct SummaryMetric: View {
    let title: LocalizedStringKey
    let valueText: String
    /// "önceki haftaya göre +4": already localized. No arrow; the sign and the words carry it. Nil
    /// when the page says the changes in one line under the cards (Özetler).
    let change: String?

    init(title: LocalizedStringKey, value: Int, change: String? = nil) {
        self.title = title
        self.valueText = value.formatted()
        self.change = change
    }

    init(title: LocalizedStringKey, valueText: String, change: String? = nil) {
        self.title = title
        self.valueText = valueText
        self.change = change
    }

    /// Compact number card (Şafak çizimi): the number title2 bold, a "/30" tail smaller and
    /// secondary, the title and the change in caption under it.
    var body: some View {
        InkCard {
            VStack(alignment: .leading, spacing: 4) {
                valueLine
                    .lineLimit(1)
                    .minimumScaleFactor(0.5)
                Text(title)
                    .font(.caption)
                    .foregroundStyle(Color.ink.secondaryText)
                if let change {
                    Text(verbatim: change)
                        .font(.caption2)
                        .monospacedDigit()
                        .foregroundStyle(Color.ink.secondaryText)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        }
        .accessibilityElement(children: .combine)
    }

    private var valueLine: some View {
        let parts = valueText.split(separator: "/", maxSplits: 1)
        return HStack(alignment: .firstTextBaseline, spacing: 0) {
            Text(verbatim: String(parts.first ?? ""))
                .font(.title2.bold())
                .foregroundStyle(Color.ink.text)
            if parts.count == 2 {
                Text(verbatim: "/" + parts[1])
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(Color.ink.secondaryText)
            }
        }
        .monospacedDigit()
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
                // A running month says how far it counts ("20 Eyl'e kadar"); a past one its tally.
                SectionHeader(
                    title: String(localized: "Ritim", bundle: bundle, locale: locale),
                    counter: rhythm.throughDay.map { SummaryPresentation.rhythmThrough($0, locale: locale) }
                        ?? "\(rhythm.writtenDayCount)/\(rhythm.measuredDayCount)"
                )
                // Ten days a row (Şafak çizimi): three rows hold a month.
                LazyVGrid(
                    columns: Array(repeating: GridItem(.flexible(), spacing: 5), count: 10),
                    spacing: 6
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

    /// A rounded day square: filled (events), accent-framed with a low fill (journal only),
    /// framed (not written) or bare (future). Today carries an ink ring outside the square.
    @ViewBuilder
    private func dayCell(_ day: MonthRhythmDay) -> some View {
        let shape = RoundedRectangle(cornerRadius: 7, style: .continuous)
        let numeral = Text(day.date.day, format: .number)
            .font(.caption.weight(day.state == .future ? .regular : .semibold))
            .monospacedDigit()
            .lineLimit(1)
            .minimumScaleFactor(0.6)
        ZStack {
            switch day.state {
            case .future:
                numeral.foregroundStyle(Color.ink.tertiaryText)
            case .empty:
                shape.strokeBorder(Color.ink.control, lineWidth: 1.5)
                numeral.foregroundStyle(Color.ink.secondaryText)
            case .partial:
                shape.fill(Color.ink.accentSoft)
                    .overlay(alignment: .bottom) {
                        GeometryReader { geo in
                            Rectangle()
                                .fill(Color.ink.accent.opacity(0.55))
                                .frame(height: geo.size.height * 0.4)
                                .frame(maxHeight: .infinity, alignment: .bottom)
                        }
                    }
                    .clipShape(shape)
                    .overlay { shape.strokeBorder(Color.ink.accent, lineWidth: 1.5) }
                numeral.foregroundStyle(Color.ink.text)
            case .full:
                shape.fill(Color.ink.accent)
                numeral.foregroundStyle(Color.ink.onAccent)
            }
        }
        .frame(maxWidth: .infinity)
        .frame(height: 28)
        .overlay {
            if day.isToday {
                RoundedRectangle(cornerRadius: 9, style: .continuous)
                    .stroke(Color.ink.text, lineWidth: 2)
                    .padding(-3)
            }
        }
    }

    private var legend: some View {
        let layout =
            dynamicTypeSize.isAccessibilitySize
            ? AnyLayout(VStackLayout(alignment: .leading, spacing: 6))
            : AnyLayout(InkFlowLayout(spacing: 12, lineSpacing: 6))
        return layout {
            legendItem(.full, "Olay var")
            legendItem(.partial, "Yalnız yazı")
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
    @Environment(\.locale) private var locale
    var body: some View {
        InkCard {
            VStack(alignment: .leading, spacing: 12) {
                // Title on the left; the created count and its change on the right, in one
                // caption line (Şafak çizimi), under the title at accessibility sizes.
                let layout =
                    dynamicTypeSize.isAccessibilitySize
                    ? AnyLayout(VStackLayout(alignment: .leading, spacing: 4))
                    : AnyLayout(HStackLayout(alignment: .firstTextBaseline, spacing: 8))
                layout {
                    Text("Görevler")
                        .font(.subheadline.bold())
                        .foregroundStyle(Color.ink.text)
                        .accessibilityAddTraits(.isHeader)
                    if !dynamicTypeSize.isAccessibilitySize { Spacer(minLength: 8) }
                    HStack(alignment: .firstTextBaseline, spacing: 0) {
                        Text("\(counts.createdTasks) görev oluşturuldu")
                        Text(verbatim: " · " + change)
                    }
                    .font(.caption)
                    .monospacedDigit()
                    .foregroundStyle(Color.ink.secondaryText)
                }
                .accessibilityElement(children: .combine)
                if let taskFlow {
                    TaskFlowChart(series: taskFlow)
                }
                InkSegmentBar(segments: [
                    .init(
                        id: 0, title: PresentationLocalization.string(localized: "Tamamlanan", locale: locale),
                        value: counts.completedTasks, style: .done),
                    .init(
                        id: 1, title: PresentationLocalization.string(localized: "Devreden", locale: locale),
                        value: counts.overdueTasks, style: .carried),
                    .init(
                        id: 2, title: PresentationLocalization.string(localized: "Tarihsiz açık", locale: locale),
                        value: counts.undatedTasks, style: .outline),
                ])
            }
        }
    }
}
