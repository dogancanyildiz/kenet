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

    /// List row on paper: matching background, page margin insets, system separators hidden
    /// (section rules come from ``SectionHeader``).
    func inkListRow(isSelected: Bool = false) -> some View {
        modifier(InkListRowModifier(isSelected: isSelected))
    }
}

private struct InkListRowModifier: ViewModifier {
    var isSelected: Bool = false
    @ScaledMetric(relativeTo: .body) private var margin = InkSpacing.margin

    func body(content: Content) -> some View {
        content
            .listRowBackground(
                isSelected ? Color.ink.accent.opacity(0.12) : Color.ink.paper
            )
            .listRowInsets(
                EdgeInsets(top: 6, leading: margin, bottom: 6, trailing: margin)
            )
            .listRowSeparator(.hidden)
    }
}
