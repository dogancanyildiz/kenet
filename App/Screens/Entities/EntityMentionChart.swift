import SwiftUI
import VaultFormat

// MARK: - Charts View (12-month bar chart + 90-day strip)

struct EntityMentionChartsView: View {
    let data: EntityMentionsData

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            EntityMonthlyBarChart(data: data)
            Entity90DayStrip(data: data)
        }
        .padding(.vertical, 4)
    }
}

// MARK: - 12-Month Bar Chart

struct EntityMonthlyBarChart: View {
    let data: EntityMentionsData
    var barHeight: CGFloat = 44
    var compact = false
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    private var maxCount: Int {
        max(1, data.monthly.map(\.count).max() ?? 1)
    }

    var body: some View {
        Group {
            if compact {
                compactColumns
            } else if dynamicTypeSize.isAccessibilitySize {
                accessibilityRows
            } else {
                columns
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text(verbatim: data.spokenSummary))
    }

    /// Şafak mini bar: 12 thin bars, an empty month a short stub in `line`, the current month
    /// outlined. `tint` is accent in lists and the place colour on map cards.
    private var compactColumns: some View {
        HStack(alignment: .bottom, spacing: 2) {
            ForEach(data.monthly) { item in
                let height = compactBarHeight * CGFloat(item.count) / CGFloat(maxCount)
                Group {
                    if item.count == 0 {
                        RoundedRectangle(cornerRadius: 1)
                            .fill(Color.ink.line)
                            .frame(height: 2)
                    } else if item.isCurrentMonth {
                        UnevenRoundedRectangle(topLeadingRadius: 1.5, topTrailingRadius: 1.5, style: .continuous)
                            .strokeBorder(tint, lineWidth: 1)
                            .frame(height: max(4, height))
                    } else {
                        UnevenRoundedRectangle(topLeadingRadius: 1.5, topTrailingRadius: 1.5, style: .continuous)
                            .fill(tint)
                            .frame(height: max(3, height))
                    }
                }
                .frame(width: compactBarWidth)
            }
        }
        .frame(height: compactBarHeight, alignment: .bottom)
        .fixedSize()
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text(verbatim: data.spokenSummary))
    }

    var tint: Color = .ink.accent
    @ScaledMetric(relativeTo: .caption) private var compactBarHeight: CGFloat = 22
    @ScaledMetric(relativeTo: .caption) private var compactBarWidth: CGFloat = 3

    private var columns: some View {
        HStack(alignment: .bottom, spacing: 3) {
            ForEach(data.monthly) { item in
                VStack(spacing: 4) {
                    GeometryReader { geo in
                        ZStack(alignment: .bottom) {
                            if item.count > 0 {
                                barShape(item: item, height: barHeight(for: item.count, in: geo.size.height))
                                    .frame(width: geo.size.width)
                            }
                        }
                        .frame(width: geo.size.width, height: geo.size.height, alignment: .bottom)
                    }
                    .frame(height: barHeight)

                    Rectangle()
                        .fill(Color.ink.rule)
                        .frame(height: InkStroke.rule)
                        .accessibilityHidden(true)

                    Text(verbatim: item.label)
                        .font(.ink.meta)
                        .foregroundStyle(Color.ink.secondaryText)
                        .lineLimit(1)
                        .minimumScaleFactor(0.6)
                }
                .frame(maxWidth: .infinity)
            }
        }
    }

    private var accessibilityRows: some View {
        VStack(alignment: .leading, spacing: 6) {
            ForEach(data.monthly) { item in
                VStack(alignment: .leading, spacing: 2) {
                    HStack(alignment: .firstTextBaseline) {
                        Text(verbatim: item.label)
                            .font(.ink.meta)
                            .foregroundStyle(Color.ink.text)
                            .fixedSize(horizontal: true, vertical: false)
                        Spacer(minLength: 8)
                        Text(verbatim: item.count > 0 ? "\(item.count)" : "")
                            .font(.ink.value)
                            .monospacedDigit()
                            .foregroundStyle(Color.ink.text)
                            .fixedSize(horizontal: true, vertical: false)
                    }
                    GeometryReader { geo in
                        let width =
                            item.count > 0 ? max(4, geo.size.width * CGFloat(item.count) / CGFloat(maxCount)) : 0
                        ZStack(alignment: .leading) {
                            if item.isCurrentMonth {
                                Capsule()
                                    .strokeBorder(Color.ink.accent, lineWidth: InkStroke.control)
                                    .frame(width: width, height: 8)
                            } else {
                                Capsule()
                                    .fill(Color.ink.accent)
                                    .frame(width: width, height: 8)
                            }
                        }
                    }
                    .frame(height: 8)
                }
            }
        }
    }

    @ViewBuilder
    private func barShape(item: EntityMonthlyMention, height: CGFloat) -> some View {
        if item.isCurrentMonth {
            UnevenRoundedRectangle(topLeadingRadius: 3, topTrailingRadius: 3, style: .continuous)
                .strokeBorder(Color.ink.accent, lineWidth: InkStroke.control)
                .frame(height: height)
        } else {
            UnevenRoundedRectangle(topLeadingRadius: 3, topTrailingRadius: 3, style: .continuous)
                .fill(Color.ink.accent)
                .frame(height: height)
        }
    }

    private func barHeight(for count: Int, in total: CGFloat) -> CGFloat {
        guard count > 0 else { return 0 }
        return max(3, total * (CGFloat(count) / CGFloat(maxCount)))
    }
}

// MARK: - 90-Day Strip

struct Entity90DayStrip: View {
    let data: EntityMentionsData
    /// A sentence appended to the frequency line ("Günlükteki geçişlere dayanır.").
    var footnote: String? = nil

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            stripRows
                .accessibilityElement(children: .ignore)
                .accessibilityLabel(Text(verbatim: data.recentIntervalText))

            Text(verbatim: [data.recentIntervalText, footnote].compactMap { $0 }.joined(separator: ". "))
                .font(.ink.meta)
                .foregroundStyle(Color.ink.secondaryText)
                // Two sentences on one line: at larger text sizes they wrap, never cut (audit).
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .leading)
                .accessibilityHidden(true)
        }
    }

    static func computeCellSize(availableWidth: CGFloat, columns: Int, spacing: CGFloat = 1) -> CGFloat {
        let cols = max(1, columns)
        let totalSpacing = CGFloat(cols - 1) * spacing
        let widthForCells = max(0, availableWidth - totalSpacing)
        return max(2, min(8, widthForCells / CGFloat(cols)))
    }

    private var stripRows: some View {
        let days = data.recentDays
        let splitIndex = days.count / 2
        let firstHalf = Array(days.prefix(splitIndex))
        let secondHalf = Array(days.suffix(from: splitIndex))

        return GeometryReader { geo in
            let spacing: CGFloat = 1
            let columns = max(1, max(firstHalf.count, secondHalf.count))
            let cellSize = Self.computeCellSize(
                availableWidth: geo.size.width,
                columns: columns,
                spacing: spacing
            )

            VStack(alignment: .leading, spacing: 3) {
                stripRow(days: firstHalf, cellSize: cellSize, spacing: spacing)
                stripRow(days: secondHalf, cellSize: cellSize, spacing: spacing)
            }
        }
        .frame(height: 19)
    }

    private func stripRow(days: [EntityRecentDay], cellSize: CGFloat, spacing: CGFloat) -> some View {
        HStack(spacing: spacing) {
            ForEach(days) { day in
                HeatmapCell(
                    kind: day.isMentioned ? .full : .empty,
                    size: cellSize,
                    isToday: day.isToday,
                    accessibilityValue: Text(verbatim: "")
                )
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}
