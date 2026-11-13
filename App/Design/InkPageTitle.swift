import SwiftUI

/// Serif page manşet for `ScrollView` / stack content. Place as the **first** scrolled child
/// so it scrolls away with the page (not a sticky wrapper). A page in a Mac window column
/// defines it once and hands it to ``InkScrolledMasthead`` (the slot in the content) and
/// ``View/inkPinnedMasthead(_:spacing:columnWidth:)`` (pinned above the content on Mac).
///
/// - List screens: use ``InkPageTitleRow`` instead.
/// - Non-scrolling full-bleed (Map): use ``inkPinnedPageTitle``.
/// - Adds its own horizontal page margin; do not nest inside another padded container
///   (there use ``InkPageHeader``).
/// - `actions`: the page's icons on the manşet row (``InkHeaderAction``, ``InkHeaderMenu``,
///   ``SearchButton``); at most ``InkHeaderActionChrome/maximumCount``, search last.
struct InkPageTitle<Actions: View>: View {
    private var header: InkPageHeader<Actions>

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
            .background(InkListRowPaper())
    }
}

extension InkPageTitle {
    /// A styled byline (bold count, warning carried-over part) in place of the plain one.
    func byline(_ text: Text) -> Self {
        var copy = self
        copy.header = header.byline(text)
        return copy
    }

    /// A small view beside the title (``InkPageHeader/titleAccessory(_:)``).
    func titleAccessory(_ view: some View) -> Self {
        var copy = self
        copy.header = header.titleAccessory(view)
        return copy
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
/// container doubles the indent. `actions` as in ``InkPageTitle``; pinned on Mac the same way
/// (``InkScrolledMasthead`` and ``View/inkPinnedMasthead(_:columnWidth:)``).
struct InkPageTitleRow<Actions: View>: View {
    private var header: InkPageHeader<Actions>
    private var hasByline = false
    @Environment(\.inkHeadlineTitleInBar) private var titleInBar

    init(
        _ title: LocalizedStringKey, byline: String? = nil, @ViewBuilder actions: () -> Actions
    ) {
        header = InkPageHeader(title, byline: byline, actions: actions)
        hasByline = byline != nil
    }

    init(
        verbatim title: String, shortTitle: String? = nil, byline: String? = nil,
        fitsOneLine: Bool = false, @ViewBuilder actions: () -> Actions
    ) {
        header = InkPageHeader(
            verbatim: title, shortTitle: shortTitle, byline: byline, fitsOneLine: fitsOneLine,
            actions: actions)
        hasByline = byline != nil
    }

    var body: some View {
        if titleInBar && !hasByline && Actions.self == EmptyView.self {
            // A read-only sheet's bar shows the title (iOS): no empty manşet row under it.
            EmptyView()
        } else {
            header
                .listRowInsets(Self.insets)
                .listRowSeparator(.hidden)
                .inkListRowBackground()
        }
    }

    private static var insets: EdgeInsets {
        EdgeInsets(top: 8, leading: InkSpacing.margin, bottom: 4, trailing: InkSpacing.margin)
    }

    /// The same manşet outside the list (``View/inkPinnedMasthead(_:columnWidth:)``): the row's
    /// insets plus the inset a Mac list gives its rows, so it starts where the rows below do,
    /// and the gap the list kept between its first two rows, so they do not move up.
    var pinned: some View {
        header
            .padding(Self.insets)
            .padding(.horizontal, MacListColumnChrome.rowInset)
            .padding(.bottom, MacListColumnChrome.rowGap)
            .background(Color.ink.paper)
    }
}

extension InkPageTitleRow {
    /// A styled byline (bold count, warning carried-over part) in place of the plain one.
    func byline(_ text: Text) -> Self {
        var copy = self
        copy.header = header.byline(text)
        copy.hasByline = true
        return copy
    }
}

extension InkPageTitleRow where Actions == EmptyView {
    init(_ title: LocalizedStringKey, byline: String? = nil) {
        header = InkPageHeader(title, byline: byline)
        hasByline = byline != nil
    }

    init(
        verbatim title: String, shortTitle: String? = nil, byline: String? = nil,
        fitsOneLine: Bool = false
    ) {
        header = InkPageHeader(
            verbatim: title, shortTitle: shortTitle, byline: byline, fitsOneLine: fitsOneLine)
        hasByline = byline != nil
    }
}
