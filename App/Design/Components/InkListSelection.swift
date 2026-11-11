import SwiftUI

/// Mac list-column selection (`docs/design.md`), also the split shell's on iOS (iPhone Duo,
/// iPad). Görevler, Günlük, Kişiler, Hedefler and search results share one shape (Şafak
/// `c-mac` `.tm-sel`, `j-mac2` `.tn-sel`): the selected row on paper becomes a rounded
/// `surface` card with a short accent bar 4 pt inside its leading edge; the Mac card also
/// takes a 1 pt `line` edge. A row inside a section card (already `surface`) is marked with
/// an `accentSoft` fill instead. Text tokens stay readable on both fills. The iPhone tab
/// shell's rows do not opt in.
enum InkListSelectionChrome {
    /// The selected row on paper: a card.
    static let fill = InkPalette.Token.surface
    /// The selected row inside a section card, which is already `surface`.
    static let cardFill = InkPalette.Token.accentSoft
    static let mark = InkPalette.Token.accent
    /// The accent bar's width (`3px` in the drawing).
    static let markWidth: CGFloat = 3
    /// The bar sits this far inside the selected card's leading edge.
    static let markInset: CGFloat = 4
    /// The bar stops this far short of the card's top and bottom (12 px in the drawing).
    static let markVerticalInset: CGFloat = 12
    static let cornerRadius: CGFloat = InkSize.listSelectionCorner
    static let horizontalInset: CGFloat = InkSpacing.listSelectionHorizontal
    static let verticalInset: CGFloat = InkSpacing.listSelectionVertical

    static var fillColor: Color { Color(fill.assetName) }
    static var cardFillColor: Color { Color(cardFill.assetName) }
    static var markColor: Color { Color(mark.assetName) }

    /// Foreground tokens drawn on a selected row (body, meta, links, dates, errors).
    static let textTokens: [InkPalette.Token] = [
        .text, .secondaryText, .accent, .warning, .danger, .person, .place,
    ]
}

/// The selected row's shape: the fill, rounded, with the accent bar inside its leading edge.
struct InkListSelectionShape: View {
    var fill: Color = InkListSelectionChrome.fillColor
    /// The Mac card's 1 pt `line` edge (`j-mac2`); a fill inside a section card has none.
    var showsEdge = false

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: InkListSelectionChrome.cornerRadius, style: .continuous)
        shape.fill(fill)
            .overlay {
                if showsEdge {
                    shape.strokeBorder(Color.ink.line, lineWidth: 1)
                }
            }
            .overlay(alignment: .leading) {
                Capsule()
                    .fill(InkListSelectionChrome.markColor)
                    .frame(width: InkListSelectionChrome.markWidth)
                    .padding(.vertical, InkListSelectionChrome.markVerticalInset)
                    .padding(.leading, InkListSelectionChrome.markInset)
            }
            .padding(.horizontal, InkListSelectionChrome.horizontalInset)
            .padding(.vertical, InkListSelectionChrome.verticalInset)
    }
}

/// Paper when idle; a `surface` card with the leading accent bar when selected.
struct InkListSelectionBackground: View {
    var isSelected: Bool

    var body: some View {
        ZStack {
            Color.ink.paper
            if isSelected {
                #if os(macOS)
                    InkListSelectionShape(showsEdge: true)
                #else
                    InkListSelectionShape()
                #endif
            }
        }
        .accessibilityHidden(true)
    }
}

extension View {
    /// A column row that is itself a card (the Hedefler column): selected, the card keeps its
    /// `surface` and takes the selection's accent bar and a 1 pt `line` edge (`j-mac2` `.tn-sel`).
    /// Its list row passes `columnSelected: false`, so no second card is drawn behind it.
    func inkCardSelection(_ isSelected: Bool, cornerRadius: CGFloat = InkCorner.md) -> some View {
        overlay {
            if isSelected {
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .strokeBorder(Color.ink.line, lineWidth: 1)
                    .overlay(alignment: .leading) {
                        Capsule()
                            .fill(InkListSelectionChrome.markColor)
                            .frame(width: InkListSelectionChrome.markWidth)
                            .padding(.vertical, InkListSelectionChrome.markVerticalInset)
                            .padding(.leading, InkListSelectionChrome.markInset)
                    }
                    .accessibilityHidden(true)
            }
        }
    }
}
