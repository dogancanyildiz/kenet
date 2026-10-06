import SwiftUI

/// Suggestion chip for tags, projects, or places.
/// Selection is never color-only: thicker stroke and a checkmark.
struct TagChip: View {
    var title: String
    var systemImage: String? = nil
    var isSelected: Bool = false
    var filled: Bool = false
    var onTap: (() -> Void)? = nil
    var onDismiss: (() -> Void)? = nil

    var body: some View {
        HStack(spacing: 6) {
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
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background {
            RoundedRectangle(cornerRadius: InkSize.chipCorner, style: .continuous)
                .fill(filled || isSelected ? Color.ink.well : Color.clear)
        }
        .overlay {
            RoundedRectangle(cornerRadius: InkSize.chipCorner, style: .continuous)
                .stroke(
                    isSelected ? Color.ink.accent : Color.ink.control,
                    lineWidth: isSelected ? InkStroke.highPriority : InkStroke.control)
        }
        .accessibilityElement(children: onDismiss == nil ? .combine : .contain)
        .accessibilityLabel(Text(verbatim: title))
        .accessibilityAddTraits(isSelected ? .isSelected : [])
        .accessibilityAddTraits(onTap == nil ? [] : .isButton)
    }

    @ViewBuilder private var labelContent: some View {
        let core = HStack(spacing: 6) {
            if let systemImage {
                Image(systemName: systemImage)
                    .font(.footnote)
                    .foregroundStyle(Color.ink.secondaryText)
            }
            Text(verbatim: title)
                .font(.ink.meta)
                .foregroundStyle(Color.ink.text)
                .lineLimit(1)
            if isSelected {
                Image(systemName: "checkmark")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(Color.ink.accent)
                    .accessibilityHidden(true)
            }
        }

        if let onTap {
            Button(action: onTap) {
                core
                    .contentShape(Rectangle())
                    .tapTarget()
            }
            .buttonStyle(.plain)
        } else {
            core
        }
    }
}
