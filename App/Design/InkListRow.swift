import SwiftUI

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

struct InkColumnListFocus: ViewModifier {
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

struct InkListRowModifier: ViewModifier {
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
struct InkHiddenLinkIndicator: ViewModifier {
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
