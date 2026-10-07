import Foundation

/// Token roles for button chrome (pressed / disabled use tokens, not opacity).
enum InkButtonChrome: Equatable, Sendable {
    case primary
    case text
    case destructive

    /// Minimum control height (Apple HIG). Styles apply this as layout and hit target.
    static let minimumHeight: CGFloat = 44

    enum Token: String, Equatable, Sendable {
        case secondaryText
        case paper
        case text
        case well
        case onAccent
        case accent
        case danger
        case control
    }

    struct Role: Equatable, Sendable {
        var foreground: Token
        var background: Token?
    }

    func role(isPressed: Bool, isEnabled: Bool) -> Role {
        switch self {
        case .primary:
            if !isEnabled { return Role(foreground: .secondaryText, background: .well) }
            if isPressed { return Role(foreground: .paper, background: .text) }
            return Role(foreground: .onAccent, background: .accent)
        case .text:
            if !isEnabled { return Role(foreground: .secondaryText, background: nil) }
            if isPressed { return Role(foreground: .text, background: nil) }
            return Role(foreground: .accent, background: nil)
        case .destructive:
            if !isEnabled { return Role(foreground: .secondaryText, background: nil) }
            if isPressed { return Role(foreground: .text, background: nil) }
            return Role(foreground: .danger, background: nil)
        }
    }
}
