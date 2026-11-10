import SwiftUI

/// One stacked bar whose parts add up to a whole, with a legend that carries the numbers.
/// The parts differ by pattern as well as tone (drawing: Özetler): done solid, carried hatched in
/// the warning color, undated a light outlined fill. Done has no green of its own (decisions
/// 2026-11-09): it takes the secondary text color.
struct InkSegmentBar: View {
    enum Style: Sendable {
        /// Done work recedes: solid secondary text.
        case done
        /// Open work carried on: warning hatching.
        case carried
        /// Open work without a date: light gray fill with an outline.
        case outline
    }

    struct Segment: Identifiable, Sendable {
        let id: Int
        let title: String
        let value: Int
        let style: Style
    }

    let segments: [Segment]
    @ScaledMetric(relativeTo: .footnote) private var height: CGFloat = 12
    @ScaledMetric(relativeTo: .footnote) private var swatchSize: CGFloat = 12

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            GeometryReader { geo in
                let shown = segments.filter { $0.value > 0 }
                let total = CGFloat(shown.reduce(0) { $0 + $1.value })
                let gaps = CGFloat(max(0, shown.count - 1)) * 2
                HStack(spacing: 2) {
                    if total == 0 {
                        Capsule().fill(Color.ink.well)
                    } else {
                        ForEach(shown) { segment in
                            part(segment.style)
                                .frame(width: max(3, (geo.size.width - gaps) * CGFloat(segment.value) / total))
                        }
                    }
                }
            }
            .frame(height: height)
            .accessibilityHidden(true)
            InkFlowLayout(spacing: 16, lineSpacing: 6) {
                ForEach(segments) { segment in
                    HStack(spacing: 6) {
                        part(segment.style).frame(width: swatchSize, height: swatchSize)
                        Text(verbatim: segment.title)
                            .font(.ink.meta)
                            .foregroundStyle(Color.ink.secondaryText)
                        Text(verbatim: segment.value.formatted())
                            .font(.ink.meta.weight(.semibold))
                            .monospacedDigit()
                            .foregroundStyle(Color.ink.text)
                    }
                    .accessibilityElement(children: .combine)
                }
            }
        }
    }

    @ViewBuilder
    private func part(_ style: Style) -> some View {
        let shape = RoundedRectangle(cornerRadius: 3, style: .continuous)
        switch style {
        case .done:
            shape.fill(Color.ink.secondaryText)
        case .carried:
            shape.fill(Color.clear)
                .overlay { InkHatch().stroke(Color.ink.warning, lineWidth: InkStroke.control) }
                .clipShape(shape)
                .overlay { shape.strokeBorder(Color.ink.warning, lineWidth: InkStroke.rule) }
        case .outline:
            shape.fill(Color.ink.well)
                .overlay { shape.strokeBorder(Color.ink.control, lineWidth: InkStroke.rule) }
        }
    }
}

/// Diagonal lines 4 pt apart across the whole rectangle.
private struct InkHatch: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        let step: CGFloat = 4
        var x = rect.minX - rect.height
        while x < rect.maxX {
            path.move(to: CGPoint(x: x, y: rect.maxY))
            path.addLine(to: CGPoint(x: x + rect.height, y: rect.minY))
            x += step
        }
        return path
    }
}
