import SwiftUI

/// Section card: opaque `surface`, 1 pt `rule`, platform corner, padded content.
/// Multi-child builders are stacked once so chrome is not applied per child.
struct InkCard<Content: View>: View {
    var bordered: Bool = true
    var padded: Bool = true
    @ViewBuilder var content: () -> Content

    @ScaledMetric(relativeTo: .body) private var padding = InkSpacing.cardPadding

    var body: some View {
        let stack = VStack(alignment: .leading, spacing: InkSpacing.row) {
            content()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        Group {
            if padded {
                stack.padding(padding)
            } else {
                stack
            }
        }
        .modifier(InkCardModifier(bordered: bordered, cornerRadius: InkCorner.card))
    }
}

/// Hairline divider between rows inside an ``InkCard``.
struct InkCardDivider: View {
    /// The hairline starts where the row's content starts (``InkSpacing/cardPadding``), not at
    /// the card edge (drawing: Görevler, Kişiler, Ayarlar). `false` for a full-width rule.
    var inset = true
    @Environment(\.displayScale) private var displayScale

    var body: some View {
        Rectangle()
            .fill(Color.ink.rule)
            .frame(height: InkStroke.hairline(scale: displayScale))
            .padding(.leading, inset ? InkSpacing.cardPadding : 0)
            .accessibilityHidden(true)
    }
}

/// Applies Şafak card chrome. ``inkSurface`` and ``InkCard`` both use this.
struct InkCardModifier: ViewModifier {
    var bordered: Bool = true
    var cornerRadius: CGFloat = InkCorner.card
    @Environment(\.displayScale) private var displayScale

    func body(content: Content) -> some View {
        content
            .background {
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .fill(Color.ink.surface)
            }
            .overlay {
                if bordered {
                    RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                        .stroke(Color.ink.rule, lineWidth: InkStroke.hairline(scale: displayScale))
                }
            }
    }
}

/// Where a list row sits in a section card drawn across several `List` rows (screens.md: the
/// task list's sections are cards). The first row rounds the top, the last the bottom; rows in
/// between are open at both ends and the card draws an ``InkCardDivider`` under every row but
/// the last.
enum InkCardSegment: Equatable, Sendable {
    case single, first, middle, last

    /// The segment of row `index` in a card of `count` rows.
    static func position(_ index: Int, of count: Int) -> Self {
        switch (index, count) {
        case (_, ...1): .single
        case (0, _): .first
        case (count - 1, _): .last
        default: .middle
        }
    }

    var roundsTop: Bool { self == .single || self == .first }
    var roundsBottom: Bool { self == .single || self == .last }
}

/// The section card's piece behind one list row (``View/inkListRow(columnSelected:cardSegment:)``):
/// paper around it, the row's `surface` part of the card with the card's 1 pt `rule` edge, the
/// divider under the row and, when the row is selected, the list selection inside the card.
/// It is the row's background, so the row's own height and insets stay those of any list row.
struct InkCardSegmentBackground: View {
    let segment: InkCardSegment
    var isSelected = false
    /// The row's vertical list inset: open ends reach through it to the next row.
    var verticalInset: CGFloat = InkListRowInsets.vertical
    @Environment(\.displayScale) private var displayScale

    var body: some View {
        let radius = InkCorner.card
        let shape = UnevenRoundedRectangle(
            topLeadingRadius: segment.roundsTop ? radius : 0,
            bottomLeadingRadius: segment.roundsBottom ? radius : 0,
            bottomTrailingRadius: segment.roundsBottom ? radius : 0,
            topTrailingRadius: segment.roundsTop ? radius : 0,
            style: .continuous)
        ZStack {
            InkListRowPaper()
            ZStack(alignment: .bottom) {
                shape.fill(Color.ink.surface)
                if isSelected {
                    RoundedRectangle(cornerRadius: InkListSelectionChrome.cornerRadius, style: .continuous)
                        .fill(InkListSelectionChrome.fillColor)
                        .overlay(alignment: .leading) {
                            Rectangle()
                                .fill(InkListSelectionChrome.markColor)
                                .frame(width: InkListSelectionChrome.markWidth)
                        }
                        .clipShape(
                            RoundedRectangle(cornerRadius: InkListSelectionChrome.cornerRadius, style: .continuous)
                        )
                        .padding(.horizontal, InkListSelectionChrome.horizontalInset)
                        .padding(.vertical, InkListSelectionChrome.verticalInset)
                }
                InkCardSegmentEdge(segment: segment, radius: radius)
                    .stroke(Color.ink.rule, lineWidth: InkStroke.hairline(scale: displayScale))
                if !segment.roundsBottom {
                    InkCardDivider()
                }
            }
            .padding(.horizontal, InkSpacing.margin)
            .padding(.top, segment.roundsTop ? verticalInset : 0)
            .padding(.bottom, segment.roundsBottom ? verticalInset : 0)
        }
        .accessibilityHidden(true)
    }
}

/// The card edge a segment draws: both sides, plus the rounded top or bottom where it closes.
private struct InkCardSegmentEdge: Shape {
    let segment: InkCardSegment
    let radius: CGFloat

    func path(in rect: CGRect) -> Path {
        let top = segment.roundsTop ? radius : 0
        let bottom = segment.roundsBottom ? radius : 0
        var path = Path()
        // Leading side, from the bottom up, then the top, then the trailing side down.
        path.move(to: CGPoint(x: rect.minX + bottom, y: rect.maxY))
        if bottom > 0 {
            path.addArc(
                center: CGPoint(x: rect.minX + bottom, y: rect.maxY - bottom), radius: bottom,
                startAngle: .degrees(90), endAngle: .degrees(180), clockwise: false)
        }
        path.addLine(to: CGPoint(x: rect.minX, y: rect.minY + top))
        if top > 0 {
            path.addArc(
                center: CGPoint(x: rect.minX + top, y: rect.minY + top), radius: top,
                startAngle: .degrees(180), endAngle: .degrees(270), clockwise: false)
            path.addLine(to: CGPoint(x: rect.maxX - top, y: rect.minY))
            path.addArc(
                center: CGPoint(x: rect.maxX - top, y: rect.minY + top), radius: top,
                startAngle: .degrees(270), endAngle: .degrees(0), clockwise: false)
        } else {
            path.move(to: CGPoint(x: rect.maxX, y: rect.minY))
        }
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY - bottom))
        if bottom > 0 {
            path.addArc(
                center: CGPoint(x: rect.maxX - bottom, y: rect.maxY - bottom), radius: bottom,
                startAngle: .degrees(0), endAngle: .degrees(90), clockwise: false)
            path.addLine(to: CGPoint(x: rect.minX + bottom, y: rect.maxY))
        }
        return path
    }
}
