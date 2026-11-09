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
    @Environment(\.displayScale) private var displayScale

    var body: some View {
        Rectangle()
            .fill(Color.ink.rule)
            .frame(height: InkStroke.hairline(scale: displayScale))
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
