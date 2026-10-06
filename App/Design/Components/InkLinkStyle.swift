import SwiftUI

/// Single source of truth for how person / place / unresolved links are drawn.
/// Reading (`Text`) and editable (`TextEditor` with `AttributedString`) share this path so
/// quick entry can adopt the same attributes later without forking styles.
enum InkLinkStyle {
    /// Active rendering path after Stage 9 validation on iOS/macOS 26.
    /// Underlines with color + pattern draw in `Text` and hosted `TextEditor`;
    /// `TextField` still binds `String` only (today's quick entry).
    enum Mode: Sendable {
        /// Link text stays ink text color; meaning is the underline (design rule 4).
        case underline
        /// Fallback: color the link text with person/place/secondary (no underline).
        case coloredText
    }

    /// Proven path: colored patterned underlines render; keep fallback available for callers.
    static let mode: Mode = .underline

    enum Kind: Sendable {
        case person
        case place
        /// Resolved vault link that is neither person nor place (project note, etc.).
        case other
        case unresolved
    }

    /// Applies the active mode's attributes to a link span (not the Turkish suffix).
    static func apply(
        _ kind: Kind, to string: inout AttributedString, highContrast: Bool,
        using renderingMode: Mode = InkLinkStyle.mode
    ) {
        switch renderingMode {
        case .underline:
            applyUnderline(kind, to: &string, highContrast: highContrast)
        case .coloredText:
            applyColoredText(kind, to: &string)
        }
    }

    static func attributed(
        _ text: String, kind: Kind, highContrast: Bool
    ) -> AttributedString {
        var value = AttributedString(text)
        apply(kind, to: &value, highContrast: highContrast)
        return value
    }

    // MARK: - Underline path

    private static func applyUnderline(
        _ kind: Kind, to string: inout AttributedString, highContrast: Bool
    ) {
        string.foregroundColor = Color.ink.text
        let pattern: Text.LineStyle.Pattern
        let color: Color
        switch kind {
        case .person:
            pattern = .solid
            color = .ink.person
        case .place:
            pattern = .dot
            color = .ink.place
        case .other:
            pattern = .solid
            color = .ink.secondaryText
        case .unresolved:
            pattern = .dash
            color = .ink.secondaryText
            string.foregroundColor = Color.ink.secondaryText
        }
        // Color + pattern via Text.LineStyle (validated). `highContrast` still selects
        // the asset-catalog high-contrast ink colors through the environment; Text.LineStyle
        // has no stroke-width API, so thickness comes from the stronger HC token hues.
        _ = highContrast
        string.underlineStyle = Text.LineStyle(pattern: pattern, color: color)
    }

    // MARK: - Colored-text fallback

    private static func applyColoredText(_ kind: Kind, to string: inout AttributedString) {
        string.underlineStyle = nil
        switch kind {
        case .person: string.foregroundColor = Color.ink.person
        case .place: string.foregroundColor = Color.ink.place
        case .other: string.foregroundColor = Color.ink.text
        case .unresolved: string.foregroundColor = Color.ink.secondaryText
        }
    }
}
