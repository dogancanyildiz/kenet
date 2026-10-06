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
    /// When false, mode words stay visible but do not change the mode (busy / writing).
    var isModeEnabled: Bool = true
    @ViewBuilder var field: () -> Field

    @ScaledMetric(relativeTo: .body) private var sendSide = InkSize.send
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

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
        // Padding sandwich (no strokeBorder): avoids the 1.5 pt end-cap "bracket" on snapshots.
        .background(Capsule().fill(Color.ink.paper))
        .padding(InkStroke.control)
        .background(Capsule().fill(Color.ink.control))
        // Chrome (mode words, send) caps at AX2; the field text still scales via the caller.
        .dynamicTypeSize(...DynamicTypeSize.accessibility2)
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
            Text(option.titleKey)
                .font(selected ? Font.ink.section : Font.ink.meta)
                .fontWeight(selected ? .semibold : .regular)
                .foregroundStyle(selected ? Color.ink.text : Color.ink.secondaryText)
                .fixedSize()
                .overlay(alignment: .bottom) {
                    Capsule()
                        .fill(selected ? Color.ink.accent : Color.clear)
                        .frame(height: InkSize.modeUnderline)
                        .offset(y: 4)
                }
                .tapTarget()
        }
        .buttonStyle(.plain)
        .disabled(!isModeEnabled)
        .accessibilityAddTraits(selected ? [.isSelected] : [])
        .accessibilityAddTraits(.isButton)
    }

    private var fieldSlot: some View {
        field()
            .frame(maxWidth: .infinity, alignment: .leading)
            // Field content escapes the chrome Dynamic Type ceiling.
            .dynamicTypeSize(dynamicTypeSize)
    }

    private var sendButton: some View {
        Button(action: onSubmit) {
            Image(systemName: "arrow.up")
                .font(.body.weight(.semibold))
                .foregroundStyle(canSubmit ? Color.ink.onAccent : Color.ink.secondaryText)
                .frame(width: sendSide, height: sendSide)
                .background {
                    if canSubmit {
                        Circle().fill(Color.ink.accent)
                    } else {
                        ZStack {
                            Circle().fill(Color.ink.control)
                            Circle().inset(by: InkStroke.control).fill(Color.ink.well)
                        }
                    }
                }
                .frame(
                    minWidth: TapTarget.minimumLength, minHeight: TapTarget.minimumLength,
                    alignment: .center
                )
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(!canSubmit)
        .accessibilityLabel(Text("Gönder"))
        .accessibilityIdentifier("button.quickEntrySend")
    }
}
