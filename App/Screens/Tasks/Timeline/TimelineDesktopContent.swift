import SwiftUI
import VaultFormat

/// Shared measures for the Mac chart and its label column so a row and its bar stay aligned.
enum TimelineDesktopMetrics {
    static let labelColumnWidth: CGFloat = 260
    /// Title (up to two lines) plus the tabular date line.
    static let rowHeight: CGFloat = 68
    static let groupHeaderHeight: CGFloat = 32
    static let axisHeight: CGFloat = 44
}

/// Placement of an axis date label in the timeline axis overlay coordinate space.
struct TimelineDateLabelPlacement: Equatable, Identifiable {
    var dayIndex: Int
    var centerX: CGFloat
    var centerY: CGFloat

    var id: Int { dayIndex }
}

/// Axis rules (unit-tested). The date labels share one row in the axis' upper part, kept
/// inside the chart so the last one is never cut at the edge. "Bugün" is an accent capsule
/// centered on the today line in the axis' lower part (Şafak drawing), under the date row,
/// so it never covers a date and stays inside the scrolling axis.
enum TimelineAxisLayout {
    static let dateLabelHeight: CGFloat = 16
    /// Center of the date row.
    static let dateRowCenterY: CGFloat = 14

    /// Bottom of the date row: the grid's vertical lines start here, so they never cross a date.
    static var dateRowBottom: CGFloat { dateRowCenterY + dateLabelHeight / 2 + 2 }

    /// The capsule's center: its bottom edge on the axis' lower edge.
    static func todayCenterY(badgeHeight: CGFloat) -> CGFloat {
        TimelineDesktopMetrics.axisHeight - max(badgeHeight, 0) / 2 - 1
    }

    /// Center of a label of `labelWidth` on `dayIndex`, shifted inward at the chart's ends.
    static func centerX(dayIndex: Int, dayWidth: CGFloat, labelWidth: CGFloat, chartWidth: CGFloat) -> CGFloat {
        let center = (CGFloat(dayIndex) + 0.5) * max(dayWidth, 0)
        let half = max(labelWidth, 0) / 2
        guard chartWidth > half * 2 else { return chartWidth / 2 }
        return min(max(center, half), chartWidth - half)
    }

    static func dateLabelPlacements(
        dayIndices: [Int], dayWidth: CGFloat, labelWidth: CGFloat, chartWidth: CGFloat
    ) -> [TimelineDateLabelPlacement] {
        dayIndices.map { index in
            TimelineDateLabelPlacement(
                dayIndex: index,
                centerX: centerX(dayIndex: index, dayWidth: dayWidth, labelWidth: labelWidth, chartWidth: chartWidth),
                centerY: dateRowCenterY)
        }
    }

    /// The "Bugün" capsule: on the today line, inside the chart.
    static func todayCenter(
        dayIndex: Int, dayWidth: CGFloat, labelWidth: CGFloat, badgeHeight: CGFloat, chartWidth: CGFloat
    ) -> CGPoint {
        CGPoint(
            x: centerX(dayIndex: dayIndex, dayWidth: dayWidth, labelWidth: labelWidth, chartWidth: chartWidth),
            y: todayCenterY(badgeHeight: badgeHeight))
    }

    /// The chart's visible part, in chart points: the days of `visible` (whole days, as the
    /// scroll view reports them) counted from `firstDay`, the chart's first drawn day.
    static func visibleSpan(
        _ visible: ClosedRange<CalendarDate>, firstDay: CalendarDate, dayWidth: CGFloat
    ) -> ClosedRange<CGFloat> {
        let lower = CGFloat(visible.lowerBound.ordinal - firstDay.ordinal) * max(dayWidth, 0)
        let upper = CGFloat(visible.upperBound.ordinal - firstDay.ordinal + 1) * max(dayWidth, 0)
        return lower...max(lower, upper)
    }

    /// A date label shows only whole: one that the scroll view's edge would cut is left out
    /// (fark3 P6: "1 Şub" cut at the phone card's right edge).
    static func showsWhole(centerX: CGFloat, labelWidth: CGFloat, in span: ClosedRange<CGFloat>) -> Bool {
        let half = max(labelWidth, 0) / 2
        return centerX - half >= span.lowerBound - 0.5 && centerX + half <= span.upperBound + 0.5
    }

    static func showsAxisDateLabel(_ day: CalendarDate, scale: TimelineModel.Scale) -> Bool {
        scale == .week || (scale == .month && day.weekday == 0) || day.day == 1
    }

    /// Weekend wells read as stripes once a day is a few points wide (Çeyrek): the drawing
    /// shows a plain axis there.
    static func showsWeekends(scale: TimelineModel.Scale) -> Bool { scale != .quarter }
}

/// Non-scrolling timeline chart shared by ``TimelineDesktopView`` and Mac snapshots:
/// axis (weekend wells, today label, date labels), grid (today vertical line), and bars.
struct TimelineDesktopContent: View {
    let model: TimelineModel
    /// Days drawn on the axis and grid (full bounds in production; a week window in tests).
    let days: [CalendarDate]
    let dayWidth: CGFloat
    let select: (TaskRow) -> Void
    let edit: (TaskRow, TimelineDates.Edge) -> Void
    var maxRowsPerGroup: Int? = nil
    /// Floors until the drawn word and date labels report a larger width.
    @State private var todayLabelWidth: CGFloat = 48
    @State private var todayBadgeHeight: CGFloat = 18
    @State private var dateLabelWidth: CGFloat = 64
    @Environment(\.timelineRowHeight) private var rowHeight

    var body: some View {
        let chartWidth = CGFloat(days.count) * dayWidth
        let shift =
            days.first.map {
                CGFloat($0.ordinal - model.bounds.lowerBound.ordinal) * dayWidth
            } ?? 0
        let clipsToWindow = days.count != model.days.count

        VStack(spacing: 0) {
            axis
            ForEach(model.groups) { group in
                Color.clear.frame(height: TimelineDesktopMetrics.groupHeaderHeight)
                if !model.collapsed.contains(group.id) {
                    let rows = maxRowsPerGroup.map { Array(group.rows.prefix($0)) } ?? group.rows
                    ForEach(rows) { row in
                        chartRow(
                            row, shift: shift, clipsToWindow: clipsToWindow, chartWidth: chartWidth)
                    }
                }
            }
        }
        .frame(width: chartWidth)
        .background {
            TimelineGrid(
                days: days, today: model.today, dayWidth: dayWidth,
                showsWeekends: TimelineAxisLayout.showsWeekends(scale: model.scale),
                lineTop: TimelineAxisLayout.dateRowBottom)
        }
        .coordinateSpace(name: "timeline-axis")
    }

    @ViewBuilder
    private func chartRow(
        _ row: TaskRow, shift: CGFloat, clipsToWindow: Bool, chartWidth: CGFloat
    ) -> some View {
        let bar = TimelineBarView(model: model, row: row, dayWidth: dayWidth) {
            select(row)
        } edit: {
            edit(row, $0)
        }
        if clipsToWindow {
            bar
                .offset(x: -shift)
                .frame(width: chartWidth, height: rowHeight, alignment: .leading)
                .clipped()
        } else {
            bar
        }
    }

    private var axis: some View {
        let chartWidth = CGFloat(days.count) * dayWidth
        let datePlacements = TimelineAxisLayout.dateLabelPlacements(
            dayIndices: dateLabelDayIndices, dayWidth: dayWidth, labelWidth: dateLabelWidth,
            chartWidth: chartWidth)
        let showsWeekends = TimelineAxisLayout.showsWeekends(scale: model.scale)
        let visible = days.first.map {
            TimelineAxisLayout.visibleSpan(model.visibleRange, firstDay: $0, dayWidth: dayWidth)
        }
        return HStack(spacing: 0) {
            ForEach(days, id: \.self) { day in
                ZStack {
                    if showsWeekends && day.weekday >= 5 { Color.ink.well }
                    if day == model.today {
                        Color.ink.accent.opacity(0.12)
                    }
                }
                .frame(width: dayWidth, height: TimelineDesktopMetrics.axisHeight)
                .id(day.description)
            }
        }
        .overlay {
            ZStack {
                ForEach(
                    datePlacements.filter { item in
                        visible.map {
                            TimelineAxisLayout.showsWhole(
                                centerX: item.centerX, labelWidth: dateLabelWidth, in: $0)
                        } ?? true
                    }
                ) { item in
                    let day = days[item.dayIndex]
                    Text(LocalDay.instant(for: day), format: .dateTime.day().month(.abbreviated))
                        .font(.ink.time)
                        .foregroundStyle(.ink.secondaryText)
                        .monospacedDigit()
                        .fixedSize()
                        .onGeometryChange(for: CGFloat.self, of: { $0.size.width }) { width in
                            if width > dateLabelWidth { dateLabelWidth = width }
                        }
                        .position(x: item.centerX, y: item.centerY)
                }
                if let index = days.firstIndex(of: model.today) {
                    let center = TimelineAxisLayout.todayCenter(
                        dayIndex: index, dayWidth: dayWidth, labelWidth: todayLabelWidth,
                        badgeHeight: todayBadgeHeight, chartWidth: chartWidth)
                    TimelineTodayBadge()
                        .onGeometryChange(for: CGSize.self, of: { $0.size }) { size in
                            if size.width > todayLabelWidth { todayLabelWidth = size.width }
                            todayBadgeHeight = size.height
                        }
                        .position(x: center.x, y: center.y)
                }
            }
        }
    }

    private var dateLabelDayIndices: [Int] {
        days.indices.filter { showsAxisDateLabel(days[$0]) }
    }

    private func showsAxisDateLabel(_ day: CalendarDate) -> Bool {
        TimelineAxisLayout.showsAxisDateLabel(day, scale: model.scale)
    }
}

/// "Bugün" on the chart axis: a filled accent capsule (Şafak drawing).
struct TimelineTodayBadge: View {
    var body: some View {
        Text("Bugün")
            .font(.ink.meta.weight(.bold))
            .foregroundStyle(Color.ink.onAccent)
            .fixedSize()
            .padding(.horizontal, 6)
            .padding(.vertical, 1)
            .background(Capsule().fill(Color.ink.accent))
            .accessibilityAddTraits(.isHeader)
    }
}
