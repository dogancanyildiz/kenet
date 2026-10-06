import SwiftUI

extension QuickEntryMode {
    var titleKey: LocalizedStringKey { LocalizedStringKey(catalogKey) }
}

/// Capsule chrome for the quick-entry bar: mode words, field slot, send.
/// Callers supply their own field; this view does not own text state.
struct QuickEntryCapsule<Field: View>: View {
    @Binding var mode: QuickEntryMode
    var canSubmit: Bool
    var onSubmit: () -> Void
    @ViewBuilder var field: () -> Field

    var body: some View {
        ViewThatFits(in: .horizontal) {
            HStack(alignment: .center, spacing: 8) {
                modePicker
                fieldSlot
                sendButton
            }
            VStack(alignment: .leading, spacing: 8) {
                HStack(alignment: .center, spacing: 8) {
                    modePicker
                    Spacer(minLength: 0)
                    sendButton
                }
                fieldSlot
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        // Double opaque fill: paper then well — scroll content must not read through.
        .background {
            Capsule().fill(Color.ink.paper)
        }
        .background {
            Capsule().fill(Color.ink.well)
        }
        .overlay {
            Capsule().strokeBorder(Color.ink.control, lineWidth: InkStroke.control)
        }
        .compositingGroup()
    }

    private var modePicker: some View {
        HStack(spacing: 4) {
            ForEach(QuickEntryMode.allCases, id: \.self) { option in
                modeWord(option)
            }
        }
        .accessibilityElement(children: .contain)
    }

    private func modeWord(_ option: QuickEntryMode) -> some View {
        let selected = mode == option
        return Button {
            mode = option
        } label: {
            VStack(spacing: 2) {
                Text(option.titleKey)
                    .font(selected ? Font.ink.section : Font.ink.meta)
                    .fontWeight(selected ? .semibold : .regular)
                    .foregroundStyle(selected ? Color.ink.text : Color.ink.secondaryText)
                Capsule()
                    .fill(selected ? Color.ink.accent : Color.clear)
                    .frame(height: InkSize.modeUnderline)
            }
            .tapTarget()
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(selected ? [.isSelected] : [])
        .accessibilityAddTraits(.isButton)
    }

    private var fieldSlot: some View {
        field()
            .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var sendButton: some View {
        Button(action: onSubmit) {
            Image(systemName: "arrow.up")
                .font(.body.weight(.semibold))
                .foregroundStyle(canSubmit ? Color.ink.onAccent : Color.ink.secondaryText)
                .frame(width: InkSize.send, height: InkSize.send)
                .background {
                    Circle().fill(canSubmit ? Color.ink.accent : Color.ink.well)
                }
                .overlay {
                    if !canSubmit {
                        Circle().stroke(Color.ink.control, lineWidth: InkStroke.control)
                    }
                }
                .tapTarget()
        }
        .buttonStyle(.plain)
        .disabled(!canSubmit)
        .accessibilityLabel(Text("Gönder"))
        .accessibilityIdentifier("button.quickEntrySend")
    }
}
