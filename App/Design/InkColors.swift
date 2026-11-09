import SwiftUI

extension Color {
    /// Şafak color tokens. Values live in `Assets.xcassets`; names match ``InkPalette/Token``.
    static let ink = InkColorTokens.self

    enum InkColorTokens {
        static let paper = Color("InkPaper")
        static let elevated = Color("InkElevated")
        static let surface = Color("InkSurface")
        static let well = Color("InkWell")
        static let rule = Color("InkRule")
        static let line = Color("InkLine")
        static let text = Color("InkText")
        static let secondaryText = Color("InkSecondaryText")
        static let tertiaryText = Color("InkTertiaryText")
        static let accent = Color("InkAccent")
        static let onAccent = Color("InkOnAccent")
        static let accentSoft = Color("InkAccentSoft")
        static let warning = Color("InkWarning")
        static let danger = Color("InkDanger")
        static let control = Color("InkControl")
        static let person = Color("InkPerson")
        static let place = Color("InkPlace")
    }
}

extension ShapeStyle where Self == Color {
    /// ShapeStyle shorthand for `Color.ink.*` (e.g. `.foregroundStyle(.ink.warning)`).
    static var ink: Color.InkColorTokens.Type { Color.ink }
}
