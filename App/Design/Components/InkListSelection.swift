import SwiftUI

/// Mac list-column selection (`docs/design.md`).
/// Görevler, Günlük, Kişiler and Hedefler share one shape: a recessed (`well`) fill
/// with a leading accent rule, clipped to the row. Text tokens stay on `well`
/// so body contrast holds. iPhone rows do not opt in.
enum InkListSelectionChrome {
    static let fill = InkPalette.Token.well
    static let mark = InkPalette.Token.accent
    /// Same width as the selected-mode underline, on the row's leading edge.
    static let markWidth: CGFloat = InkSize.modeUnderline
    static let cornerRadius: CGFloat = 6
    static let horizontalInset: CGFloat = 4
    static let verticalInset: CGFloat = 2

    /// Foreground tokens drawn on a selected row (body, meta, links, dates, errors).
    static let textTokens: [InkPalette.Token] = [
        .text, .secondaryText, .accent, .warning, .danger, .person, .place,
    ]
}

private struct InkColumnRowSelectedKey: EnvironmentKey {
    static let defaultValue: Bool? = nil
}

extension EnvironmentValues {
    /// `nil` when the row is not a Mac list-column row.
    /// `true` / `false` opts ``inkListRow()`` into ``InkListSelectionBackground``.
    var inkColumnRowSelected: Bool? {
        get { self[InkColumnRowSelectedKey.self] }
        set { self[InkColumnRowSelectedKey.self] = newValue }
    }
}

extension View {
    /// Shared Mac list-column selection. No visual change on iPhone.
    ///
    /// Apply **after** ``inkListRow()`` so that modifier reads this environment and paints
    /// a single row background. Pair the list with `.listStyle(.plain)` so the system
    /// capsule does not draw over it.
    func inkColumnSelection(isSelected: Bool) -> some View {
        modifier(InkColumnSelectionModifier(isSelected: isSelected))
    }
}

private struct InkColumnSelectionModifier: ViewModifier {
    var isSelected: Bool

    @ViewBuilder func body(content: Content) -> some View {
        #if os(macOS)
            content
                .environment(\.inkColumnRowSelected, isSelected)
                .focusEffectDisabled()
        #else
            content
        #endif
    }
}

/// Paper when idle; recessed fill and a leading accent rule when selected.
struct InkListSelectionBackground: View {
    var isSelected: Bool

    var body: some View {
        ZStack {
            Color.ink.paper
            if isSelected {
                RoundedRectangle(cornerRadius: InkListSelectionChrome.cornerRadius, style: .continuous)
                    .fill(Color.ink.well)
                    .overlay(alignment: .leading) {
                        Rectangle()
                            .fill(Color.ink.accent)
                            .frame(width: InkListSelectionChrome.markWidth)
                    }
                    .clipShape(
                        RoundedRectangle(
                            cornerRadius: InkListSelectionChrome.cornerRadius, style: .continuous)
                    )
                    .padding(.horizontal, InkListSelectionChrome.horizontalInset)
                    .padding(.vertical, InkListSelectionChrome.verticalInset)
            }
        }
        .accessibilityHidden(true)
    }
}
