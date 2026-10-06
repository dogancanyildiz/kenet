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
            .padding(.vertical, 10)
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
    }
}
