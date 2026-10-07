import SwiftUI

/// Surface chrome for sheets, popovers, and Mac kanban cards: `ink.surface`, optional hairline, no shadow.
struct InkSurfaceModifier: ViewModifier {
    var bordered: Bool = true
    var cornerRadius: CGFloat = InkSize.kanbanCorner
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

extension View {
    /// Applies Mürekkep surface fill and optional 1-pixel rule. Never adds a shadow.
    func inkSurface(bordered: Bool = true, cornerRadius: CGFloat = InkSize.kanbanCorner) -> some View {
        modifier(InkSurfaceModifier(bordered: bordered, cornerRadius: cornerRadius))
    }
}

/// Framed, shadowless paper card for Mac kanban (jury condition 6).
/// Named ``InkKanbanCard`` because ``KanbanCard`` already exists under Screens.
struct InkKanbanCard<Content: View>: View {
    var isDragging: Bool = false
    @ViewBuilder var content: () -> Content

    var body: some View {
        content()
            .padding(12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .inkSurface(bordered: true, cornerRadius: InkSize.kanbanCorner)
            .overlay {
                if isDragging {
                    RoundedRectangle(cornerRadius: InkSize.kanbanCorner, style: .continuous)
                        .stroke(Color.ink.accent, lineWidth: InkStroke.highPriority)
                }
            }
            .accessibilityAddTraits(isDragging ? [.updatesFrequently] : [])
    }
}
