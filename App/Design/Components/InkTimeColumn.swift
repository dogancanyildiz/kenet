import SwiftUI

/// A time in a row's leading column: one line at every text size and in every locale, never
/// wrapped and never truncated. The column is as wide as the widest time the locale writes
/// (a 12-hour time carries its day period) and never narrower than ``minWidth``, so the rows of
/// one list line up whatever their own time is. Up to ``minWidth`` it draws as a fixed column did.
struct InkTimeColumn: View {
    let text: String
    var font: Font = .ink.time
    /// The column's width while the time fits in it.
    var minWidth: CGFloat
    /// Where the time sits in a column wider than itself.
    var alignment: Alignment = .leading
    /// `false` sizes the column to its own text (a time on a line of its own).
    var reservesWidestTime = true

    @Environment(\.locale) private var locale

    var body: some View {
        ZStack(alignment: .trailing) {
            if reservesWidestTime {
                let samples = EventTimeFormat.widestSamples(locale: locale)
                label(samples.morning).hidden()
                label(samples.evening).hidden()
            }
            label(text)
                .foregroundStyle(Color.ink.secondaryText)
        }
        .frame(minWidth: minWidth, alignment: alignment)
    }

    private func label(_ string: String) -> some View {
        Text(verbatim: string)
            .font(font)
            .monospacedDigit()
            .lineLimit(1)
            .fixedSize()
    }
}

/// A time column beside its content, drawn by `HStack(alignment: .top)` itself; on a row proposed
/// narrower than ``stacksBelowWidth`` the time goes on a line of its own above the content, which
/// then has the row's whole width. The width decides inside one layout, so the content keeps its
/// identity when the row's width changes. Two subviews: the time column, the content.
struct InkTimeRowLayout: Layout {
    /// Between the column and the content.
    var gap: CGFloat
    /// Padding the time column carries above its time; a stacked row leaves it out.
    var timeTopInset: CGFloat = 0
    /// Between the time's line and the content when stacked.
    var stackedSpacing: CGFloat = 4
    /// The row stacks when proposed narrower than this; `nil` never stacks.
    var stacksBelowWidth: CGFloat?
    /// `false` leaves the time's line out of a stacked row (a row without a time).
    var showsStackedTime = true

    /// `HStackLayout` shows its `Layout` members only through `AnyLayout`.
    private var row: AnyLayout { AnyLayout(HStackLayout(alignment: .top, spacing: gap)) }

    func stacks(width: CGFloat?) -> Bool {
        guard let stacksBelowWidth, let width else { return false }
        return width < stacksBelowWidth
    }

    func makeCache(subviews: Subviews) -> AnyLayout.Cache {
        row.makeCache(subviews: subviews)
    }

    func updateCache(_ cache: inout AnyLayout.Cache, subviews: Subviews) {
        row.updateCache(&cache, subviews: subviews)
    }

    func spacing(subviews: Subviews, cache: inout AnyLayout.Cache) -> ViewSpacing {
        row.spacing(subviews: subviews, cache: &cache)
    }

    /// The stacked time's line: its height, less the padding it carries, and the gap under it.
    private func stackedTimeHeight(_ subviews: Subviews) -> CGFloat {
        guard showsStackedTime else { return 0 }
        return max(0, subviews[0].sizeThatFits(.unspecified).height - timeTopInset) + stackedSpacing
    }

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout AnyLayout.Cache) -> CGSize {
        guard subviews.count == 2, stacks(width: proposal.width) else {
            return row.sizeThatFits(proposal: proposal, subviews: subviews, cache: &cache)
        }
        let content = subviews[1].sizeThatFits(ProposedViewSize(width: proposal.width, height: nil))
        let timeWidth = showsStackedTime ? subviews[0].sizeThatFits(.unspecified).width : 0
        return CGSize(width: max(timeWidth, content.width), height: stackedTimeHeight(subviews) + content.height)
    }

    func placeSubviews(
        in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout AnyLayout.Cache
    ) {
        guard subviews.count == 2, stacks(width: proposal.width) else {
            row.placeSubviews(in: bounds, proposal: proposal, subviews: subviews, cache: &cache)
            return
        }
        // An unshown time is an empty one: it keeps a place and draws nothing.
        subviews[0].place(
            at: CGPoint(x: bounds.minX, y: bounds.minY - timeTopInset), anchor: .topLeading,
            proposal: .unspecified)
        subviews[1].place(
            at: CGPoint(x: bounds.minX, y: bounds.minY + stackedTimeHeight(subviews)), anchor: .topLeading,
            proposal: ProposedViewSize(width: bounds.width, height: nil))
    }
}
