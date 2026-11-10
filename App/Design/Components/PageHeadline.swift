import SwiftUI

/// Page manşet: SF Pro Bold display title with an optional byline (jury condition 4).
struct PageHeadline: View {
    private enum Title {
        case verbatim(String)
        case key(LocalizedStringKey)
    }

    private let title: Title
    /// Shorter date (abbreviated month) tried when ``fitsOneLine`` and the full title is too wide.
    var shortTitle: String? = nil
    var byline: String? = nil
    /// Styled byline (bold count, warning carried-over part); wins over ``byline``.
    var bylineText: Text? = nil
    /// Keeps the title on one line by trying full → 85% → short → short shrinking (floor 75%).
    /// Accessibility sizes still wrap: shrinking there would defeat the larger text.
    var fitsOneLine = false
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @Environment(\.inkPageHeadlineIsSubpage) private var isSubpage
    @Environment(\.inkHeadlineTitleInBar) private var titleInBar

    init(
        title: String, shortTitle: String? = nil, byline: String? = nil, fitsOneLine: Bool = false
    ) {
        self.title = .verbatim(title)
        self.shortTitle = shortTitle
        self.byline = byline
        self.fitsOneLine = fitsOneLine
    }

    init(_ title: LocalizedStringKey, byline: String? = nil) {
        self.title = .key(title)
        self.byline = byline
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            // An iOS sheet's first page shows its title in the bar, beside "Kapat" (drawing).
            if !titleInBar {
                titleBlock
                    .foregroundStyle(.ink.text)
                    // Always speak the full form, even when a short title is on screen.
                    .accessibilityLabel(accessibilityTitle)
                    .accessibilityAddTraits(.isHeader)
            }
            if let shownByline {
                // A subpage's byline is one footnote line (drawing: varlık sayfası).
                shownByline
                    .font(isSubpage ? .ink.meta : .ink.pageByline)
                    .foregroundStyle(.ink.secondaryText)
                    .lineLimit(isSubpage ? 1 : nil)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .combine)
    }

    private var shownByline: Text? {
        if let bylineText { return bylineText }
        guard let byline, !byline.isEmpty else { return nil }
        return Text(verbatim: byline)
    }

    private var shrinksToFit: Bool { fitsOneLine && !dynamicTypeSize.isAccessibilitySize }

    private var accessibilityTitle: Text {
        switch title {
        case .verbatim(let text): Text(verbatim: text)
        case .key(let key): Text(key)
        }
    }

    @ViewBuilder private var titleBlock: some View {
        if shrinksToFit, case .verbatim(let full) = title {
            let short = shortTitle ?? full
            ViewThatFits(in: .horizontal) {
                // (a) full form, full size
                oneLine(full)
                    .fixedSize(horizontal: true, vertical: false)
                // (b) full form, at most 85%
                ScaledHeadlineLine(text: full, scale: 0.85, font: titleFont)
                // (c) short form, full size
                oneLine(short)
                    .fixedSize(horizontal: true, vertical: false)
                // (d) short form, shrink no lower than 75%
                oneLine(short)
                    .lineLimit(1)
                    .minimumScaleFactor(0.75)
            }
        } else {
            titleText
                .font(titleFont)
                .lineLimit(shrinksToFit ? 1 : nil)
                .minimumScaleFactor(shrinksToFit ? 0.75 : 1)
        }
    }

    /// A subpage title under its back item is one step smaller than a root page's manşet.
    private var titleFont: Font { isSubpage ? .ink.subpageTitle : .ink.display }

    private func oneLine(_ text: String) -> some View {
        Text(verbatim: text)
            .font(titleFont)
            .lineLimit(1)
    }

    @ViewBuilder private var titleText: some View {
        switch title {
        case .verbatim(let text):
            Text(verbatim: text)
        case .key(let key):
            Text(key)
        }
    }
}

/// Draws display text at a fixed scale and reports that scaled ideal width to ``ViewThatFits``.
private struct ScaledHeadlineLine: View {
    let text: String
    var scale: CGFloat
    var font: Font

    var body: some View {
        ScaledHeadlineLayout(scale: scale) {
            Text(verbatim: text)
                .font(font)
                .lineLimit(1)
                .fixedSize(horizontal: true, vertical: false)
        }
        .scaleEffect(scale, anchor: .topLeading)
    }
}

/// Layout size is the child's ideal size × ``scale`` so ``ViewThatFits`` rejects when even the
/// scaled line would overflow (unlike ``minimumScaleFactor``, which still claims to fit).
private struct ScaledHeadlineLayout: Layout {
    var scale: CGFloat

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        guard let child = subviews.first else { return .zero }
        let ideal = child.sizeThatFits(.unspecified)
        return CGSize(width: ideal.width * scale, height: ideal.height * scale)
    }

    func placeSubviews(
        in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()
    ) {
        guard let child = subviews.first else { return }
        let ideal = child.sizeThatFits(.unspecified)
        child.place(
            at: bounds.origin, anchor: .topLeading,
            proposal: ProposedViewSize(width: ideal.width, height: ideal.height))
    }
}

/// Pure fitting choice for unit tests (mirrors ``PageHeadline``'s ``ViewThatFits`` order).
enum PageHeadlineFitting {
    enum Candidate: Equatable, Sendable {
        case full
        case fullScaled
        case short
        case shortScaled
    }

    /// Scale floors match the view: full shrink stop at 85%, short at 75%.
    static let fullScaleFloor: CGFloat = 0.85
    static let shortScaleFloor: CGFloat = 0.75

    static func pick(fullWidth: CGFloat, shortWidth: CGFloat, available: CGFloat) -> Candidate {
        if fullWidth <= available { return .full }
        if fullWidth * fullScaleFloor <= available { return .fullScaled }
        if shortWidth <= available { return .short }
        return .shortScaled
    }
}

extension EnvironmentValues {
    /// Set by ``InkPageHeader`` when it draws a back item: the title below it is ``Font/InkFontTokens/subpageTitle``.
    @Entry var inkPageHeadlineIsSubpage = false
    /// Set by an iOS sheet (``InkSheetModifier``): the next page title inside it goes to the
    /// system bar as an inline large title. The first page chrome consumes it.
    @Entry var inkSheetBarTitle = false
    /// The manşet leaves its title out: the system bar shows it (a sheet's first page, iOS).
    @Entry var inkHeadlineTitleInBar = false
}
