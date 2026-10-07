import SwiftUI

/// Frameless icon drawing for a button on the manşet row: token color by role, 44 pt target,
/// no capsule. ``InkHeaderAction`` applies it itself; the `actions` slot of a manşet row also
/// sets it (utility role) as the default for plain buttons such as ``SearchButton``.
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
            .foregroundStyle(InkButtonChrome.color(for: token))
            .tapTarget()
    }
}
