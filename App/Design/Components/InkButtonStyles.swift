import SwiftUI

/// Token color mapping for ``InkButtonChrome``.
extension InkButtonChrome {
    static func color(for token: Token) -> Color {
        switch token {
        case .secondaryText: Color.ink.secondaryText
        case .paper: Color.ink.paper
        case .text: Color.ink.text
        case .well: Color.ink.well
        case .surface: Color.ink.surface
        case .onAccent: Color.ink.onAccent
        case .accent: Color.ink.accent
        case .danger: Color.ink.danger
        case .control: Color.ink.control
        case .rule: Color.ink.rule
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
            .frame(minHeight: InkButtonChrome.minimumHeight)
            .background {
                if let background = role.background {
                    Capsule().fill(InkButtonChrome.color(for: background))
                }
            }
            .contentShape(Capsule())
    }
}

/// Secondary button: card (`surface`) fill capsule, 44 pt.
struct InkSecondaryButtonStyle: ButtonStyle {
    @Environment(\.isEnabled) private var isEnabled
    @Environment(\.displayScale) private var displayScale

    func makeBody(configuration: Configuration) -> some View {
        let role = InkButtonChrome.secondary.role(
            isPressed: configuration.isPressed, isEnabled: isEnabled)
        return configuration.label
            .font(.ink.byline)
            .foregroundStyle(InkButtonChrome.color(for: role.foreground))
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
            .frame(minHeight: InkButtonChrome.minimumHeight)
            .background {
                if let background = role.background {
                    Capsule()
                        .fill(InkButtonChrome.color(for: background))
                        .overlay {
                            Capsule()
                                .stroke(
                                    Color.ink.rule,
                                    lineWidth: InkStroke.hairline(scale: displayScale))
                        }
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
            .frame(
                minWidth: InkButtonChrome.minimumTextWidth, minHeight: InkButtonChrome.minimumHeight,
                alignment: .leading
            )
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
            .frame(
                minWidth: InkButtonChrome.minimumTextWidth, minHeight: InkButtonChrome.minimumHeight,
                alignment: .leading
            )
            .contentShape(Rectangle())
    }
}
