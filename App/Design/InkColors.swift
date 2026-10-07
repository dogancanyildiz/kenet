import SwiftUI

extension Color {
    /// Mürekkep color tokens. Values live in `Assets.xcassets`; names match ``InkPalette/Token``.
    static let ink = InkColorTokens.self

    enum InkColorTokens {
        static let paper = Color("InkPaper")
        static let surface = Color("InkSurface")
        static let well = Color("InkWell")
        static let rule = Color("InkRule")
        static let text = Color("InkText")
        static let secondaryText = Color("InkSecondaryText")
        static let accent = Color("InkAccent")
        static let onAccent = Color("InkOnAccent")
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
