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

    @Environment(\.displayScale) private var displayScale
    @ScaledMetric(relativeTo: .body) private var padding = InkSpacing.cardPadding

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Capsule()
                .fill(barColor)
                .frame(width: InkSize.timelineBar)
                .frame(maxHeight: .infinity)
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 4) {
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Text(verbatim: title)
                        .font(.ink.content)
                        .foregroundStyle(isCompleted ? Color.ink.secondaryText : Color.ink.text)
                        .frame(maxWidth: .infinity, alignment: .leading)
                    if isCompleted {
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
        }
        .padding(padding)
        .background {
            RoundedRectangle(cornerRadius: InkCorner.card, style: .continuous)
                .fill(isSelected ? Color.ink.accentSoft : Color.ink.surface)
        }
        .overlay {
            RoundedRectangle(cornerRadius: InkCorner.card, style: .continuous)
                .stroke(
                    isSelected ? Color.ink.line : Color.ink.rule,
                    lineWidth: InkStroke.hairline(scale: displayScale))
        }
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(isSelected ? [.isSelected] : [])
        .accessibilityValue(
            Text(verbatim: [kindLabel, isCompleted ? String(localized: "Tamamlandı") : nil]
                .compactMap { $0 }.filter { !$0.isEmpty }.joined(separator: ", ")))
    }
}
