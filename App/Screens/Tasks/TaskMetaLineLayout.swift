import SwiftUI

/// A task row's meta line: one row while everything fits, otherwise the parts flow onto the
/// next line whole. A plain `HStack` shared a short width out among the parts instead, so
/// each part broke mid-word ("No proje / ct" at xxxL on a 320 pt screen).
///
/// The parts are the same views in either arrangement, so growing text never swaps one view
/// for another (the accessibility audit reads such a swap as clipped text).
struct TaskMetaLineLayout: Layout {
    var spacing: CGFloat = 8
    /// `false` keeps the single row whatever the width: its text gives way with "…" instead.
    var wraps = true

    /// `HStackLayout` keeps its `Layout` methods to itself; `AnyLayout` hands them on.
    private var row: AnyLayout { AnyLayout(HStackLayout(spacing: spacing)) }
    private var flow: InkFlowLayout { InkFlowLayout(spacing: spacing, lineSpacing: 2) }

    func makeCache(subviews: Subviews) -> AnyLayout.Cache {
        row.makeCache(subviews: subviews)
    }

    func updateCache(_ cache: inout AnyLayout.Cache, subviews: Subviews) {
        row.updateCache(&cache, subviews: subviews)
    }

    func sizeThatFits(
        proposal: ProposedViewSize, subviews: Subviews, cache: inout AnyLayout.Cache
    ) -> CGSize {
        if staysOnOneRow(width: proposal.width, subviews: subviews, cache: &cache) {
            return row.sizeThatFits(proposal: proposal, subviews: subviews, cache: &cache)
        }
        var none: Void = ()
        return flow.sizeThatFits(proposal: proposal, subviews: subviews, cache: &none)
    }

    func placeSubviews(
        in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout AnyLayout.Cache
    ) {
        if staysOnOneRow(width: bounds.width, subviews: subviews, cache: &cache) {
            row.placeSubviews(in: bounds, proposal: proposal, subviews: subviews, cache: &cache)
        } else {
            var none: Void = ()
            flow.placeSubviews(in: bounds, proposal: proposal, subviews: subviews, cache: &none)
        }
    }

    private func staysOnOneRow(
        width: CGFloat?, subviews: Subviews, cache: inout AnyLayout.Cache
    ) -> Bool {
        guard wraps, let width, width.isFinite else { return true }
        let ideal = row.sizeThatFits(proposal: .unspecified, subviews: subviews, cache: &cache)
        return Self.fitsOnOneRow(idealWidth: ideal.width, in: width)
    }

    /// Half a point of slack: the row's own width comes back rounded to the pixel.
    static func fitsOnOneRow(idealWidth: CGFloat, in width: CGFloat) -> Bool {
        idealWidth <= width + 0.5
    }
}
