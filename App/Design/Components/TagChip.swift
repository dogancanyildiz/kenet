import SwiftUI

/// Suggestion chip for tags, projects, or places: capsule on `well`.
/// Selection is never color-only: thicker stroke and a checkmark.
struct TagChip: View {
    var title: String
    var systemImage: String? = nil
    var isSelected: Bool = false
    var filled: Bool = false
    /// Trailing tabular count, read after the title (summary name chips).
    var count: Int? = nil
    var onTap: (() -> Void)? = nil
    var onDismiss: (() -> Void)? = nil
    /// Scope chip (Ara): selected is `accentSoft` with accent, bold text and no stroke; the
    /// checkmark shows only with "Renksiz ayırt et". Unselected is `well` with a thin rule.
    var accentSelection = false

    @Environment(\.accessibilityDifferentiateWithoutColor) private var differentiateWithoutColor
    @Environment(\.displayScale) private var displayScale

    private var showsCheckmark: Bool {
        isSelected && (!accentSelection || differentiateWithoutColor)
    }

    var body: some View {
        HStack(spacing: 2) {
            labelContent
            if let onDismiss {
                Button(action: onDismiss) {
                    Image(systemName: "xmark")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(Color.ink.secondaryText)
                        .tapTarget()
                }
                .buttonStyle(.plain)
                .accessibilityLabel(Text("Kapat"))
                // The 44 pt target overlaps the chip's edge; the capsule keeps its own height.
                .padding(.vertical, -TagChipChrome.targetOverhang)
            }
        }
        .accessibilityElement(children: onDismiss == nil ? .combine : .contain)
        .accessibilityLabel(Text(verbatim: count.map { title + ", " + $0.formatted() } ?? title))
        .accessibilityAddTraits(isSelected ? .isSelected : [])
        .accessibilityAddTraits(onTap == nil ? [] : .isButton)
    }

    /// The drawn chip: a thin capsule (≈ 30 pt at the default text size), whatever the tap
    /// target around it.
    private func capsule(_ content: some View) -> some View {
        content
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background {
                Capsule()
                    .fill(fill)
            }
            .overlay {
                if accentSelection {
                    Capsule()
                        .strokeBorder(
                            isSelected ? Color.clear : Color.ink.rule,
                            lineWidth: InkStroke.hairline(scale: displayScale))
                } else {
                    Capsule()
                        .stroke(
                            isSelected ? Color.ink.accent : Color.ink.control,
                            lineWidth: isSelected ? InkStroke.highPriority : InkStroke.control)
                }
            }
    }

    private var fill: Color {
        if accentSelection { return isSelected ? Color.ink.accentSoft : Color.ink.well }
        return filled || isSelected ? Color.ink.well : Color.clear
    }

    private var titleColor: Color {
        guard accentSelection else { return Color.ink.text }
        return isSelected ? Color.ink.accent : Color.ink.secondaryText
    }

    @ViewBuilder private var labelContent: some View {
        let core = HStack(spacing: 6) {
            if let systemImage {
                Image(systemName: systemImage)
                    .font(.footnote)
                    .foregroundStyle(Color.ink.secondaryText)
            }
            Text(verbatim: title)
                .font(.ink.meta.weight(accentSelection && isSelected ? .semibold : .regular))
                .foregroundStyle(titleColor)
                .lineLimit(1)
            if let count {
                Text(verbatim: count.formatted())
                    .font(.ink.meta)
                    .monospacedDigit()
                    .foregroundStyle(Color.ink.secondaryText)
            }
            if showsCheckmark {
                Image(systemName: "checkmark")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(Color.ink.accent)
                    .accessibilityHidden(true)
            }
        }

        if let onTap {
            Button(action: onTap) {
                // The capsule is drawn first; the 44 pt target is a clear frame around it.
                capsule(core)
                    .tapTarget()
            }
            .buttonStyle(.plain)
        } else {
            capsule(core)
        }
    }
}

enum TagChipChrome {
    /// How far a dismiss button's 44 pt target reaches past the chip's top and bottom edges.
    static let targetOverhang: CGFloat = 7
}
