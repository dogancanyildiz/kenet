import SwiftUI

/// Icon drawing for a button on the manşet row: token color by role. On iOS the icon sits in a
/// translucent round chip (``InkHeaderActionChrome/Chrome/round``), on root and subpage rows
/// alike; on Mac it stays frameless.
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
            .inkHeaderIconChip()
            .tapTarget()
            .inkPointerHighlight()
    }
}

extension InkHeaderActionChrome {
    /// How a manşet icon is drawn.
    enum Chrome: Equatable, Sendable {
        /// iOS root manşet: icon in a translucent round chip.
        case round
        /// Bare icon (a caller that opts out; Mac is always bare).
        case bare
    }

    /// Diameter of the round chip (pt); the 44 pt touch target stays around it.
    static let chipDiameter: CGFloat = 40
}

extension EnvironmentValues {
    @Entry var inkHeaderActionChrome: InkHeaderActionChrome.Chrome = .round
}

extension View {
    /// The manşet icon's round chip (iOS, ``InkHeaderActionChrome/Chrome/round``). Under Reduce
    /// Transparency the chip is opaque.
    func inkHeaderIconChip() -> some View {
        modifier(InkHeaderIconChip())
    }
}

private struct InkHeaderIconChip: ViewModifier {
    @Environment(\.inkHeaderActionChrome) private var chrome
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    @ScaledMetric(relativeTo: .body) private var diameter = InkHeaderActionChrome.chipDiameter

    func body(content: Content) -> some View {
        #if os(iOS)
            if chrome == .round {
                content
                    // A smaller symbol in the chip (drawing: manşet buttons).
                    .font(.subheadline.weight(.medium))
                    .frame(minWidth: diameter, minHeight: diameter)
                    .background {
                        Circle()
                            .fill(Color.ink.surface.opacity(reduceTransparency ? 1 : 0.72))
                            .overlay(Circle().strokeBorder(Color.ink.line, lineWidth: 0.5))
                    }
            } else {
                content
            }
        #else
            content
        #endif
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
