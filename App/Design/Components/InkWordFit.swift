import SwiftUI

#if canImport(UIKit)
    import UIKit
#endif

/// Keeps a wrapping text from breaking inside a word. A text wraps between words by itself; a
/// word wider than the line is cut mid-word or hyphenated ("hede- / flerini"), and
/// `minimumScaleFactor` does not help a text that may take more lines. This measures the text's
/// widest word in its system text style; ``InkWordFitModifier`` then draws the text smaller, in
/// one layout pass, until that word fits its line.
enum InkWordFit {
    /// The text never shrinks below this share of its size; a longer word then breaks.
    static let floor: CGFloat = 0.5
    /// Share of the measured width the word may take: keeps a rounding point off the edge.
    static let slack: CGFloat = 0.98

    /// The runs without whitespace: a text wraps between them.
    static func words(in text: String) -> [String] {
        text.split(omittingEmptySubsequences: true) { $0.isWhitespace }.map { String($0) }
    }

    /// The scale at which a word `wordWidth` points wide fits `available` points: 1 while it fits
    /// (and while the width is not known), never below ``floor``.
    static func scale(wordWidth: CGFloat, available: CGFloat?) -> CGFloat {
        guard let available, available > 0, wordWidth > available * slack else { return 1 }
        return max(floor, available * slack / wordWidth)
    }

    #if canImport(UIKit)
        /// The system font a text style draws with at a text size.
        static func platformFont(_ style: UIFont.TextStyle, weight: UIFont.Weight, size: DynamicTypeSize) -> UIFont {
            let traits = UITraitCollection(preferredContentSizeCategory: UIContentSizeCategory(size))
            let base = UIFont.preferredFont(forTextStyle: style, compatibleWith: traits)
            return .systemFont(ofSize: base.pointSize, weight: weight)
        }

        /// The width of the widest word of `text` in a text style at a text size. The widest is
        /// not the longest: "doküman" is wider than "arşivini".
        static func widestWordWidth(
            in text: String, style: UIFont.TextStyle, weight: UIFont.Weight, size: DynamicTypeSize
        ) -> CGFloat {
            let font = platformFont(style, weight: weight, size: size)
            let widths = words(in: text).map { ($0 as NSString).size(withAttributes: [.font: font]).width }
            return ceil(widths.max() ?? 0)
        }
    #endif

    /// The width of the widest word of `text`, for ``InkWordFitModifier``. 0 on the Mac, which
    /// draws at the default size: the text then keeps its size.
    static func wordWidth(in text: String, style: InkWordFitStyle, size: DynamicTypeSize) -> CGFloat {
        #if canImport(UIKit)
            widestWordWidth(in: text, style: style.textStyle, weight: style.platformWeight, size: size)
        #else
            0
        #endif
    }

    /// The coordinate space of a fitted text's box; the text reads the box's width from it.
    static let space = "inkWordFit"

    /// The scale a fitted text is drawn at: its box's width over its own. The layout made the box
    /// narrower than the text by exactly the scale it chose.
    static func drawnScale(own: CGFloat, box: CGFloat?) -> CGFloat {
        guard let box, own > 0, box > 0, box < own else { return 1 }
        return box / own
    }
}

/// The system text styles ``InkWordFit`` measures; each mirrors one `Font.ink` token.
enum InkWordFitStyle: Sendable {
    /// `Font.ink.content`.
    case content
    /// `Font.ink.sectionTitle`.
    case sectionTitle

    var weight: Font.Weight {
        switch self {
        case .content: .regular
        case .sectionTitle: .bold
        }
    }

    #if canImport(UIKit)
        var textStyle: UIFont.TextStyle {
            switch self {
            case .content: .body
            case .sectionTitle: .title3
            }
        }

        var platformWeight: UIFont.Weight {
            switch self {
            case .content: .regular
            case .sectionTitle: .bold
            }
        }
    #endif
}

/// Draws a wrapping text smaller when its widest word is wider than the line it is offered, so
/// the word stays whole. Everything is decided inside one layout pass: no state, no second frame.
/// The layout offers the text a line as wide as the word, and reports the text's size times the
/// scale; the text then draws itself at that scale. `wordWidth` 0 leaves the text as it is.
struct InkWordFitModifier: ViewModifier {
    /// The widest word at the text's full size (``InkWordFit/wordWidth(in:style:size:)``).
    var wordWidth: CGFloat

    func body(content: Content) -> some View {
        InkWordFitLayout(wordWidth: wordWidth) {
            content.visualEffect { view, proxy in
                view.scaleEffect(
                    InkWordFit.drawnScale(
                        own: proxy.size.width, box: proxy.bounds(of: .named(InkWordFit.space))?.width),
                    anchor: .topLeading)
            }
        }
        .coordinateSpace(.named(InkWordFit.space))
    }
}

/// One subview. While the widest word fits the offered width it passes every proposal through.
struct InkWordFitLayout: Layout {
    var wordWidth: CGFloat

    /// The scale for an offered width; 1 when the width is not a real one.
    func scale(width: CGFloat?) -> CGFloat {
        guard let width, width.isFinite, wordWidth > 0 else { return 1 }
        return InkWordFit.scale(wordWidth: wordWidth, available: width)
    }

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        guard let subview = subviews.first else { return .zero }
        let scale = scale(width: proposal.width)
        guard scale < 1, let width = proposal.width else { return subview.sizeThatFits(proposal) }
        let full = subview.sizeThatFits(ProposedViewSize(width: width / scale, height: nil))
        return CGSize(width: min(width, full.width * scale), height: full.height * scale)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        guard let subview = subviews.first else { return }
        let scale = scale(width: proposal.width)
        guard scale < 1, let width = proposal.width else {
            subview.place(at: bounds.origin, anchor: .topLeading, proposal: proposal)
            return
        }
        subview.place(
            at: bounds.origin, anchor: .topLeading, proposal: ProposedViewSize(width: width / scale, height: nil))
    }
}
