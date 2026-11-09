import SwiftUI

/// Şafak tokens for the widget (docs/design.md). The widget does not build the app's design
/// layer, so the colors are read by their asset names from the app's catalog, which the widget
/// target also compiles: one set of values, kept by `PaletteContrastTests`. No hex here.
enum WidgetTheme {
    static let paper = Color("InkPaper")
    static let surface = Color("InkSurface")
    static let elevated = Color("InkElevated")
    static let well = Color("InkWell")
    static let text = Color("InkText")
    static let secondaryText = Color("InkSecondaryText")
    static let accent = Color("InkAccent")
    static let accentSoft = Color("InkAccentSoft")
    static let onAccent = Color("InkOnAccent")
    static let control = Color("InkControl")
    static let rule = Color("InkRule")

    /// Goal names and primary widget labels: SF Pro subheadline.
    static var name: Font { .system(.subheadline, design: .default) }
    /// Section title: SF Pro Semibold footnote, as `Font.ink.section`.
    static var section: Font { .system(.footnote, design: .default, weight: .semibold) }
    /// Meta and counters: SF Pro footnote, tabular digits.
    static var meta: Font { .footnote.monospacedDigit() }
    /// Compact badge and caption text: SF Pro caption2, tabular digits.
    static var caption: Font { .caption2.monospacedDigit() }
}
