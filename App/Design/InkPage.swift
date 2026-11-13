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
    /// Page-like screens (day, diary, entity, goal detail) use this on Mac and wide layouts;
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

    func inkPageNavigationTitle(_ title: LocalizedStringKey, isRoot: Bool) -> some View {
        self
            .modifier(InkSubpageChrome(title: Text(title), isRoot: isRoot))
            .navigationTitle(title)
            .inkPageHiddenBarTitle()
    }

    func inkPageNavigationTitle(verbatim title: String, isRoot: Bool) -> some View {
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
