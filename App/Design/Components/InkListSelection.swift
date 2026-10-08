import SwiftUI

/// Mac list-column selection (`docs/design.md`).
/// Görevler, Günlük, Kişiler, Hedefler and search results share one shape: a recessed
/// (`well`) fill with a leading accent rule, clipped to the row. Text tokens stay on
/// `well` so body contrast holds. iPhone rows do not opt in.
enum InkListSelectionChrome {
    static let fill = InkPalette.Token.well
    static let mark = InkPalette.Token.accent
    /// Same width as the selected-mode underline, on the row's leading edge.
    static let markWidth: CGFloat = InkSize.modeUnderline
    static let cornerRadius: CGFloat = InkSize.listSelectionCorner
    static let horizontalInset: CGFloat = InkSpacing.listSelectionHorizontal
    static let verticalInset: CGFloat = InkSpacing.listSelectionVertical

    static var fillColor: Color { Color(fill.assetName) }
    static var markColor: Color { Color(mark.assetName) }

    /// Foreground tokens drawn on a selected row (body, meta, links, dates, errors).
    static let textTokens: [InkPalette.Token] = [
        .text, .secondaryText, .accent, .warning, .danger, .person, .place,
    ]
}

private struct InkColumnRowSelectedKey: EnvironmentKey {
    static let defaultValue: Bool? = nil
}

extension EnvironmentValues {
    /// Kept so a parent cannot style nested rows. ``inkListRow(columnSelected:)`` does not
    /// read this; it clears the value for its content (sheets, editors).
    var inkColumnRowSelected: Bool? {
        get { self[InkColumnRowSelectedKey.self] }
        set { self[InkColumnRowSelectedKey.self] = newValue }
    }
}

/// How many Mac rows in this subtree opted into the selected-column chrome.
struct InkColumnChromeCountKey: PreferenceKey {
    static let defaultValue = 0
    static func reduce(value: inout Int, nextValue: () -> Int) {
        value += nextValue()
    }
}

/// Paper when idle; recessed fill and a leading accent rule when selected.
struct InkListSelectionBackground: View {
    var isSelected: Bool

    var body: some View {
        ZStack {
            Color.ink.paper
            if isSelected {
                RoundedRectangle(cornerRadius: InkListSelectionChrome.cornerRadius, style: .continuous)
                    .fill(InkListSelectionChrome.fillColor)
                    .overlay(alignment: .leading) {
                        Rectangle()
                            .fill(InkListSelectionChrome.markColor)
                            .frame(width: InkListSelectionChrome.markWidth)
                    }
                    .clipShape(
                        RoundedRectangle(
                            cornerRadius: InkListSelectionChrome.cornerRadius, style: .continuous)
                    )
                    .padding(.horizontal, InkListSelectionChrome.horizontalInset)
                    .padding(.vertical, InkListSelectionChrome.verticalInset)
            }
        }
        .accessibilityHidden(true)
    }
}
