import SwiftUI

extension View {
    /// Page chrome: paper background and hidden list/scroll system fill.
    /// Screens adopt this in a later Stage 9 pass; defined here as the shared entry point.
    func inkPage() -> some View {
        self
            .background(Color.ink.paper.ignoresSafeArea())
            .scrollContentBackground(.hidden)
    }

    /// Reading column: content is centered and at most ``InkSpacing/macPageWidth`` wide.
    /// Page-like screens (day, journal, entity, goal detail) use this on Mac and wide layouts;
    /// on a phone the limit is never reached, so it is safe to apply everywhere.
    func inkPageColumn() -> some View {
        self
            .frame(maxWidth: InkSpacing.macPageWidth, alignment: .leading)
            .frame(maxWidth: .infinity, alignment: .center)
    }

    /// System navigation title for back-history / Mac window title, without a visible bar title.
    /// Pair with ``InkPageTitleRow`` (List) or ``InkPageTitle`` (ScrollView / stack).
    func inkPageNavigationTitle(_ title: LocalizedStringKey) -> some View {
        self
            .navigationTitle(title)
            .inkPageHiddenBarTitle()
    }

    func inkPageNavigationTitle(verbatim title: String) -> some View {
        self
            .navigationTitle(title)
            .inkPageHiddenBarTitle()
    }

    /// Pinned manşet strip above non-scrolling full-bleed content (e.g. Map).
    /// Prefer ``InkPageTitle`` inside a `ScrollView` / `List` whenever content scrolls.
    func inkPinnedPageTitle(_ title: LocalizedStringKey, byline: String? = nil) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            InkPageTitle(title, byline: byline)
            self
        }
        .inkPageNavigationTitle(title)
    }

    func inkPinnedPageTitle(verbatim title: String, byline: String? = nil) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            InkPageTitle(verbatim: title, byline: byline)
            self
        }
        .inkPageNavigationTitle(verbatim: title)
    }

    @ViewBuilder
    private func inkPageHiddenBarTitle() -> some View {
        #if os(iOS)
            self
                .navigationBarTitleDisplayMode(.inline)
                .toolbar(removing: .title)
        #else
            self
        #endif
    }
}

/// How a screen attaches the serif page manşet. Pure cases for unit tests and call-site docs.
enum InkPageTitlePlacement: Equatable, Sendable {
    /// First `List` row via ``InkPageTitleRow``; navigation chrome via ``inkPageNavigationTitle``.
    case listRow
    /// First child inside a `ScrollView` / stack via ``InkPageTitle`` (scrolls with content).
    case scrollContent
    /// Fixed strip above non-scrolling content via ``inkPinnedPageTitle``.
    case pinned
}

/// Resolves placement → which view/modifier to use (no SwiftUI types; unit-tested).
enum InkPageTitleAttachment: Equatable, Sendable {
    /// Insert ``InkPageTitleRow`` as the first list row; call ``inkPageNavigationTitle``.
    case listRowAndNavigationTitle
    /// Insert ``InkPageTitle`` as the first scrolled child; call ``inkPageNavigationTitle``.
    case scrollLeadingAndNavigationTitle
    /// Wrap with ``inkPinnedPageTitle`` (strip + navigation title).
    case pinnedStripAndNavigationTitle

    static func resolve(_ placement: InkPageTitlePlacement) -> Self {
        switch placement {
        case .listRow: .listRowAndNavigationTitle
        case .scrollContent: .scrollLeadingAndNavigationTitle
        case .pinned: .pinnedStripAndNavigationTitle
        }
    }
}

/// Serif page manşet for `ScrollView` / stack content. Place as the **first** scrolled child
/// so it scrolls away with the page (not a sticky wrapper).
///
/// - List screens: use ``InkPageTitleRow`` instead.
/// - Non-scrolling full-bleed (Map): use ``inkPinnedPageTitle``.
struct InkPageTitle: View {
    private enum Title {
        case key(LocalizedStringKey)
        case verbatim(String)
    }

    private let title: Title
    var byline: String? = nil

    init(_ title: LocalizedStringKey, byline: String? = nil) {
        self.title = .key(title)
        self.byline = byline
    }

    init(verbatim title: String, byline: String? = nil) {
        self.title = .verbatim(title)
        self.byline = byline
    }

    var body: some View {
        Group {
            switch title {
            case .key(let key):
                PageHeadline(key, byline: byline)
            case .verbatim(let text):
                PageHeadline(title: text, byline: byline)
            }
        }
        .padding(.horizontal, InkSpacing.margin)
        .padding(.top, 4)
        .padding(.bottom, 8)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.ink.paper)
    }
}

/// First `List` row for a serif page manşet: no separator, paper background, page margins.
struct InkPageTitleRow: View {
    private enum Title {
        case key(LocalizedStringKey)
        case verbatim(String)
    }

    private let title: Title
    var byline: String? = nil

    init(_ title: LocalizedStringKey, byline: String? = nil) {
        self.title = .key(title)
        self.byline = byline
    }

    init(verbatim title: String, byline: String? = nil) {
        self.title = .verbatim(title)
        self.byline = byline
    }

    var body: some View {
        Group {
            switch title {
            case .key(let key):
                PageHeadline(key, byline: byline)
            case .verbatim(let text):
                PageHeadline(title: text, byline: byline)
            }
        }
        .listRowInsets(
            EdgeInsets(top: 8, leading: InkSpacing.margin, bottom: 4, trailing: InkSpacing.margin)
        )
        .listRowSeparator(.hidden)
        .listRowBackground(Color.ink.paper)
    }
}
