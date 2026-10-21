import SwiftUI

/// Mürekkep tokens for the widget (docs/design.md). The widget does not build the app's design
/// layer, so the colors are read by their asset names from the app's catalog, which the widget
/// target also compiles: one set of values, kept by `PaletteContrastTests`. No hex here.
enum WidgetTheme {
    static let paper = Color("InkPaper")
    static let text = Color("InkText")
    static let secondaryText = Color("InkSecondaryText")
    static let accent = Color("InkAccent")
    static let control = Color("InkControl")
    static let rule = Color("InkRule")

    /// Vault words (goal names): New York, rule 1.
    static var name: Font { .system(.subheadline, design: .serif) }
    /// Section title: SF Pro Semibold footnote, as `Font.ink.section`.
    static var section: Font { .system(.footnote, design: .default, weight: .semibold) }
    /// Meta and counters: SF Pro footnote, tabular digits.
    static var meta: Font { .footnote.monospacedDigit() }
}
