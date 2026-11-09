import SwiftUI

extension Font {
    /// Şafak type roles. Semantic text styles only — no fixed point sizes.
    static let ink = InkFontTokens.self

    enum InkFontTokens {
        /// Flip to `.serif` to restore New York for vault content in one place.
        static let contentDesign: Font.Design = .default

        /// Page title (manşet): SF Pro Bold ≈ largeTitle (34).
        static var display: Font { .system(.largeTitle, design: .default, weight: .bold) }

        /// Day name / month: SF Pro Semibold ≈ title2 (22).
        static var dayName: Font { .system(.title2, design: .default, weight: .semibold) }

        /// Vault content: SF Pro Regular ≈ body (17). Serif returns via ``contentDesign``.
        static var content: Font { .system(.body, design: contentDesign) }

        /// Smaller vault content (day preview, compact quotes): same family ≈ footnote (13).
        static var contentSmall: Font { .system(.footnote, design: contentDesign) }

        /// Placeholder: content family, not italic ≈ body (17).
        static var placeholder: Font { .system(.body, design: contentDesign) }

        /// Byline / künye: SF Pro Medium ≈ title3 (20).
        static var byline: Font { .system(.title3, design: .default, weight: .medium) }

        /// Section title: SF Pro Semibold ≈ headline (17).
        static var section: Font { .system(.headline, design: .default, weight: .semibold) }

        /// Meta: SF Pro Regular ≈ footnote (13).
        static var meta: Font { .footnote }

        /// Value: SF Pro tabular ≈ body (17).
        static var value: Font { .body.monospacedDigit() }

        /// Time: SF Pro tabular ≈ subheadline (15).
        static var time: Font { .subheadline.monospacedDigit() }

        /// Week-strip weekday letter: SF Pro Medium ≈ caption1 (12).
        static var weekday: Font { .system(.caption, design: .default, weight: .medium) }

        /// Large number fallback when ``LargeNumberText`` is unavailable: SF Pro Light tabular ≈ largeTitle.
        /// Prefer ``LargeNumberText`` so the design target (48 pt) scales with Dynamic Type.
        static var largeNumber: Font {
            .system(.largeTitle, design: .default, weight: .light).monospacedDigit()
        }
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
