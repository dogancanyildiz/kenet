import SwiftUI
import VaultFormat

#if os(macOS)

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
                    Color.clear.frame(height: 32)
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
                    .frame(width: chartWidth, height: 52, alignment: .leading)
                    .clipped()
            } else {
                bar
            }
        }

        private var axis: some View {
            HStack(spacing: 0) {
                ForEach(days, id: \.self) { day in
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
                                .zIndex(1)
                                .offset(y: day == model.today ? 8 : 0)
                        }
                        if day == model.today {
                            Text("Bugün")
                                .font(.ink.meta)
                                .foregroundStyle(.ink.accent)
                                .fixedSize()
                                .zIndex(2)
                                .offset(y: showsAxisDateLabel(day) ? -8 : 0)
                                .accessibilityAddTraits(.isHeader)
                        }
                    }.frame(width: dayWidth, height: 44).id(day.description)
                }
            }
        }

        private func showsAxisDateLabel(_ day: CalendarDate) -> Bool {
            model.scale == .week || (model.scale == .month && day.weekday == 0) || day.day == 1
        }
    }

#endif
