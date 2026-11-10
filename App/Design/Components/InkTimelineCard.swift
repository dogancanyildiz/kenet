import SwiftUI

/// Timeline / board card with a leading color bar. Color alone never carries meaning:
/// ``kindLabel`` is shown in a chip when provided.
struct InkTimelineCard: View {
    var title: String
    var meta: String? = nil
    /// Leading bar color (`person` / `place` / `accent` / project).
    var barColor: Color = Color.ink.accent
    /// Non-color meaning for the bar (shown as a chip).
    var kindLabel: String? = nil
    var isSelected: Bool = false
    var isCompleted: Bool = false
    /// Room kept free at the content's leading edge for a control the caller overlays there
    /// (the Mac Today grid's task box, placed with ``accessoryInset(padding:)``). With it the
    /// card leaves the done mark to that control.
    var leadingAccessoryWidth: CGFloat = 0

    @Environment(\.displayScale) private var displayScale
    @Environment(\.locale) private var locale
    @ScaledMetric(relativeTo: .body) private var padding = InkSpacing.cardPadding

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text(verbatim: title)
                    .font(.ink.content)
                    .foregroundStyle(isCompleted ? Color.ink.secondaryText : Color.ink.text)
                    .frame(maxWidth: .infinity, alignment: .leading)
                if isCompleted && leadingAccessoryWidth == 0 {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.body)
                        .foregroundStyle(Color.ink.secondaryText)
                        .accessibilityHidden(true)
                }
            }
            if let meta, !meta.isEmpty {
                Text(verbatim: meta)
                    .font(.ink.meta)
                    .foregroundStyle(Color.ink.secondaryText)
            }
            if let kindLabel, !kindLabel.isEmpty {
                TagChip(title: kindLabel, filled: true)
            }
        }
        .padding(.leading, leadingAccessoryWidth)
        .padding(padding)
        .padding(.leading, InkSize.timelineBar + 12)
        .background {
            RoundedRectangle(cornerRadius: InkCorner.card, style: .continuous)
                .fill(isSelected ? Color.ink.accentSoft : Color.ink.surface)
        }
        .background(alignment: .leading) {
            barColor
                .frame(width: InkSize.timelineBar)
                .frame(maxHeight: .infinity)
                .accessibilityHidden(true)
        }
        .clipShape(RoundedRectangle(cornerRadius: InkCorner.card, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: InkCorner.card, style: .continuous)
                .stroke(
                    isSelected ? Color.ink.line : Color.ink.rule,
                    lineWidth: InkStroke.hairline(scale: displayScale))
        }
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(isSelected ? [.isSelected] : [])
        .accessibilityValue(Text(verbatim: completedAccessibilityValue))
    }

    /// Where an overlaid leading control's top-leading corner sits, for the card's scaled
    /// `padding` (``InkSpacing/cardPadding`` scaled relative to `.body`).
    static func accessoryInset(padding: CGFloat) -> EdgeInsets {
        EdgeInsets(top: padding, leading: InkSize.timelineBar + 12 + padding, bottom: 0, trailing: 0)
    }

    private var completedAccessibilityValue: String {
        guard isCompleted else { return "" }
        return String(
            localized: "Tamamlandı", bundle: PresentationLocalization.bundle(locale),
            locale: locale)
    }
}
