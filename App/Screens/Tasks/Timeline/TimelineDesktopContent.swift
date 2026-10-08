import SwiftUI
import VaultFormat

#if os(macOS)

    /// Shared measures for the Mac chart and its label column so a row and its bar stay aligned.
    enum TimelineDesktopMetrics {
        static let labelColumnWidth: CGFloat = 260
        /// Title (up to two lines) plus the tabular date line.
        static let rowHeight: CGFloat = 68
        static let groupHeaderHeight: CGFloat = 32
        static let axisHeight: CGFloat = 44
    }

    /// Center of the "Bugün" word, plus the date labels that must drop to clear it.
    struct TimelineTodayLabelPlacement: Equatable {
        var centerX: CGFloat
        var centerY: CGFloat
        var loweredDateIndices: Set<Int>
    }

    /// Where "Bugün" sits. The word is wider than a quarter-scale cell, so centering it on the
    /// day runs the today line through the word and covers a neighboring date. The word moves
    /// beside the line, shifts inward when today is the first or last day of the range, and
    /// steps up when a date label would still cover it. A date that would still meet the raised
    /// word moves down by ``TimelineAxisLayout/loweredDateOffset``.
    enum TimelineAxisLayout {
        static let todayLabelHeight: CGFloat = 16
        static let dateLabelHeight: CGFloat = 16
        /// Upper row. A midline date (center 22, height 16) occupies y 14…30; this clears it.
        static let upperCenterY: CGFloat = 10
        /// Drops a colliding date from the midline to y 26…42, under the raised word.
        static let loweredDateOffset: CGFloat = 12
        /// Gap kept between the today line and the word.
        static let lineClearance: CGFloat = 4

        static func todayLabelPlacement(
            dayIndex: Int,
            dayCount: Int,
            dayWidth: CGFloat,
            labelWidth: CGFloat,
            dateLabelWidth: CGFloat,
            dateLabelDayIndices: Set<Int>
        ) -> TimelineTodayLabelPlacement {
            let width = max(dayWidth, 0)
            let chartWidth = CGFloat(max(dayCount, 1)) * width
            let lineX = (CGFloat(dayIndex) + 0.5) * width
            let label = max(labelWidth, 1)
            let half = label / 2
            let dateWidth = max(dateLabelWidth, 0)
            let midline = TimelineDesktopMetrics.axisHeight / 2
            let towardRight = clamped(lineX + lineClearance + half, half: half, label: label, chartWidth: chartWidth)
            let towardLeft = clamped(lineX - lineClearance - half, half: half, label: label, chartWidth: chartWidth)
            let preferRight = chartWidth - lineX >= lineX
            let preferred = preferRight ? towardRight : towardLeft
            let alternate = preferRight ? towardLeft : towardRight

            if fits(
                preferred, lineX: lineX, half: half, chartWidth: chartWidth, label: label, wordY: midline,
                dateWidth: dateWidth, dayWidth: width, dateY: midline, dates: dateLabelDayIndices)
            {
                return TimelineTodayLabelPlacement(centerX: preferred, centerY: midline, loweredDateIndices: [])
            }
            if fits(
                alternate, lineX: lineX, half: half, chartWidth: chartWidth, label: label, wordY: midline,
                dateWidth: dateWidth, dayWidth: width, dateY: midline, dates: dateLabelDayIndices)
            {
                return TimelineTodayLabelPlacement(centerX: alternate, centerY: midline, loweredDateIndices: [])
            }

            let centerX = besideLine(preferred, alternate, lineX: lineX, half: half, chartWidth: chartWidth)
            let word = wordFrame(centerX: centerX, centerY: upperCenterY, labelWidth: label)
            let lowered = Set(
                dateLabelDayIndices.filter { index in
                    word.intersects(
                        dateFrame(dayIndex: index, dayWidth: width, dateLabelWidth: dateWidth, centerY: midline))
                })
            return TimelineTodayLabelPlacement(
                centerX: centerX, centerY: upperCenterY, loweredDateIndices: lowered)
        }

        private static func clamped(_ center: CGFloat, half: CGFloat, label: CGFloat, chartWidth: CGFloat) -> CGFloat {
            guard chartWidth > label else { return chartWidth / 2 }
            return min(max(center, half), chartWidth - half)
        }

        /// Inside the chart, clear of the today line, and clear of every date label on `dateY`.
        private static func fits(
            _ center: CGFloat, lineX: CGFloat, half: CGFloat, chartWidth: CGFloat, label: CGFloat, wordY: CGFloat,
            dateWidth: CGFloat, dayWidth: CGFloat, dateY: CGFloat, dates: Set<Int>
        ) -> Bool {
            guard inside(center, half: half, chartWidth: chartWidth), !throughLine(center, lineX: lineX, half: half)
            else { return false }
            let word = wordFrame(centerX: center, centerY: wordY, labelWidth: label)
            return !dates.contains { index in
                word.intersects(
                    dateFrame(dayIndex: index, dayWidth: dayWidth, dateLabelWidth: dateWidth, centerY: dateY))
            }
        }

        private static func besideLine(
            _ preferred: CGFloat, _ alternate: CGFloat, lineX: CGFloat, half: CGFloat, chartWidth: CGFloat
        ) -> CGFloat {
            if inside(preferred, half: half, chartWidth: chartWidth), !throughLine(preferred, lineX: lineX, half: half)
            {
                return preferred
            }
            if inside(alternate, half: half, chartWidth: chartWidth), !throughLine(alternate, lineX: lineX, half: half)
            {
                return alternate
            }
            return preferred
        }

        private static func inside(_ center: CGFloat, half: CGFloat, chartWidth: CGFloat) -> Bool {
            center - half >= -0.01 && center + half <= chartWidth + 0.01
        }

        private static func throughLine(_ center: CGFloat, lineX: CGFloat, half: CGFloat) -> Bool {
            lineX > center - half && lineX < center + half
        }

        private static func wordFrame(centerX: CGFloat, centerY: CGFloat, labelWidth: CGFloat) -> CGRect {
            CGRect(
                x: centerX - labelWidth / 2, y: centerY - todayLabelHeight / 2, width: labelWidth,
                height: todayLabelHeight)
        }

        private static func dateFrame(
            dayIndex: Int, dayWidth: CGFloat, dateLabelWidth: CGFloat, centerY: CGFloat
        ) -> CGRect {
            let centerX = (CGFloat(dayIndex) + 0.5) * dayWidth
            return CGRect(
                x: centerX - dateLabelWidth / 2, y: centerY - dateLabelHeight / 2,
                width: dateLabelWidth, height: dateLabelHeight)
        }
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
        @State private var dateLabelWidth: CGFloat = 64

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
                TimelineGrid(days: days, today: model.today, dayWidth: dayWidth)
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
                    .frame(width: chartWidth, height: TimelineDesktopMetrics.rowHeight, alignment: .leading)
                    .clipped()
            } else {
                bar
            }
        }

        private var axis: some View {
            let placement = todayPlacement
            return HStack(spacing: 0) {
                ForEach(Array(days.enumerated()), id: \.element) { index, day in
                    ZStack {
                        if day.weekday >= 5 { Color.ink.well }
                        if day == model.today {
                            Color.ink.accent.opacity(0.12)
                        }
                        if showsAxisDateLabel(day) {
                            Text(LocalDay.instant(for: day), format: .dateTime.day().month(.abbreviated))
                                .font(.ink.time)
                                .foregroundStyle(.ink.secondaryText)
                                .monospacedDigit()
                                .fixedSize()
                                .onGeometryChange(for: CGFloat.self, of: { $0.size.width }) { width in
                                    if width > dateLabelWidth { dateLabelWidth = width }
                                }
                                .zIndex(1)
                                .offset(y: dateLabelOffset(index: index, placement: placement))
                        }
                    }
                    .frame(width: dayWidth, height: TimelineDesktopMetrics.axisHeight)
                    .id(day.description)
                }
            }
            .overlay {
                if let placement {
                    Text("Bugün")
                        .font(.ink.meta)
                        .foregroundStyle(.ink.accent)
                        .fixedSize()
                        .onGeometryChange(for: CGFloat.self, of: { $0.size.width }) { width in
                            if width > todayLabelWidth { todayLabelWidth = width }
                        }
                        .position(x: placement.centerX, y: placement.centerY)
                        .accessibilityAddTraits(.isHeader)
                }
            }
        }

        private var todayPlacement: TimelineTodayLabelPlacement? {
            guard let index = days.firstIndex(of: model.today) else { return nil }
            return TimelineAxisLayout.todayLabelPlacement(
                dayIndex: index,
                dayCount: days.count,
                dayWidth: dayWidth,
                labelWidth: todayLabelWidth,
                dateLabelWidth: dateLabelWidth,
                dateLabelDayIndices: Set(days.indices.filter { showsAxisDateLabel(days[$0]) }))
        }

        private func dateLabelOffset(index: Int, placement: TimelineTodayLabelPlacement?) -> CGFloat {
            placement?.loweredDateIndices.contains(index) == true ? TimelineAxisLayout.loweredDateOffset : 0
        }

        private func showsAxisDateLabel(_ day: CalendarDate) -> Bool {
            model.scale == .week || (model.scale == .month && day.weekday == 0) || day.day == 1
        }
    }

#endif
