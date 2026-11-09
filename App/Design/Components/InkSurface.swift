import SwiftUI

/// Surface chrome for sheets, popovers, and Mac kanban cards.
/// Delegates to ``InkCardModifier`` so Şafak card tokens apply without breaking call sites.
struct InkSurfaceModifier: ViewModifier {
    var bordered: Bool = true
    var cornerRadius: CGFloat = InkSize.kanbanCorner

    func body(content: Content) -> some View {
        content.modifier(InkCardModifier(bordered: bordered, cornerRadius: cornerRadius))
    }
}

extension View {
    /// Applies Şafak surface fill and optional 1-pixel rule. Never adds a shadow.
    /// Delegates to ``InkCardModifier``.
    func inkSurface(bordered: Bool = true, cornerRadius: CGFloat = InkSize.kanbanCorner) -> some View {
        modifier(InkSurfaceModifier(bordered: bordered, cornerRadius: cornerRadius))
    }
}

/// Framed, shadowless paper card for Mac kanban (jury condition 6).
/// Named ``InkKanbanCard`` because ``KanbanCard`` already exists under Screens.
struct InkKanbanCard<Content: View>: View {
    var isDragging: Bool = false
    @ViewBuilder var content: () -> Content
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency

    var body: some View {
        content()
            .padding(12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .inkSurface(bordered: true, cornerRadius: InkSize.kanbanCorner)
            .overlay {
                if isDragging {
                    RoundedRectangle(cornerRadius: InkSize.kanbanCorner, style: .continuous)
                        .stroke(Color.ink.line, lineWidth: InkStroke.rule)
                }
            }
            .shadow(
                color: isDragging && !reduceTransparency
                    ? InkShadow.floating(colorScheme: colorScheme).color : .clear,
                radius: isDragging ? InkShadow.floating(colorScheme: colorScheme).radius : 0,
                y: isDragging ? InkShadow.floating(colorScheme: colorScheme).y : 0
            )
            .accessibilityAddTraits(isDragging ? [.updatesFrequently] : [])
    }
}
