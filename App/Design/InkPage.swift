import SwiftUI

extension View {
    /// Page chrome: paper background and hidden list/scroll system fill.
    /// Screens adopt this in a later Stage 9 pass; defined here as the shared entry point.
    /// On a root page of the iPhone tab shell (``View/inkGlow()`` or
    /// ``inkRootPageNavigationTitle(_:)`` around it) the paper carries the dawn glow, which moves
    /// with the scrolled content.
    func inkPage() -> some View {
        modifier(InkPageBackground())
            .scrollContentBackground(.hidden)
            .inkPaperWindowToolbar()
    }

    /// Mac: the strip under the window toolbar is paper, like the page below it. Without this
    /// the system draws its own white (dark: gray) backdrop there, only as wide as the
    /// scrolled content.
    @ViewBuilder
    private func inkPaperWindowToolbar() -> some View {
        #if os(macOS)
            self
                .toolbarBackground(Color.ink.paper, for: .windowToolbar)
                .toolbarBackground(.visible, for: .windowToolbar)
        #else
            self
        #endif
    }

    /// Reading column: content is centered and at most ``InkSpacing/macPageWidth`` wide.
    /// Page-like screens (day, journal, entity, goal detail) use this on Mac and wide layouts;
    /// on a phone the limit is never reached, so it is safe to apply everywhere.
    func inkPageColumn() -> some View {
        self
            .frame(maxWidth: InkSpacing.macPageWidth, alignment: .leading)
            .frame(maxWidth: .infinity, alignment: .center)
    }

    /// Reading column for a `List` page (a `List` cannot hold the limit inside itself).
    /// On Mac the list fills its column and only its rows are held to
    /// ``InkSpacing/macPageWidth`` and centered; its scroll bar stays beside the rows. A
    /// `ScrollView` page puts ``inkPageColumn()`` on the stack inside it instead. On a phone
    /// this is ``inkPageColumn()``.
    func inkPageScrollColumn() -> some View {
        #if os(macOS)
            modifier(InkPageScrollColumn())
        #else
            inkPageColumn()
        #endif
    }

    /// System navigation title for back-history / Mac window title, without a visible bar title.
    /// Pair with ``InkPageTitleRow`` (List) or ``InkPageTitle`` (ScrollView / stack).
    /// ``InkPageTitle`` adds its own horizontal page margin; nesting it inside another
    /// horizontally padded container doubles the indent.
    ///
    /// In the iPhone tab shell a subpage's manşet (``InkPageHeader``) draws the back item
    /// itself, "‹ <parent page>", on a row above its title; the system bar is then hidden.
    func inkPageNavigationTitle(_ title: LocalizedStringKey) -> some View {
        inkPageNavigationTitle(title, isRoot: false)
    }

    func inkPageNavigationTitle(verbatim title: String) -> some View {
        inkPageNavigationTitle(verbatim: title, isRoot: false)
    }

    #if os(iOS)
        /// A sheet's first page: the title sits in the system bar as an inline large title, on
        /// one row with the sheet's words ("Kapat"); the manşet leaves it out (``PageHeadline``).
        func inkSheetBarNavigationTitle(_ title: LocalizedStringKey) -> some View {
            self
                .modifier(InkSubpageChrome(title: Text(title), isRoot: false))
                .navigationTitle(title)
                .toolbarTitleDisplayMode(.inlineLarge)
        }

        func inkSheetBarNavigationTitle(verbatim title: String) -> some View {
            self
                .modifier(InkSubpageChrome(title: Text(verbatim: title), isRoot: false))
                .navigationTitle(title)
                .toolbarTitleDisplayMode(.inlineLarge)
        }
    #endif

    fileprivate func inkPageNavigationTitle(_ title: LocalizedStringKey, isRoot: Bool) -> some View {
        self
            .modifier(InkSubpageChrome(title: Text(title), isRoot: isRoot))
            .navigationTitle(title)
            .inkPageHiddenBarTitle()
    }

    fileprivate func inkPageNavigationTitle(verbatim title: String, isRoot: Bool) -> some View {
        self
            .modifier(InkSubpageChrome(title: Text(verbatim: title), isRoot: isRoot))
            .navigationTitle(title)
            .inkPageHiddenBarTitle()
    }

    /// Root (tab) screen: the system navigation bar is hidden entirely in the iOS tab shell,
    /// so no bar title, no glass capsule; the page's icons live on the manşet row instead. The
    /// split shell keeps the empty bar for its sidebar button (`InkHiddenNavigationBar`). The title
    /// still feeds back-button history. Mac keeps the window title (same as
    /// ``inkPageNavigationTitle(_:)``).
    ///
    /// Subpages keep ``inkPageNavigationTitle(_:)``: the bar stays for the back button only,
    /// and their actions also go on the manşet row, not in `.toolbar`.
    func inkRootPageNavigationTitle(_ title: LocalizedStringKey) -> some View {
        self
            .environment(\.inkPageGlow, true)
            .inkPageNavigationTitle(title, isRoot: true)
            .inkHiddenNavigationBar()
    }

    func inkRootPageNavigationTitle(verbatim title: String) -> some View {
        self
            .environment(\.inkPageGlow, true)
            .inkPageNavigationTitle(verbatim: title, isRoot: true)
            .inkHiddenNavigationBar()
    }

    @ViewBuilder
    private func inkHiddenNavigationBar() -> some View {
        #if os(iOS)
            modifier(InkHiddenNavigationBar())
        #else
            self
        #endif
    }

    /// The split iOS shell keeps form width; short editors can fit their content vertically.
    /// Other sheets keep the common ideal height. Existing phone and Mac presenters stay as is;
    /// callers without phone detents pass `usesPhoneDetents: false`.
    func inkAdaptiveSheetPresentation(fitsContent: Bool = false, usesPhoneDetents: Bool = true) -> some View {
        modifier(InkAdaptiveSheetPresentation(usesPhoneDetents: usesPhoneDetents, fitsContent: fitsContent))
    }

    func inkAdaptiveFormPresentation() -> some View {
        modifier(InkAdaptiveSheetPresentation(usesPhoneDetents: false))
    }

    /// Pinned manşet strip above non-scrolling full-bleed content (e.g. Map), on every platform.
    /// Prefer ``InkPageTitle`` inside a `ScrollView` / `List` whenever content scrolls (pinned
    /// on Mac through ``View/inkPinnedMasthead(_:spacing:columnWidth:)``).
    /// ``InkPageTitle`` adds its own horizontal page margin; nesting it inside another
    /// horizontally padded container doubles the indent.
    func inkPinnedPageTitle(_ title: LocalizedStringKey, byline: String? = nil) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            InkPageTitle(title, byline: byline)
                // A strip over full-bleed content: opaque paper up under the status bar.
                .background(Color.ink.paper.ignoresSafeArea(edges: .top))
            self
        }
        .inkPageNavigationTitle(title)
    }

    func inkPinnedPageTitle(verbatim title: String, byline: String? = nil) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            InkPageTitle(verbatim: title, byline: byline)
                // A strip over full-bleed content: opaque paper up under the status bar.
                .background(Color.ink.paper.ignoresSafeArea(edges: .top))
            self
        }
        .inkPageNavigationTitle(verbatim: title)
    }

    @ViewBuilder
    private func inkPageHiddenBarTitle() -> some View {
        #if os(iOS)
            modifier(InkHiddenBarTitle())
        #else
            self
        #endif
    }
}

#if os(iOS)
    /// The bar shows no title: the manşet carries it. A sheet's first page is the exception: its
    /// title is the bar's inline large title, on one row with "Kapat" (``InkSheetChrome``).
    private struct InkHiddenBarTitle: ViewModifier {
        @Environment(\.inkSheetBarTitle) private var titleInBar

        @ViewBuilder func body(content: Content) -> some View {
            if titleInBar {
                content.toolbarTitleDisplayMode(.inlineLarge)
            } else {
                content
                    .navigationBarTitleDisplayMode(.inline)
                    .toolbar(removing: .title)
            }
        }
    }

    /// A root page's bar is hidden in the tab shell. The split shell (iPhone Duo inner screen)
    /// keeps it: the bar holds the button that brings the hidden sidebar back.
    private struct InkHiddenNavigationBar: ViewModifier {
        @Environment(\.shellKind) private var shellKind

        func body(content: Content) -> some View {
            content.toolbar(shellKind == .split ? .automatic : .hidden, for: .navigationBar)
        }
    }
#endif

#if os(macOS)
    private struct InkPageScrollColumn: ViewModifier {
        @State private var width: CGFloat = 0

        func body(content: Content) -> some View {
            let side = max(0, (width - InkSpacing.macPageWidth) / 2)
            // Safe-area padding, not content margins: a Mac `List` ignores content margins.
            content
                .safeAreaPadding(.horizontal, side)
                .frame(maxWidth: .infinity)
                .onGeometryChange(for: CGFloat.self) {
                    $0.size.width
                } action: {
                    width = $0
                }
        }
    }
#endif

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

extension View {
    /// List row on paper: matching background, page margin insets, system separators hidden
    /// (section rules come from ``SectionHeader``).
    ///
    /// `columnSelected` is the Mac list-column and search-result selection, and on iOS the split
    /// shell's (iPhone Duo, iPad). `nil` stays paper (sheets, headers). Pass `true` / `false` on
    /// a column row; the value does not inherit into sheets. In the iPhone tab shell, `true`
    /// keeps the search result's accent wash.
    ///
    /// `cardSegment` puts the row in a section card drawn across rows (``InkCardSegment``): the
    /// card is the row's background, so the row keeps the insets and height of any list row.
    func inkListRow(columnSelected: Bool? = nil, cardSegment: InkCardSegment? = nil) -> some View {
        modifier(InkListRowModifier(columnSelected: columnSelected, cardSegment: cardSegment))
    }
}

extension View {
    /// A selectable column list (Günlük, Kişiler, Görevler) draws its own selection
    /// (``InkListSelectionBackground``). The system focus halo would frame the selected row edge
    /// to edge over it (iPad with a keyboard), so it is off on the Mac and in the split iOS
    /// shell; the selection itself still follows focus and the arrow keys (design.md kural 12).
    /// iPadOS draws the halo in the cell's tint, so the list's tint is clear there, as the
    /// sidebar's; ``View/inkListRow(columnSelected:cardSegment:)`` gives the row's content the
    /// accent back.
    func inkColumnListFocus() -> some View {
        modifier(InkColumnListFocus())
    }
}

private struct InkColumnListFocus: ViewModifier {
    #if os(iOS)
        @Environment(\.shellKind) private var shellKind
    #endif

    func body(content: Content) -> some View {
        #if os(iOS)
            if shellKind == .split {
                content.focusEffectDisabled().tint(Color.clear)
            } else {
                content
            }
        #else
            content.focusEffectDisabled()
        #endif
    }
}

/// The page list row's insets (``View/inkListRow(columnSelected:cardSegment:)``).
enum InkListRowInsets {
    static let vertical: CGFloat = 6
}

private struct InkListRowModifier: ViewModifier {
    var columnSelected: Bool? = nil
    var cardSegment: InkCardSegment? = nil
    #if os(iOS)
        @Environment(\.shellKind) private var shellKind
    #endif

    func body(content: Content) -> some View {
        row(content)
            .modifier(InkHiddenLinkIndicator())
            .listRowBackground(background)
            .listRowInsets(
                EdgeInsets(
                    top: InkListRowInsets.vertical, leading: InkSpacing.margin,
                    bottom: InkListRowInsets.vertical, trailing: InkSpacing.margin)
            )
            .listRowSeparator(.hidden)
    }

    /// A column row draws its own selection, so the system focus ring is turned off there.
    /// In the split iOS shell the pointer highlights the column row it is over (iPad).
    @ViewBuilder private func row(_ content: Content) -> some View {
        #if os(macOS)
            if columnSelected != nil {
                content.focusEffectDisabled()
            } else {
                content
            }
        #else
            if shellKind == .split, columnSelected != nil {
                // The column list's tint is clear (``View/inkColumnListFocus()``); the row's own
                // controls and links keep the accent.
                content.tint(Color.ink.accent).inkPointerHighlight()
            } else {
                content
            }
        #endif
    }

    @ViewBuilder private var background: some View {
        if let cardSegment {
            InkCardSegmentBackground(segment: cardSegment, isSelected: columnSelected == true)
        } else {
            plainBackground
        }
    }

    @ViewBuilder private var plainBackground: some View {
        #if os(macOS)
            if let columnSelected {
                InkListSelectionBackground(isSelected: columnSelected)
            } else {
                Color.ink.paper
            }
        #else
            if shellKind == .split, let columnSelected {
                // The split shell's list columns (iPhone Duo, iPad) select like the Mac's.
                InkListSelectionBackground(isSelected: columnSelected)
            } else if columnSelected == true {
                // Search marks the keyboard selection. Phone list columns pass false or nil.
                Color.ink.accent.opacity(0.12)
            } else {
                // Clear on the tab shell: the page's paper (and a root page's glow) shows through.
                InkListRowPaper()
            }
        #endif
    }
}

/// A page row draws its own "›" where it has one (``InkCard``, ``InkRows``); the chevron
/// `List` adds to a `NavigationLink` row would sit outside the card (Kişiler, Ayarlar).
private struct InkHiddenLinkIndicator: ViewModifier {
    func body(content: Content) -> some View {
        #if os(iOS)
            content.navigationLinkIndicatorVisibility(.hidden)
        #else
            content
        #endif
    }
}

/// The background of a plain page row (and the manşet row). On a root page of the iPhone tab
/// shell (``EnvironmentValues/inkPageGlow``) it is clear, so the glow is not covered row by row;
/// the page's own paper lies under the list. Elsewhere (subpages, sheets, split shell, Mac) it
/// stays paper, as before.
struct InkListRowPaper: View {
    @Environment(\.inkPageGlow) private var glow
    #if os(iOS)
        @Environment(\.shellKind) private var shellKind
    #endif

    var body: some View {
        #if os(iOS)
            if glow && shellKind == .tabs {
                Color.clear
            } else {
                Color.ink.paper
            }
        #else
            Color.ink.paper
        #endif
    }
}

extension View {
    /// List row background of a page row outside ``View/inkListRow(columnSelected:cardSegment:)``:
    /// clear on the iPhone tab shell (the glow shows), paper elsewhere.
    func inkListRowBackground() -> some View {
        listRowBackground(InkListRowPaper())
    }
}

private struct InkAdaptiveSheetPresentation: ViewModifier {
    @Environment(\.shellKind) private var shellKind
    var usesPhoneDetents = true
    var fitsContent = false

    @ViewBuilder func body(content: Content) -> some View {
        #if os(iOS)
            switch InkSheetSizing.resolve(
                shell: shellKind, fitsContent: fitsContent, usesPhoneDetents: usesPhoneDetents)
            {
            case .fittedForm:
                content
                    .frame(minWidth: InkSheetChrome.macMinWidth, idealWidth: InkSheetChrome.macIdealWidth)
                    .presentationSizing(.form.fitted(horizontal: false, vertical: true))
            case .form:
                content
                    .frame(
                        minWidth: InkSheetChrome.macMinWidth, idealWidth: InkSheetChrome.macIdealWidth,
                        minHeight: InkSheetChrome.macMinHeight, idealHeight: InkSheetChrome.macIdealHeight
                    )
            case .detents:
                content.presentationDetents([.medium, .large])
            case .plain:
                content
            }
        #else
            if usesPhoneDetents {
                content.presentationDetents([.medium, .large])
            } else {
                content
            }
        #endif
    }
}

/// The page's paper. In the iPhone tab shell, on a root page (``EnvironmentValues/inkPageGlow``),
/// the glow lies on the paper and follows the scroll view this is applied to. Elsewhere (Mac,
/// split shell, subpages, sheets) plain paper, as before.
private struct InkPageBackground: ViewModifier {
    @Environment(\.inkPageGlow) private var glow
    #if os(iOS)
        @Environment(\.shellKind) private var shellKind
    #endif
    @State private var shift: CGFloat = 0

    private var drawsGlow: Bool {
        #if os(iOS)
            glow && shellKind == .tabs
        #else
            false
        #endif
    }

    func body(content: Content) -> some View {
        if drawsGlow {
            content
                .background {
                    ZStack(alignment: .top) {
                        Color.ink.paper.ignoresSafeArea()
                        InkGlowLayer(shift: shift)
                    }
                }
                .modifier(InkGlowScrollTracking(shift: $shift))
        } else {
            content.background(Color.ink.paper.ignoresSafeArea())
        }
    }
}

extension EnvironmentValues {
    /// The title a page pushed from here shows on its back item (``InkPageHeader``). Each page
    /// title modifier sets its own; the tab shell sets the tab's name on the stack.
    @Entry var inkBackTitle: Text? = nil
    /// The back item this page's manşet draws: the parent's title on a subpage, nil on a root
    /// page and in a sheet's first page.
    @Entry var inkHeaderBackTitle: Text? = nil
    /// Inside a sheet (``InkSheetModifier``): pages keep the system back button there.
    @Entry var inkInSheet = false
    /// Set on a sheet's `NavigationStack` (Ayarlar). Pages pushed there take the stack's
    /// environment, not the first page's (``inkInSheet`` is false on them); they get an opaque
    /// paper bar (``SheetBarEdge``).
    @Entry var inkSheetStack = false
}

/// A manşet that drew its own back item (``InkPageHeader``) asks for the system bar to hide.
struct InkHeaderBackShownKey: PreferenceKey {
    static let defaultValue = false
    static func reduce(value: inout Bool, nextValue: () -> Bool) {
        value = value || nextValue()
    }
}

/// Subpage chrome of the iPhone tab shell: hands the parent's title to the manşet's back item,
/// its own title to the pages pushed from it, and hides the system bar once the manşet drew the
/// back item (latched: a manşet row scrolled out of a `List` does not bring the bar back). Root
/// pages and other shells keep the system behavior.
private struct InkSubpageChrome: ViewModifier {
    let title: Text
    let isRoot: Bool
    @Environment(\.inkBackTitle) private var parentTitle
    @Environment(\.inkInSheet) private var inSheet
    @Environment(\.inkSheetStack) private var inSheetStack
    @Environment(\.inkSheetBarTitle) private var titleInSheetBar
    #if os(iOS)
        @Environment(\.shellKind) private var shellKind
    #endif
    @State private var drawsOwnBack = false

    func body(content: Content) -> some View {
        content
            .environment(\.inkHeaderBackTitle, isRoot || inSheet ? nil : parentTitle)
            .environment(\.inkBackTitle, title)
            // A sheet's first page gives its title to the bar; pages pushed from it draw their own.
            .environment(\.inkSheetBarTitle, false)
            .environment(\.inkHeadlineTitleInBar, titleInSheetBar)
            .modifier(SubpageGlowReset(isRoot: isRoot))
            .onPreferenceChange(InkHeaderBackShownKey.self) { shown in
                if shown { drawsOwnBack = true }
            }
            .modifier(SubpageBarVisibility(isRoot: isRoot, hidesBar: hidesBar))
            .modifier(SheetBarEdge(pushedInSheet: inSheetStack && !inSheet && !isRoot))
    }

    private var hidesBar: Bool {
        #if os(iOS)
            !isRoot && shellKind == .tabs && drawsOwnBack
        #else
            false
        #endif
    }
}

/// A page pushed inside a sheet (``EnvironmentValues/inkSheetStack``) keeps the system bar and
/// its round back button. Content scrolled up goes under an opaque paper bar there, not visibly
/// under the button: the bar was clear and the title and rows read through the glass ("Hızlı giriş" as "zlı giriş"). At rest the bar is
/// the page's own paper, so nothing changes until the page scrolls. The sheet's first page (title
/// in the bar, "Kapat") keeps the system bar as it is.
private struct SheetBarEdge: ViewModifier {
    let pushedInSheet: Bool

    @ViewBuilder func body(content: Content) -> some View {
        #if os(iOS)
            if pushedInSheet {
                content
                    .toolbarBackground(Color.ink.paper, for: .navigationBar)
                    .toolbarBackgroundVisibility(.visible, for: .navigationBar)
            } else {
                content
            }
        #else
            content
        #endif
    }
}

/// A subpage never carries the root page's glow, even when it is pushed from inside one.
private struct SubpageGlowReset: ViewModifier {
    let isRoot: Bool

    @ViewBuilder func body(content: Content) -> some View {
        if isRoot {
            content
        } else {
            content.environment(\.inkPageGlow, false)
        }
    }
}

private struct SubpageBarVisibility: ViewModifier {
    let isRoot: Bool
    let hidesBar: Bool

    /// One view tree for both states: toggling the bar must not rebuild the page.
    @ViewBuilder func body(content: Content) -> some View {
        #if os(iOS)
            if isRoot {
                content
            } else {
                content.toolbar(hidesBar ? .hidden : .automatic, for: .navigationBar)
                    // A hidden bar stops UIKit's edge swipe back; the enabler keeps it.
                    .background { InkInteractivePopEnabler() }
            }
        #else
            content
        #endif
    }
}
