import SwiftUI

#if canImport(UIKit)
    import UIKit
#endif

/// Keeps a wrapping text from breaking inside a word. A text wraps between words by itself; a
/// word wider than the line is cut mid-word or hyphenated ("hede- / flerini"), and
/// `minimumScaleFactor` does not help a text that may take more lines. This measures the text's
/// widest word in its system text style and returns the scale at which that word fits.
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

    /// What a text draws with: `base` while its widest word fits `available`, a smaller system
    /// font of the same weight otherwise. The Mac draws at the default size and keeps `base`.
    static func font(
        base: Font, text: String, style: InkWordFitStyle, size: DynamicTypeSize, available: CGFloat?
    ) -> Font {
        #if canImport(UIKit)
            guard let available else { return base }
            let width = widestWordWidth(in: text, style: style.textStyle, weight: style.platformWeight, size: size)
            let scale = scale(wordWidth: width, available: available)
            guard scale < 1 else { return base }
            let pointSize = platformFont(style.textStyle, weight: style.platformWeight, size: size).pointSize
            return .system(size: pointSize * scale, weight: style.weight)
        #else
            return base
        #endif
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

/// Reads the width a text is offered, for ``InkWordFit/font(base:text:style:size:available:)``.
/// The text's own width will not do: it is the width of its lines, and it follows the font this
/// reading sets. The reader lays its content out exactly as it would be laid out without it.
struct InkOfferedWidthReader: ViewModifier {
    var isActive: Bool
    @Binding var width: CGFloat?

    func body(content: Content) -> some View {
        let binding = $width
        let current = width
        let layout = InkOfferedWidthLayout(isActive: isActive) { offered in
            guard current.map({ abs($0 - offered) > 0.5 }) ?? true else { return }
            // Layout runs inside a view update; the state changes after it.
            Task { @MainActor in binding.wrappedValue = offered }
        }
        layout { content }
    }
}

/// Passes every proposal through to its one subview and reports the width it places it in.
private struct InkOfferedWidthLayout: Layout {
    var isActive: Bool
    var report: @Sendable (CGFloat) -> Void

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        subviews.first?.sizeThatFits(proposal) ?? .zero
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        subviews.first?.place(at: bounds.origin, anchor: .topLeading, proposal: proposal)
        if isActive, let width = proposal.width, width.isFinite, width > 0 { report(width) }
    }
}
