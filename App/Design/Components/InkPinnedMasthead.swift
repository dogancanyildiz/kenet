import SwiftUI

/// Where a page's manşet row sits relative to the content that scrolls (unit-tested).
///
/// A page defines its manşet once and hands the same value to two places: the slot in its
/// scrolled content (``InkScrolledMasthead``) and the pinned strip above it
/// (``SwiftUI/View/inkPinnedMasthead(_:spacing:columnWidth:)``). The placement decides which of
/// the two draws it.
enum InkMastheadPlacement: Equatable, Sendable {
    /// First child of the scrolled content: the manşet scrolls away with the page (iPhone, iPad).
    case scrolled
    /// Above the scrolled content, which slides under it (Mac). The window toolbar there is
    /// opaque paper; a manşet that scrolled under it took the page's icons out of reach.
    case pinned

    /// The placement this platform draws.
    static var platform: Self {
        #if os(macOS)
            .pinned
        #else
            .scrolled
        #endif
    }
}

extension EnvironmentValues {
    /// ``InkMastheadPlacement/platform`` unless a test asks for the other placement.
    @Entry var inkMastheadPlacement: InkMastheadPlacement = .platform
}

/// Measures of the pinned manşet strip (unit-tested).
enum InkPinnedMastheadChrome {
    /// The rule under the pinned manşet shows once the content has moved under it: never on a
    /// page at rest, so an unscrolled page looks as it did with its manşet in the content.
    /// `offset` and `topInset` are the scroll view's content offset and top content inset (the
    /// strip itself is part of that inset); at rest the offset is minus the inset.
    static func showsRule(offset: CGFloat, topInset: CGFloat) -> Bool {
        offset + topInset > 0.5
    }
}

/// The manşet's slot in the scrolled content: draws `masthead` where the placement is
/// ``InkMastheadPlacement/scrolled`` and nothing where the page pins it above
/// (``SwiftUI/View/inkPinnedMasthead(_:spacing:columnWidth:)``, given the same value).
///
/// As the first row of a `List` an empty slot is no row at all.
struct InkScrolledMasthead<Masthead: View>: View {
    private let masthead: Masthead
    @Environment(\.inkMastheadPlacement) private var placement

    init(_ masthead: Masthead) {
        self.masthead = masthead
    }

    var body: some View {
        if placement == .scrolled {
            masthead
        }
    }
}

extension View {
    /// Pins a ``InkPageTitle`` above this `ScrollView` where the placement is pinned (Mac);
    /// elsewhere this does nothing and the page's ``InkScrolledMasthead`` draws it.
    ///
    /// - Parameters:
    ///   - spacing: the gap that followed the manşet in the scrolled stack, kept under the strip.
    ///   - columnWidth: the page's reading column; the manşet starts where the content does.
    func inkPinnedMasthead<Actions: View>(
        _ title: InkPageTitle<Actions>, spacing: CGFloat = 0,
        columnWidth: CGFloat = InkSpacing.macPageWidth
    ) -> some View {
        modifier(
            InkPinnedMastheadModifier(
                masthead: title.padding(.bottom, spacing), columnWidth: columnWidth))
    }

    /// Pins a ``InkPageTitleRow`` above this `List` (Mac), at the margins the row had as the
    /// list's first row.
    func inkPinnedMasthead<Actions: View>(
        _ row: InkPageTitleRow<Actions>, columnWidth: CGFloat = InkSpacing.macPageWidth
    ) -> some View {
        modifier(InkPinnedMastheadModifier(masthead: row.pinned, columnWidth: columnWidth))
    }

    /// Pins any other manşet block (Today's header in its padded stack, the Tasks page top);
    /// `insets` are the margins it had in the scrolled content.
    func inkPinnedMasthead<Masthead: View>(
        _ masthead: Masthead, insets: EdgeInsets, columnWidth: CGFloat = InkSpacing.macPageWidth
    ) -> some View {
        modifier(
            InkPinnedMastheadModifier(
                masthead: masthead.padding(insets).background(Color.ink.paper), columnWidth: columnWidth))
    }
}

/// The pinned strip: the manşet on paper over the content's top edge, a hairline under it while
/// the content is scrolled. Applied to the scroll view itself (not inside it), so its offset is
/// the one measured.
private struct InkPinnedMastheadModifier<Masthead: View>: ViewModifier {
    let masthead: Masthead
    let columnWidth: CGFloat
    @Environment(\.inkMastheadPlacement) private var placement
    @State private var isScrolled = false

    func body(content: Content) -> some View {
        if placement == .pinned {
            content
                .onScrollGeometryChange(for: Bool.self) { geometry in
                    InkPinnedMastheadChrome.showsRule(
                        offset: geometry.contentOffset.y, topInset: geometry.contentInsets.top)
                } action: { _, scrolled in
                    isScrolled = scrolled
                }
                .safeAreaInset(edge: .top, spacing: 0) {
                    masthead
                        .frame(maxWidth: columnWidth, alignment: .leading)
                        .frame(maxWidth: .infinity)
                        .background(Color.ink.paper)
                        .overlay(alignment: .bottom) {
                            if isScrolled { InkScrollEdgeLine() }
                        }
                        // A container of its own, as the list row was: a page identifier applied
                        // around the page (`screen.tasks`) does not replace its controls' own.
                        .accessibilityElement(children: .contain)
                }
        } else {
            content
        }
    }
}

extension View {
    /// A scroll view with no manşet above it (the Mac sidebar): the same hairline at the top of
    /// its visible area once its content has moved under the window toolbar, none at rest.
    /// Apply it to the scroll view itself.
    func inkScrollEdgeRule() -> some View {
        modifier(InkScrollEdgeRuleModifier())
    }
}

private struct InkScrollEdgeRuleModifier: ViewModifier {
    @State private var isScrolled = false
    @Environment(\.displayScale) private var displayScale

    func body(content: Content) -> some View {
        let line = InkStroke.hairline(scale: displayScale)
        content
            .onScrollGeometryChange(for: Bool.self) { geometry in
                InkPinnedMastheadChrome.showsRule(
                    offset: geometry.contentOffset.y, topInset: geometry.contentInsets.top)
            } action: { _, scrolled in
                isScrolled = scrolled
            }
            // The line sits at the top of the safe area (under the toolbar) over the list; its
            // own height is taken back by the spacing, so the rows do not move. An overlay on
            // the list is drawn under the sidebar's rows.
            .safeAreaInset(edge: .top, spacing: -line) {
                InkScrollEdgeLine()
                    .opacity(isScrolled ? 1 : 0)
            }
    }
}

/// The hairline between a fixed top edge and the content that has scrolled under it.
private struct InkScrollEdgeLine: View {
    @Environment(\.displayScale) private var displayScale

    var body: some View {
        Rectangle()
            .fill(Color.ink.rule)
            .frame(height: InkStroke.hairline(scale: displayScale))
            .accessibilityHidden(true)
    }
}
