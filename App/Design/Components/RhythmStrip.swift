import SwiftUI

/// Whether a rhythm unit was written. Shape carries the state, never color alone:
/// filled dot, ring, short dash, nothing (not come yet).
enum RhythmMark: Equatable, Sendable {
    case full, partial, none, notStarted
}

struct RhythmStripItem: Identifiable, Equatable, Sendable {
    let id: Int
    /// Short column label: "Pzt", "1–7", "Oca".
    let label: String
    let spokenLabel: String
    let value: Int
    /// The same unit of the period before; drawn as a wide quiet bar behind the current one.
    let previous: Int?
    let mark: RhythmMark
    /// VoiceOver value: count, the period before and the mark, already localized by the caller.
    let spokenValue: String
}

struct RhythmLegendItem: Identifiable, Sendable {
    enum Swatch: Sendable {
        case current, previous
        case mark(RhythmMark)
    }
    let swatch: Swatch
    let title: String
    var id: String { title }
}

/// Bar strip of a period's units with the previous period drawn wide and quiet behind each bar.
/// Accessibility sizes turn the columns into rows, so labels and numbers keep their size.
struct RhythmStrip: View {
    let items: [RhythmStripItem]
    let legend: [RhythmLegendItem]
    var barHeight: CGFloat = 112
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @ScaledMetric(relativeTo: .footnote) private var markSize: CGFloat = 7

    private var maxValue: Int {
        max(1, items.map { max($0.mark == .notStarted ? 0 : $0.value, $0.previous ?? 0) }.max() ?? 1)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            if dynamicTypeSize.isAccessibilitySize { rows } else { columns }
            legendView
        }
    }

    private var columns: some View {
        HStack(alignment: .bottom, spacing: items.count > 8 ? 2 : 6) {
            ForEach(items) { item in
                VStack(spacing: 4) {
                    Text(verbatim: item.mark == .notStarted ? " " : item.value.formatted())
                        .font(.ink.meta)
                        .monospacedDigit()
                        .foregroundStyle(Color.ink.secondaryText)
                        .lineLimit(1)
                        .minimumScaleFactor(0.6)
                    GeometryReader { geo in
                        ZStack(alignment: .bottom) {
                            if let previous = item.previous, previous > 0 {
                                bar(previousColor, height: height(previous, in: geo.size.height))
                                    .frame(width: geo.size.width)
                            }
                            if item.mark != .notStarted, item.value > 0 {
                                bar(Color.ink.accent, height: height(item.value, in: geo.size.height))
                                    .frame(width: max(4, geo.size.width * 0.5))
                            }
                        }
                        .frame(width: geo.size.width, height: geo.size.height, alignment: .bottom)
                    }
                    .frame(height: barHeight)
                    baseline
                    markView(item.mark)
                        .frame(height: markSize + 2)
                    Text(verbatim: item.label)
                        .font(.ink.meta)
                        .foregroundStyle(Color.ink.secondaryText)
                        .lineLimit(1)
                        .minimumScaleFactor(0.6)
                }
                .frame(maxWidth: .infinity)
                .accessibilityElement(children: .ignore)
                .accessibilityLabel(Text(verbatim: item.spokenLabel))
                .accessibilityValue(Text(verbatim: item.spokenValue))
            }
        }
    }

    private var rows: some View {
        VStack(alignment: .leading, spacing: 10) {
            ForEach(items) { item in
                VStack(alignment: .leading, spacing: 4) {
                    HStack(alignment: .firstTextBaseline) {
                        Text(verbatim: item.label)
                            .font(.ink.meta)
                            .foregroundStyle(Color.ink.text)
                        Spacer(minLength: 8)
                        markView(item.mark)
                        Text(verbatim: item.mark == .notStarted ? "" : item.value.formatted())
                            .font(.ink.value)
                            .foregroundStyle(Color.ink.text)
                    }
                    GeometryReader { geo in
                        ZStack(alignment: .leading) {
                            if let previous = item.previous, previous > 0 {
                                Capsule().fill(previousColor)
                                    .frame(width: geo.size.width * ratio(previous), height: 12)
                            }
                            if item.mark != .notStarted, item.value > 0 {
                                Capsule().fill(Color.ink.accent)
                                    .frame(width: max(4, geo.size.width * ratio(item.value)), height: 6)
                            }
                        }
                        .frame(height: 12)
                    }
                    .frame(height: 12)
                }
                .accessibilityElement(children: .ignore)
                .accessibilityLabel(Text(verbatim: item.spokenLabel))
                .accessibilityValue(Text(verbatim: item.spokenValue))
            }
        }
    }

    /// The previous period: wide and quiet in both themes. The well token disappears on dark paper.
    private var previousColor: Color { Color.ink.control.opacity(0.3) }

    private var baseline: some View {
        Rectangle()
            .fill(Color.ink.rule)
            .frame(height: 1)
            .accessibilityHidden(true)
    }

    private var legendView: some View {
        let layout =
            dynamicTypeSize.isAccessibilitySize
            ? AnyLayout(VStackLayout(alignment: .leading, spacing: 6))
            : AnyLayout(InkFlowLayout(spacing: 14, lineSpacing: 6))
        return layout {
            ForEach(legend) { entry in
                HStack(spacing: 6) {
                    swatch(entry.swatch)
                    Text(verbatim: entry.title)
                        .font(.ink.meta)
                        .foregroundStyle(Color.ink.secondaryText)
                }
            }
        }
        .accessibilityElement(children: .combine)
    }

    @ViewBuilder
    private func swatch(_ swatch: RhythmLegendItem.Swatch) -> some View {
        switch swatch {
        case .current:
            RoundedRectangle(cornerRadius: 2).fill(Color.ink.accent).frame(width: 6, height: 12)
        case .previous:
            RoundedRectangle(cornerRadius: 2).fill(previousColor).frame(width: 14, height: 12)
        case .mark(let mark):
            markView(mark)
        }
    }

    @ViewBuilder
    private func markView(_ mark: RhythmMark) -> some View {
        switch mark {
        case .full:
            Circle().fill(Color.ink.text).frame(width: markSize, height: markSize)
        case .partial:
            Circle().stroke(Color.ink.text, lineWidth: InkStroke.control).frame(width: markSize, height: markSize)
        case .none:
            Capsule().fill(Color.ink.control).frame(width: markSize, height: InkStroke.control)
        case .notStarted:
            Color.clear.frame(width: markSize, height: markSize)
        }
    }

    private func bar(_ color: Color, height: CGFloat) -> some View {
        UnevenRoundedRectangle(topLeadingRadius: 3, topTrailingRadius: 3, style: .continuous)
            .fill(color)
            .frame(height: height)
    }

    private func ratio(_ value: Int) -> CGFloat { CGFloat(value) / CGFloat(maxValue) }

    private func height(_ value: Int, in total: CGFloat) -> CGFloat {
        max(2, total * ratio(value))
    }
}
