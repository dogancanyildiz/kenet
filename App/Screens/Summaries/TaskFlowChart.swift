import Charts
import Summaries
import SwiftUI
import VaultFormat

struct TaskFlowChart: View {
    let series: TaskFlowSeries
    @Environment(\.dynamicTypeSize) private var typeSize
    @Environment(\.locale) private var locale
    @Environment(\.timeZone) private var timeZone

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            openFlow
            Text("— açık görev  ┄ \(SummaryPresentation.previousTitle(series.period, locale: locale))")
                .accessibilityHidden(true)
            Text("Dönem sonunda \(series.closing) açık · dönem başında \(series.opening)")
                .accessibilityHidden(true)
        }
        .font(.ink.meta)
        .monospacedDigit()
        .foregroundStyle(Color.ink.secondaryText)
        .transaction {
            $0.animation = nil
            $0.disablesAnimations = true
        }
    }

    private func label(_ range: ClosedRange<CalendarDate>, short: Bool = false) -> String {
        let start = range.lowerBound
        let date = LocalDay.instant(for: start, timeZone: timeZone)
        switch series.period {
        case .week:
            return date.formatted(
                Date.FormatStyle(locale: locale, timeZone: timeZone).day().month(short ? .abbreviated : .wide))
        case .month:
            let days = "\(start.day)–\(range.upperBound.day)"
            return short
                ? days : days + " " + date.formatted(Date.FormatStyle(locale: locale, timeZone: timeZone).month(.wide))
        case .year:
            return date.formatted(
                Date.FormatStyle(locale: locale, timeZone: timeZone).month(short ? .abbreviated : .wide))
        }
    }

    private var openSummary: String {
        let peak = series.peak
        let peakLabel =
            peak.map { unit in
                series.period == .month
                    ? String(
                        localized: "\(unit.id + 1). hafta", bundle: PresentationLocalization.bundle(locale),
                        locale: locale) : label(unit.range)
            } ?? ""
        return String(
            localized:
                "Açık görevler: başta \(series.opening), sonda \(series.closing); en çok \(peakLabel) \(peak?.open ?? 0)",
            bundle: PresentationLocalization.bundle(locale), locale: locale
        )
    }

    private var openFlow: some View {
        Group {
            if typeSize.isAccessibilitySize {
                VStack(alignment: .leading, spacing: 8) {
                    ForEach(series.units) { unit in
                        Text(verbatim: "\(label(unit.range)): \(unit.open.formatted(.number.locale(locale)))")
                    }
                }
            } else {
                lineChart.frame(height: 164)
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(openSummary)
    }

    private var lineChart: some View {
        let ranges = series.units.first.map { series.period.units(containing: $0.range.lowerBound) } ?? []
        let top = max(1, (series.units + series.previous).map(\.open).max() ?? 0)
        return Chart {
            ForEach(series.previous) { unit in
                LineMark(x: .value("unit", unit.id), y: .value("open", unit.open), series: .value("series", "previous"))
                    .foregroundStyle(Color.ink.control)
                    .lineStyle(StrokeStyle(lineWidth: 2, dash: [4, 3]))
            }
            ForEach(series.units) { unit in
                LineMark(x: .value("unit", unit.id), y: .value("open", unit.open), series: .value("series", "current"))
                    .foregroundStyle(Color.ink.accent)
                PointMark(x: .value("unit", unit.id), y: .value("open", unit.open))
                    .foregroundStyle(Color.ink.accent)
                    .annotation(position: .top, alignment: .trailing) {
                        if unit.id == series.units.last?.id {
                            Text(verbatim: unit.open.formatted(.number.locale(locale)))
                                .font(.ink.meta).monospacedDigit()
                                .foregroundStyle(Color.ink.secondaryText)
                        }
                    }
            }
        }
        .chartXScale(domain: -0.5...(Double(max(series.unitCount, series.previous.count)) - 0.5))
        .chartYScale(domain: 0...(Double(top) * 1.2))
        .chartXAxis {
            AxisMarks(values: Array(0..<series.unitCount)) { value in
                AxisValueLabel {
                    if let index = value.as(Int.self),
                        ranges.indices.contains(index),
                        series.period != .year || index.isMultiple(of: 2)
                    {
                        Text(verbatim: label(ranges[index], short: true))
                            .fixedSize()
                            .font(.ink.meta).monospacedDigit()
                            .foregroundStyle(Color.ink.secondaryText)
                    }
                }
            }
        }
        .chartYAxis {
            AxisMarks(position: .leading, values: .automatic(desiredCount: 3)) { value in
                AxisGridLine().foregroundStyle(Color.ink.control)
                AxisValueLabel {
                    if let number = value.as(Double.self) {
                        Text(verbatim: number.formatted(.number.precision(.fractionLength(0)).locale(locale)))
                            .font(.ink.meta).monospacedDigit()
                            .foregroundStyle(Color.ink.secondaryText)
                    }
                }
            }
        }
    }
}
