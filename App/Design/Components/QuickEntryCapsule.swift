import SwiftUI

/// Pure layout choice for the quick-entry capsule (unit-tested).
enum QuickEntryCapsuleLayout: Equatable, Sendable {
    /// Mode words | time/field | send on one row.
    case singleRow
    /// Mode + send on the first row; field below (accessibility sizes only).
    case stacked

    static func resolve(dynamicTypeSize: DynamicTypeSize) -> Self {
        dynamicTypeSize.isAccessibilitySize ? .stacked : .singleRow
    }
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

    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @Environment(\.locale) private var locale

    private var layout: QuickEntryCapsuleLayout {
        QuickEntryCapsuleLayout.resolve(dynamicTypeSize: dynamicTypeSize)
    }

    var body: some View {
        Group {
            switch layout {
            case .singleRow:
                HStack(alignment: .center, spacing: 6) {
                    modePicker
                    fieldSlot
                    sendButton
                }
            case .stacked:
                VStack(alignment: .leading, spacing: 8) {
                    HStack(alignment: .center, spacing: 6) {
                        modePicker
                        Spacer(minLength: 0)
                        sendButton
                    }
                    fieldSlot
                }
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 4)
        // Padding sandwich (no strokeBorder): avoids the 1.5 pt end-cap "bracket" on snapshots.
        .background { chromeFill(Color.ink.paper) }
        .padding(InkStroke.control)
        .background { chromeFill(Color.ink.control) }
        // Chrome (mode words, send) caps at AX2; the field text still scales via the caller.
        .dynamicTypeSize(...DynamicTypeSize.accessibility2)
    }

    @ViewBuilder private func chromeFill(_ color: Color) -> some View {
        switch layout {
        case .singleRow:
            Capsule().fill(color)
        case .stacked:
            RoundedRectangle(cornerRadius: InkSize.quickEntryCorner, style: .continuous)
                .fill(color)
        }
    }

    private var modePicker: some View {
        HStack(spacing: 2) {
            ForEach(QuickEntryMode.allCases, id: \.self) { option in
                modeWord(option)
            }
        }
        .accessibilityElement(children: .contain)
    }

    private func modeWord(_ option: QuickEntryMode) -> some View {
        let selected = mode == option
        let title = String(
            localized: String.LocalizationValue(option.catalogKey),
            bundle: PresentationLocalization.bundle(locale), locale: locale)
        return Button {
            mode = option
        } label: {
            Text(verbatim: title)
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
        // ScaledMetric must live under the AX2 ceiling (separate subview).
        QuickEntrySendButton(canSubmit: canSubmit, onSubmit: onSubmit)
    }
}

/// Send control sized from the capped Dynamic Type environment.
private struct QuickEntrySendButton: View {
    var canSubmit: Bool
    var onSubmit: () -> Void
    @ScaledMetric(relativeTo: .body) private var sendSide = InkSize.send
    @Environment(\.locale) private var locale

    var body: some View {
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
        .accessibilityLabel(
            Text(
                verbatim: String(
                    localized: "Gönder", bundle: PresentationLocalization.bundle(locale),
                    locale: locale))
        )
        .accessibilityIdentifier("button.quickEntrySend")
    }
}

/// Whether mode words accept taps (busy / writing locks the picker).
enum QuickEntryModeLock {
    static func isModeEnabled(
        isEnabled: Bool, isSubmitting: Bool, isCreating: Bool, isWriting: Bool
    ) -> Bool {
        isEnabled && !isSubmitting && !isCreating && !isWriting
    }
}
