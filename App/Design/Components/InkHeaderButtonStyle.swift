import SwiftUI

/// Frameless icon drawing for a button on the manşet row: token color by role, no capsule.
/// iPhone hit area is 44 pt via ``tapTarget()``. Mac symbol size and pointer target come from
/// ``View/inkHeaderIconMetrics()``. ``InkHeaderAction`` applies the style itself; the `actions`
/// slot of a manşet row also sets it (utility role) as the default for plain buttons such as
/// ``SearchButton``.
struct InkHeaderButtonStyle: ButtonStyle {
    var role: InkHeaderActionRole = .utility
    var isActive = false
    @Environment(\.isEnabled) private var isEnabled

    func makeBody(configuration: Configuration) -> some View {
        let token = InkHeaderActionChrome.token(
            role: role, isActive: isActive, isEnabled: isEnabled,
            isPressed: configuration.isPressed)
        // `tapTarget` on `configuration.label` is the placement that grows the hit area.
        return configuration.label
            .inkHeaderIconMetrics()
            .foregroundStyle(InkButtonChrome.color(for: token))
            .tapTarget()
            .inkPointerHighlight()
    }
}

extension View {
    /// Mac manşet icon: semantic `title2` symbol inside a pointer target of at least
    /// ``InkHeaderActionChrome/macMinimumSide``. No-op on iOS, where ``tapTarget()`` is 44 pt
    /// and the symbol stays the button's own size.
    func inkHeaderIconMetrics() -> some View {
        #if os(macOS)
            self
                .font(.title2)
                .frame(
                    minWidth: InkHeaderActionChrome.macMinimumSide,
                    minHeight: InkHeaderActionChrome.macMinimumSide
                )
                .contentShape(Rectangle())
        #else
            self
        #endif
    }
}

extension View {
    /// iPad pointer feedback for a frameless icon. No-op on Mac (its own hover) and without a
    /// pointer, so the iPhone drawing is unchanged.
    @ViewBuilder func inkPointerHighlight() -> some View {
        #if os(iOS)
            hoverEffect(.highlight)
        #else
            self
        #endif
    }

    /// iPad pointer feedback for a card that can be picked up (a Kanban card): the card lifts
    /// under the pointer. No-op on Mac and without a pointer.
    @ViewBuilder func inkPointerLift() -> some View {
        #if os(iOS)
            hoverEffect(.lift)
        #else
            self
        #endif
    }
}
