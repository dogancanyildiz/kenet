import SwiftUI

/// Token color mapping for ``InkButtonChrome``.
extension InkButtonChrome {
    static func color(for token: Token) -> Color {
        switch token {
        case .secondaryText: Color.ink.secondaryText
        case .paper: Color.ink.paper
        case .text: Color.ink.text
        case .well: Color.ink.well
        case .onAccent: Color.ink.onAccent
        case .accent: Color.ink.accent
        case .danger: Color.ink.danger
        case .control: Color.ink.control
        }
    }
}

struct InkPrimaryButtonStyle: ButtonStyle {
    @Environment(\.isEnabled) private var isEnabled

    func makeBody(configuration: Configuration) -> some View {
        let role = InkButtonChrome.primary.role(
            isPressed: configuration.isPressed, isEnabled: isEnabled)
        return configuration.label
            .font(.ink.byline)
            .foregroundStyle(InkButtonChrome.color(for: role.foreground))
            .padding(.horizontal, 16)
            // Padding keeps the label off the capsule edge at accessibility sizes; the frame
            // guarantees the 44 pt touch target at the default size.
            .padding(.vertical, 10)
            .frame(minHeight: InkButtonChrome.minimumHeight)
            .background {
                if let background = role.background {
                    Capsule().fill(InkButtonChrome.color(for: background))
                }
            }
            .contentShape(Capsule())
    }
}

struct InkTextButtonStyle: ButtonStyle {
    @Environment(\.isEnabled) private var isEnabled

    func makeBody(configuration: Configuration) -> some View {
        let role = InkButtonChrome.text.role(
            isPressed: configuration.isPressed, isEnabled: isEnabled)
        return configuration.label
            .font(.ink.byline)
            .foregroundStyle(InkButtonChrome.color(for: role.foreground))
            .frame(minHeight: InkButtonChrome.minimumHeight)
            .contentShape(Rectangle())
    }
}

struct InkDestructiveButtonStyle: ButtonStyle {
    @Environment(\.isEnabled) private var isEnabled

    func makeBody(configuration: Configuration) -> some View {
        let role = InkButtonChrome.destructive.role(
            isPressed: configuration.isPressed, isEnabled: isEnabled)
        return configuration.label
            .font(.ink.byline)
            .foregroundStyle(InkButtonChrome.color(for: role.foreground))
            .frame(minHeight: InkButtonChrome.minimumHeight)
            .contentShape(Rectangle())
    }
}
