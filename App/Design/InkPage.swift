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
    /// ``InkPageTitle`` adds its own horizontal page margin; nesting it inside another
    /// horizontally padded container doubles the indent.
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

    /// Root (tab) screen: the system navigation bar is hidden entirely on iOS, so no bar
    /// title, no glass capsule; the page's icons live on the manşet row instead. The title
    /// still feeds back-button history. Mac keeps the window title (same as
    /// ``inkPageNavigationTitle(_:)``).
    ///
    /// Subpages keep ``inkPageNavigationTitle(_:)``: the bar stays for the back button only,
    /// and their actions also go on the manşet row, not in `.toolbar`.
    func inkRootPageNavigationTitle(_ title: LocalizedStringKey) -> some View {
        self
            .inkPageNavigationTitle(title)
            .inkHiddenNavigationBar()
    }

    func inkRootPageNavigationTitle(verbatim title: String) -> some View {
        self
            .inkPageNavigationTitle(verbatim: title)
            .inkHiddenNavigationBar()
    }

    @ViewBuilder
    private func inkHiddenNavigationBar() -> some View {
        #if os(iOS)
            self.toolbar(.hidden, for: .navigationBar)
        #else
            self
        #endif
    }

    /// Pinned manşet strip above non-scrolling full-bleed content (e.g. Map).
    /// Prefer ``InkPageTitle`` inside a `ScrollView` / `List` whenever content scrolls.
    /// ``InkPageTitle`` adds its own horizontal page margin; nesting it inside another
    /// horizontally padded container doubles the indent.
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

/// Serif page manşet for `ScrollView` / stack content. Place as the **first** scrolled child
/// so it scrolls away with the page (not a sticky wrapper).
///
/// - List screens: use ``InkPageTitleRow`` instead.
/// - Non-scrolling full-bleed (Map): use ``inkPinnedPageTitle``.
/// - Adds its own horizontal page margin; do not nest inside another padded container
///   (there use ``InkPageHeader``).
/// - `actions`: the page's icons on the manşet row (``InkHeaderAction``, ``InkHeaderMenu``,
///   ``SearchButton``); at most ``InkHeaderActionChrome/maximumCount``, search last.
struct InkPageTitle<Actions: View>: View {
    private let header: InkPageHeader<Actions>

    init(
        _ title: LocalizedStringKey, byline: String? = nil, @ViewBuilder actions: () -> Actions
    ) {
        header = InkPageHeader(title, byline: byline, actions: actions)
    }

    init(
        verbatim title: String, shortTitle: String? = nil, byline: String? = nil,
        fitsOneLine: Bool = false, @ViewBuilder actions: () -> Actions
    ) {
        header = InkPageHeader(
            verbatim: title, shortTitle: shortTitle, byline: byline, fitsOneLine: fitsOneLine,
            actions: actions)
    }

    var body: some View {
        header
            .padding(.horizontal, InkSpacing.margin)
            .padding(.top, 4)
            .padding(.bottom, 8)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color.ink.paper)
    }
}

extension InkPageTitle where Actions == EmptyView {
    init(_ title: LocalizedStringKey, byline: String? = nil) {
        header = InkPageHeader(title, byline: byline)
    }

    init(
        verbatim title: String, shortTitle: String? = nil, byline: String? = nil,
        fitsOneLine: Bool = false
    ) {
        header = InkPageHeader(
            verbatim: title, shortTitle: shortTitle, byline: byline, fitsOneLine: fitsOneLine)
    }
}

/// First `List` row for a serif page manşet: no separator, paper background, page margins.
/// Applies leading/trailing insets itself; nesting inside another horizontally padded
/// container doubles the indent. `actions` as in ``InkPageTitle``.
struct InkPageTitleRow<Actions: View>: View {
    private let header: InkPageHeader<Actions>

    init(
        _ title: LocalizedStringKey, byline: String? = nil, @ViewBuilder actions: () -> Actions
    ) {
        header = InkPageHeader(title, byline: byline, actions: actions)
    }

    init(
        verbatim title: String, shortTitle: String? = nil, byline: String? = nil,
        fitsOneLine: Bool = false, @ViewBuilder actions: () -> Actions
    ) {
        header = InkPageHeader(
            verbatim: title, shortTitle: shortTitle, byline: byline, fitsOneLine: fitsOneLine,
            actions: actions)
    }

    var body: some View {
        header
            .listRowInsets(
                EdgeInsets(
                    top: 8, leading: InkSpacing.margin, bottom: 4, trailing: InkSpacing.margin)
            )
            .listRowSeparator(.hidden)
            .listRowBackground(Color.ink.paper)
    }
}

extension InkPageTitleRow where Actions == EmptyView {
    init(_ title: LocalizedStringKey, byline: String? = nil) {
        header = InkPageHeader(title, byline: byline)
    }

    init(
        verbatim title: String, shortTitle: String? = nil, byline: String? = nil,
        fitsOneLine: Bool = false
    ) {
        header = InkPageHeader(
            verbatim: title, shortTitle: shortTitle, byline: byline, fitsOneLine: fitsOneLine)
    }
}

extension View {
    /// List row on paper: matching background, page margin insets, system separators hidden
    /// (section rules come from ``SectionHeader``).
    func inkListRow(isSelected: Bool = false) -> some View {
        modifier(InkListRowModifier(isSelected: isSelected))
    }
}

private struct InkListRowModifier: ViewModifier {
    var isSelected: Bool = false
    @Environment(\.inkColumnRowSelected) private var columnSelected

    func body(content: Content) -> some View {
        content
            .listRowBackground(background)
            .listRowInsets(
                EdgeInsets(
                    top: 6, leading: InkSpacing.margin, bottom: 6, trailing: InkSpacing.margin)
            )
            .listRowSeparator(.hidden)
    }

    @ViewBuilder private var background: some View {
        if let columnSelected {
            InkListSelectionBackground(isSelected: columnSelected)
        } else if isSelected {
            Color.ink.accent.opacity(0.12)
        } else {
            Color.ink.paper
        }
    }
}
