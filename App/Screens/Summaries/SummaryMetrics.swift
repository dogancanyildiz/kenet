import Summaries
import SwiftUI

/// A headline number with its title and the change in words under it.
struct SummaryMetric: View {
    let title: LocalizedStringKey
    let value: Int
    /// "önceki haftaya göre +4": already localized. No arrow; the sign and the words carry it.
    let change: String
    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            LargeNumberText(verbatim: value.formatted())
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
        .accessibilityElement(children: .combine)
    }
}

/// Created tasks, then one stacked bar: completed, carried over past their date, open without a date.
struct SummaryTaskSection: View {
    let counts: SummaryCounts
    let change: String
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    var body: some View {
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
            InkSegmentBar(segments: [
                .init(id: 0, title: String(localized: "Tamamlanan"), value: counts.completedTasks, style: .done),
                .init(id: 1, title: String(localized: "Devreden"), value: counts.overdueTasks, style: .carried),
                .init(id: 2, title: String(localized: "Tarihsiz açık"), value: counts.undatedTasks, style: .outline),
            ])
        }
    }
}
