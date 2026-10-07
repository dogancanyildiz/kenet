import SwiftUI

/// Page manşet: New York Semibold display title with an optional byline (jury condition 4).
struct PageHeadline: View {
    private enum Title {
        case verbatim(String)
        case key(LocalizedStringKey)
    }

    private let title: Title
    /// Shorter date (abbreviated month) tried when ``fitsOneLine`` and the full title is too wide.
    var shortTitle: String? = nil
    var byline: String? = nil
    /// Keeps the title on one line by trying full → 85% → short → short shrinking (floor 75%).
    /// Accessibility sizes still wrap: shrinking there would defeat the larger text.
    var fitsOneLine = false
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

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
            titleBlock
                .foregroundStyle(.ink.text)
                // Always speak the full form, even when a short title is on screen.
                .accessibilityLabel(accessibilityTitle)
                .accessibilityAddTraits(.isHeader)
            if let byline, !byline.isEmpty {
                Text(verbatim: byline)
                    .font(.ink.byline)
                    .foregroundStyle(.ink.secondaryText)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .combine)
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
                ScaledHeadlineLine(text: full, scale: 0.85)
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
                .font(.ink.display)
                .lineLimit(shrinksToFit ? 1 : nil)
                .minimumScaleFactor(shrinksToFit ? 0.75 : 1)
        }
    }

    private func oneLine(_ text: String) -> some View {
        Text(verbatim: text)
            .font(.ink.display)
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

    var body: some View {
        ScaledHeadlineLayout(scale: scale) {
            Text(verbatim: text)
                .font(.ink.display)
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
