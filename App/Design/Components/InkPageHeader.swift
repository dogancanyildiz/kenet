import SwiftUI

/// Where the manşet-row icons sit relative to the manşet (unit-tested).
enum InkPageHeaderLayout: Equatable, Sendable {
    /// Manşet on the left, icons on the same row at its right.
    case inline
    /// Accessibility text sizes: icons on their own row above the manşet, right-aligned,
    /// so the 44 pt targets stay clear of the large title.
    case stacked

    static func resolve(dynamicTypeSize: DynamicTypeSize) -> Self {
        dynamicTypeSize.isAccessibilitySize ? .stacked : .inline
    }
}

/// Manşet row without page margins: ``PageHeadline`` plus the page's action icons on its right.
///
/// Use this only where the surrounding container already supplies the horizontal page margin
/// (Today's padded stack). Everywhere else use ``InkPageTitle`` (ScrollView / stack) or
/// ``InkPageTitleRow`` (List), which wrap this view and add the margins.
///
/// `actions` holds ``InkHeaderAction`` / ``InkHeaderMenu`` / ``SearchButton`` views, at most
/// ``InkHeaderActionChrome/maximumCount``; search goes last (rightmost).
/// With no actions the view draws exactly what ``PageHeadline`` draws.
struct InkPageHeader<Actions: View>: View {
    private enum Title {
        case key(LocalizedStringKey)
        case verbatim(String)
    }

    private let title: Title
    private let shortTitle: String?
    private let byline: String?
    private let fitsOneLine: Bool
    private let actions: Actions
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    init(
        _ title: LocalizedStringKey, byline: String? = nil, @ViewBuilder actions: () -> Actions
    ) {
        self.title = .key(title)
        self.shortTitle = nil
        self.byline = byline
        self.fitsOneLine = false
        self.actions = actions()
    }

    /// - Parameters:
    ///   - shortTitle: shorter form tried when `fitsOneLine` and the full title is too wide.
    ///   - fitsOneLine: keep the manşet on one line by shrinking (see ``PageHeadline``).
    init(
        verbatim title: String, shortTitle: String? = nil, byline: String? = nil,
        fitsOneLine: Bool = false, @ViewBuilder actions: () -> Actions
    ) {
        self.title = .verbatim(title)
        self.shortTitle = shortTitle
        self.byline = byline
        self.fitsOneLine = fitsOneLine
        self.actions = actions()
    }

    var body: some View {
        if Actions.self == EmptyView.self {
            headline
        } else {
            switch InkPageHeaderLayout.resolve(dynamicTypeSize: dynamicTypeSize) {
            case .inline:
                HStack(alignment: .firstTextBaseline, spacing: InkHeaderActionChrome.spacing) {
                    headline
                    actionGroup
                }
            case .stacked:
                VStack(alignment: .leading, spacing: InkSpacing.row) {
                    HStack(spacing: InkHeaderActionChrome.spacing) {
                        Spacer(minLength: 0)
                        actionGroup
                    }
                    headline
                }
            }
        }
    }

    private var actionGroup: some View {
        // Plain buttons in the slot (``SearchButton``) draw as utility icons; ``InkHeaderAction``
        // and ``InkHeaderMenu`` set their own style and are not affected.
        actions.buttonStyle(InkHeaderButtonStyle())
            .environment(\.isInkHeaderActionSlot, true)
    }

    @ViewBuilder private var headline: some View {
        switch title {
        case .key(let key):
            PageHeadline(key, byline: byline)
        case .verbatim(let text):
            PageHeadline(
                title: text, shortTitle: shortTitle, byline: byline, fitsOneLine: fitsOneLine)
        }
    }
}

extension InkPageHeader where Actions == EmptyView {
    init(_ title: LocalizedStringKey, byline: String? = nil) {
        self.init(title, byline: byline) { EmptyView() }
    }

    init(
        verbatim title: String, shortTitle: String? = nil, byline: String? = nil,
        fitsOneLine: Bool = false
    ) {
        self.init(
            verbatim: title, shortTitle: shortTitle, byline: byline, fitsOneLine: fitsOneLine
        ) { EmptyView() }
    }
}
