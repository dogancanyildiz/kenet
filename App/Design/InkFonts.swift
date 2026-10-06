import SwiftUI

extension Font {
    /// Mürekkep type roles. Semantic text styles only — no fixed point sizes.
    static let ink = InkFontTokens.self

    enum InkFontTokens {
        /// Page title (manşet): New York Semibold ≈ largeTitle (34).
        static var display: Font { .system(.largeTitle, design: .serif, weight: .semibold) }

        /// Vault content: New York Regular ≈ body (17).
        static var content: Font { .system(.body, design: .serif) }

        /// Placeholder: New York Italic ≈ body (17).
        static var placeholder: Font { .system(.body, design: .serif).italic() }

        /// Byline / künye: SF Pro Regular ≈ subheadline (15).
        static var byline: Font { .subheadline }

        /// Section title: SF Pro Semibold ≈ footnote (13).
        static var section: Font { .system(.footnote, design: .default, weight: .semibold) }

        /// Meta: SF Pro Regular ≈ footnote (13).
        static var meta: Font { .footnote }

        /// Value: SF Pro tabular ≈ body (17).
        static var value: Font { .body.monospacedDigit() }

        /// Time: SF Pro tabular ≈ subheadline (15).
        static var time: Font { .subheadline.monospacedDigit() }

        /// Large number: SF Pro Light tabular ≈ largeTitle (34; design table lists 48).
        static var largeNumber: Font { .system(.largeTitle, design: .default, weight: .light).monospacedDigit() }
    }
}

extension View {
    /// Journal paragraph leading: design targets 26 pt line height at default body (17).
    func inkJournalParagraph() -> some View {
        modifier(InkJournalParagraphModifier())
    }
}

private struct InkJournalParagraphModifier: ViewModifier {
    /// Extra space beyond the font's built-in leading (26 − 17 at default size).
    @ScaledMetric(relativeTo: .body) private var extraLeading = 9

    func body(content: Content) -> some View {
        content.lineSpacing(extraLeading)
    }
}
