import Charts
import GoalTracking
import SwiftUI
import VaultFormat

/// "Son 90 gün" (30 at accessibility sizes) on a number goal's page: daily values against the target (daily goal), or totals
/// per week or month (weekly and yearly goals). Boolean and milestone goals draw nothing.
struct GoalValueChart: View {
    let goal: GoalDefinition
    let logs: [GoalLog]
    let today: CalendarDate
    @Environment(\.dynamicTypeSize) private var typeSize
    @Environment(\.locale) private var locale
    @Environment(\.timeZone) private var timeZone
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    /// One line of `ink.meta` (footnote) axis text, scaled with Dynamic Type.
    @ScaledMetric(relativeTo: .footnote) private var labelHeight: CGFloat = 16

    static let height: CGFloat = 160
    private static let axisNumber = FloatingPointFormatStyle<Double>.number.precision(.fractionLength(0...1))

    /// Plot labels: the chart reads as one accessibility element, so these are never shown.
    private enum Plot {
        static let day = "day"
        static let value = "value"
        static let target = "target"
        static let segment = "segment"
        static let period = "period"
    }

    static func isShown(for goal: GoalDefinition) -> Bool { goal.kind == .number }

    /// Days drawn by a daily goal: 90, or 30 at accessibility sizes, where the wider axis labels
    /// leave too little room for 90 points.
    static func span(isAccessibilitySize: Bool) -> Int { isAccessibilitySize ? 30 : 90 }

    /// Y axis values to label: the target always, and 0 and the top only when they sit at least `gap`
    /// (a fraction of the axis) away from it, so a label never overlaps "hedef N".
    static func axisValues(target: Double, top: Double, domain: Double, gap: Double) -> [Double] {
        ([0, top].filter { domain > 0 && abs($0 - target) / domain >= gap } + [target]).sorted()
    }

    static func title(for goal: GoalDefinition, isAccessibilitySize: Bool) -> String {
        switch goal.period {
        case .day: String(localized: "Son \(span(isAccessibilitySize: isAccessibilitySize)) gün")
        case .week: String(localized: "Son 12 hafta")
        case .year: String(localized: "Son 12 ay")
        }
    }

    /// At accessibility sizes the X labels grow; the chart grows with them so the plot keeps about 160 pt.
    private var chartHeight: CGFloat {
        typeSize.isAccessibilitySize ? Self.height + labelHeight + 8 : Self.height
    }

    /// The axis fraction one label line needs: the label's height over the plot, at least 15 %.
    private var labelGap: Double { max(0.15, Double(labelHeight / Self.height)) }

    var body: some View {
        Group {
            if goal.period == .day {
                daily(
                    GoalValueSeries.daily(
                        logs: logs, target: goal.target, today: today,
                        span: Self.span(isAccessibilitySize: typeSize.isAccessibilitySize)))
            } else if let totals = GoalPeriodTotals.make(goal: goal, logs: logs, today: today) {
                periodic(totals)
            }
        }
        .transaction { if reduceMotion { $0.animation = nil } }
    }

    // MARK: Daily line

    @ViewBuilder
    private func daily(_ series: GoalValueSeries) -> some View {
        if let average = series.average, let peak = series.peak {
            VStack(alignment: .leading, spacing: 8) {
                lineChart(series, peak: peak)
                    .frame(height: chartHeight)
                    .accessibilityElement(children: .ignore)
                    .accessibilityLabel(
                        String(
                            localized:
                                "Son \(series.span) gün: ortalama \(amount(average)), \(series.metCount) gün hedefin üstünde, en yüksek \(amount(peak.value)) \(dayText(peak.day))"
                        ))
                Text(
                    String(
                        localized: "Ortalama \(amount(average)) · \(series.metCount) günde hedefin üstünde")
                )
                .font(.ink.meta.monospacedDigit())
                .foregroundStyle(Color.ink.secondaryText)
                .accessibilityHidden(true)
            }
        } else {
            Text("Son \(series.span) günde kayıt yok")
                .font(.ink.meta)
                .foregroundStyle(Color.ink.secondaryText)
        }
    }

    /// Recorded days as points: filled at or above the target, a ring below it.
    @ChartContentBuilder
    private func dayPoints(_ series: GoalValueSeries) -> some ChartContent {
        ForEach(series.points.filter { $0.value >= series.target }, id: \.index) { point in
            PointMark(x: .value(Plot.day, point.index), y: .value(Plot.value, point.value))
                .symbol {
                    Circle().fill(Color.ink.accent).frame(width: 6, height: 6)
                }
        }
        ForEach(series.points.filter { $0.value < series.target }, id: \.index) { point in
            PointMark(x: .value(Plot.day, point.index), y: .value(Plot.value, point.value))
                .symbol {
                    Circle().fill(Color.ink.paper)
                        .overlay(Circle().strokeBorder(Color.ink.accent, lineWidth: 1.5))
                        .frame(width: 6, height: 6)
                }
        }
    }

    private func lineChart(_ series: GoalValueSeries, peak: GoalValueSeries.Point) -> some View {
        let top = max(peak.value, series.target, series.averages.map(\.value).max() ?? 0)
        // 90 days: a label at each month's first day. 30 days (accessibility sizes): the first and
        // the last day, so two labels name the span.
        let isShort = series.span < 60
        let monthStarts = (0..<series.span).filter { series.start.addingDays($0)?.day == 1 }
        return Chart {
            RuleMark(y: .value(Plot.target, series.target))
                .lineStyle(StrokeStyle(lineWidth: 1, dash: [4, 3]))
                .foregroundStyle(Color.ink.secondaryText)
            RuleMark(x: .value(Plot.day, series.span - 1))
                .lineStyle(StrokeStyle(lineWidth: 1))
                .foregroundStyle(Color.ink.control)
            ForEach(series.averages, id: \.index) { point in
                LineMark(
                    x: .value(Plot.day, point.index), y: .value(Plot.value, point.value),
                    series: .value(Plot.segment, point.segment)
                )
                .interpolationMethod(.monotone)
                .lineStyle(StrokeStyle(lineWidth: 2.5, lineCap: .round, lineJoin: .round))
                .foregroundStyle(Color.ink.accent)
            }
            dayPoints(series)
        }
        .chartXScale(domain: -1...series.span)
        .chartYScale(domain: 0...(max(top, 1) * 1.08))
        .chartXAxis {
            if isShort {
                AxisMarks(values: [0]) { _ in
                    AxisValueLabel(anchor: .topLeading) { dayLabel(series.start) }
                }
                AxisMarks(values: [series.span - 1]) { _ in
                    AxisValueLabel(anchor: .topTrailing) { dayLabel(today) }
                }
            } else {
                AxisMarks(values: monthStarts) { value in
                    AxisTick(length: 4, stroke: StrokeStyle(lineWidth: 1))
                        .foregroundStyle(Color.ink.control)
                    AxisValueLabel(anchor: .top) {
                        if let index = value.as(Int.self), let day = series.start.addingDays(index) {
                            Text(monthText(day))
                                .font(.ink.meta)
                                .foregroundStyle(Color.ink.secondaryText)
                        }
                    }
                }
            }
        }
        .chartYAxis {
            // The target's label names it ("hedef 20"): beside the dashed line, off the plotted values.
            AxisMarks(
                position: .leading,
                values: Self.axisValues(target: series.target, top: top, domain: max(top, 1) * 1.08, gap: labelGap)
            ) { value in
                AxisValueLabel {
                    if let number = value.as(Double.self) {
                        Text(
                            number == series.target
                                ? String(localized: "hedef \(number.formatted(Self.axisNumber.locale(locale)))")
                                : number.formatted(Self.axisNumber.locale(locale))
                        )
                        .font(.ink.meta.monospacedDigit())
                        .foregroundStyle(Color.ink.secondaryText)
                    }
                }
            }
        }
    }

    // MARK: Weekly / monthly bars

    @ViewBuilder
    private func periodic(_ totals: GoalPeriodTotals) -> some View {
        let peak = totals.peak
        VStack(alignment: .leading, spacing: 8) {
            barChart(totals)
                .frame(height: chartHeight)
                .accessibilityElement(children: .ignore)
                .accessibilityLabel(
                    String(
                        localized:
                            "\(Self.title(for: goal, isAccessibilitySize: typeSize.isAccessibilitySize)): toplam \(amount(totals.total)), en yüksek \(amount(peak?.total ?? 0)) \(peak.map { bucketText($0.start, unit: totals.unit) } ?? "")"
                    ))
            Text(totalText(totals))
                .font(.ink.meta.monospacedDigit())
                .foregroundStyle(Color.ink.secondaryText)
                .accessibilityHidden(true)
        }
    }

    private func totalText(_ totals: GoalPeriodTotals) -> String {
        switch totals.unit {
        case .week: String(localized: "Son 12 haftada toplam \(amount(totals.total))")
        case .month: String(localized: "Son 12 ayda toplam \(amount(totals.total))")
        }
    }

    private func barChart(_ totals: GoalPeriodTotals) -> some View {
        let top = max(totals.peak?.total ?? 0, totals.pace)
        let step = typeSize.isAccessibilitySize ? 6 : 3
        let labelled = totals.buckets.map(\.index).filter { (totals.buckets.count - 1 - $0).isMultiple(of: step) }
        // At accessibility sizes the last label would run past the plot's edge and be cut to "…".
        let trailing = typeSize.isAccessibilitySize ? totals.buckets.count - 1 : nil
        return Chart {
            ForEach(totals.buckets, id: \.index) { bucket in
                BarMark(
                    x: .value(Plot.period, bucket.index), y: .value(Plot.value, bucket.total), width: .fixed(14)
                )
                .foregroundStyle(Color.ink.accent)
                .cornerRadius(2)
            }
            RuleMark(y: .value(Plot.target, totals.pace))
                .lineStyle(StrokeStyle(lineWidth: 1, dash: [4, 3]))
                .foregroundStyle(Color.ink.secondaryText)
        }
        .chartXScale(domain: -0.6...(Double(totals.buckets.count) - 0.4))
        .chartYScale(domain: 0...(max(top, 1) * 1.15))
        .chartXAxis {
            AxisMarks(values: labelled) { value in
                AxisValueLabel(anchor: value.as(Int.self) == trailing ? .topTrailing : .top) {
                    if let index = value.as(Int.self), totals.buckets.indices.contains(index) {
                        Text(bucketText(totals.buckets[index].start, unit: totals.unit))
                            .font(.ink.meta)
                            .foregroundStyle(Color.ink.secondaryText)
                    }
                }
            }
        }
        .chartYAxis {
            AxisMarks(
                position: .leading,
                values: Self.axisValues(target: totals.pace, top: top, domain: max(top, 1) * 1.15, gap: labelGap)
            ) { value in
                AxisValueLabel {
                    if let number = value.as(Double.self) {
                        Text(
                            number == totals.pace
                                ? paceText(totals) : number.formatted(Self.axisNumber.locale(locale))
                        )
                        .font(.ink.meta.monospacedDigit())
                        .foregroundStyle(Color.ink.secondaryText)
                    }
                }
            }
        }
    }

    private func paceText(_ totals: GoalPeriodTotals) -> String {
        let value = totals.pace.formatted(Self.axisNumber.locale(locale))
        return switch totals.unit {
        case .week: String(localized: "hedef \(value)")
        case .month: String(localized: "ayda \(value)")
        }
    }

    // MARK: Text

    private func amount(_ value: Double) -> String {
        let number = value.formatted(.number.precision(.fractionLength(0)).locale(locale))
        return goal.unit.map { number + " " + $0 } ?? number
    }

    private func style(_ base: Date.FormatStyle) -> Date.FormatStyle {
        var style = base
        style.locale = locale
        style.timeZone = timeZone
        return style
    }

    private func dayText(_ day: CalendarDate) -> String {
        LocalDay.instant(for: day, timeZone: timeZone).formatted(style(.dateTime.day().month(.wide)))
    }

    private func dayLabel(_ day: CalendarDate) -> some View {
        Text(LocalDay.instant(for: day, timeZone: timeZone).formatted(style(.dateTime.day().month(.abbreviated))))
            .font(.ink.meta)
            .foregroundStyle(Color.ink.secondaryText)
    }

    private func monthText(_ day: CalendarDate) -> String {
        LocalDay.instant(for: day, timeZone: timeZone).formatted(style(.dateTime.month(.abbreviated)))
    }

    private func bucketText(_ start: CalendarDate, unit: GoalPeriodTotals.Unit) -> String {
        let date = LocalDay.instant(for: start, timeZone: timeZone)
        return switch unit {
        case .week: date.formatted(style(.dateTime.day().month(.abbreviated)))
        case .month: date.formatted(style(.dateTime.month(.abbreviated)))
        }
    }
}
