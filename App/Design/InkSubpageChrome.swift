import SwiftUI

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
struct InkSubpageChrome: ViewModifier {
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
struct SheetBarEdge: ViewModifier {
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
struct SubpageGlowReset: ViewModifier {
    let isRoot: Bool

    @ViewBuilder func body(content: Content) -> some View {
        if isRoot {
            content
        } else {
            content.environment(\.inkPageGlow, false)
        }
    }
}

struct SubpageBarVisibility: ViewModifier {
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
