import SwiftUI

/// Pure layout choice for the quick-entry capsule (unit-tested).
enum QuickEntryCapsuleLayout: Equatable, Sendable {
    /// Mode words | time/field | send on one row.
    case singleRow
    /// Mode + send on the first row; field below (accessibility sizes only).
    case stacked

    /// Gap between kip words when 44 pt tap frames are not what separates them.
    /// iPhone uses this at accessibility sizes; Mac always does, because ``tapTarget()``
    /// does not grow the word there. At default iPhone type the 44 pt frames produce
    /// the same visual gap (about 12 pt between "Olay" and "Görev").
    static let visualWordGap: CGFloat = 12

    /// Extra space between the 44 pt frames on the single-row iPhone layout.
    /// The frames, not this number, are the visual gap.
    static let tapFrameGap: CGFloat = 2

    /// Height of the rule after the mode words on the single row.
    static let ruleHeight: CGFloat = 22

    static func resolve(dynamicTypeSize: DynamicTypeSize) -> Self {
        dynamicTypeSize.isAccessibilitySize ? .stacked : .singleRow
    }

    /// Whether the default-size capsule splits into two rows (mode words and time on top, field
    /// and send below). Only a compact-width iPhone does; a regular-width iPad and the Mac keep
    /// one row: Olay | Görev · time · field · send (drawing: iPad frame of `c-mac`, fark2 D7).
    static func usesTwoRows(layout: Self, isCompactWidth: Bool) -> Bool {
        layout == .singleRow && isCompactWidth
    }

    /// Whether the capsule's top row carries the recognized chips (names, task date). Only the
    /// two-row iPhone capsule does: a chip row above it would cover the page while the keyboard
    /// is up. Elsewhere the caller keeps the chips in their own row above the capsule.
    static func carriesChips(dynamicTypeSize: DynamicTypeSize, isCompactWidth: Bool) -> Bool {
        usesTwoRows(layout: resolve(dynamicTypeSize: dynamicTypeSize), isCompactWidth: isCompactWidth)
    }

    /// Stack spacing between the two kip words.
    static func stackSpacing(for layout: Self) -> CGFloat {
        #if os(macOS)
            return visualWordGap
        #else
            return layout == .stacked ? visualWordGap : tapFrameGap
        #endif
    }
}

/// Capsule chrome for the quick-entry bar: mode words, field slot, send.
/// Callers supply their own field; this view does not own text state.
///
/// iPhone (drawing: Bugün): two rows in a rounded card: the mode words, the `chips` strip (the
/// recognized names) and, at the trailing end, the `accessory` (the time chip, or the task date)
/// on top, the field and send below. iPad (regular width) and Mac keep one pill row; there a thin
/// rule follows the mode words and the accessory sits before the field. Only the two-row layout
/// draws `chips` (``QuickEntryCapsuleLayout/carriesChips(dynamicTypeSize:isCompactWidth:)``).
struct QuickEntryCapsule<Field: View, Accessory: View, Chips: View>: View {
    @Binding var mode: QuickEntryMode
    var canSubmit: Bool
    var onSubmit: () -> Void
    /// When false, mode words stay visible but do not change the mode (busy / writing).
    var isModeEnabled: Bool = true
    @ViewBuilder var field: () -> Field
    /// Top-row slot after the mode words (the time chip). Empty by default.
    @ViewBuilder var accessory: () -> Accessory
    /// Two-row top row only: a strip between the mode words and the accessory. Empty by default.
    @ViewBuilder var chips: () -> Chips

    init(
        mode: Binding<QuickEntryMode>, canSubmit: Bool, onSubmit: @escaping () -> Void,
        isModeEnabled: Bool = true, @ViewBuilder field: @escaping () -> Field,
        @ViewBuilder accessory: @escaping () -> Accessory, @ViewBuilder chips: @escaping () -> Chips
    ) {
        _mode = mode
        self.canSubmit = canSubmit
        self.onSubmit = onSubmit
        self.isModeEnabled = isModeEnabled
        self.field = field
        self.accessory = accessory
        self.chips = chips
    }

    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @Environment(\.locale) private var locale
    #if os(iOS)
        @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    #endif

    private var layout: QuickEntryCapsuleLayout {
        QuickEntryCapsuleLayout.resolve(dynamicTypeSize: dynamicTypeSize)
    }

    /// The iPhone draws the default text sizes on two rows; iPad and Mac keep one row.
    private var usesTwoRows: Bool {
        #if os(iOS)
            QuickEntryCapsuleLayout.usesTwoRows(
                layout: layout, isCompactWidth: horizontalSizeClass != .regular)
        #else
            false
        #endif
    }

    var body: some View {
        Group {
            if usesTwoRows {
                VStack(alignment: .leading, spacing: 0) {
                    // Drawing: mode words on the left, the time chip at the row's trailing end. The
                    // recognized chips scroll sideways between them, so the card keeps two rows.
                    HStack(alignment: .center, spacing: 6) {
                        modePicker
                        chips()
                        Spacer(minLength: 0)
                        accessory()
                    }
                    HStack(alignment: .center, spacing: 6) {
                        fieldSlot
                        sendButton
                    }
                }
                .padding(.leading, 6)
            } else {
                switch layout {
                case .singleRow:
                    HStack(alignment: .center, spacing: 6) {
                        modePicker
                        modeRule
                        accessory()
                        fieldSlot
                        sendButton
                    }
                case .stacked:
                    VStack(alignment: .leading, spacing: 8) {
                        HStack(alignment: .center, spacing: 6) {
                            modePicker
                            accessory()
                            Spacer(minLength: 0)
                            sendButton
                        }
                        fieldSlot
                    }
                }
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 4)
        // Padding sandwich (no strokeBorder): keeps mode-word frame metrics stable for Mac audits.
        .background { chromeFill(Color.ink.surface) }
        .padding(InkStroke.rule)
        .background { chromeFill(Color.ink.line) }
        // Flatten before the floating shadow so glyph layers are not duplicated for metrics.
        .compositingGroup()
        .inkFloatingShadow()
        // Chrome (mode words, send) caps at AX2; the field text still scales via the caller.
        .dynamicTypeSize(...DynamicTypeSize.accessibility2)
    }

    @ViewBuilder private func chromeFill(_ color: Color) -> some View {
        switch layout {
        case .singleRow where !usesTwoRows:
            Capsule().fill(color)
        case .singleRow, .stacked:
            RoundedRectangle(cornerRadius: InkSize.quickEntryCorner, style: .continuous)
                .fill(color)
        }
    }

    /// Thin vertical rule between the mode words and the rest of the single row (drawing).
    private var modeRule: some View {
        Rectangle()
            .fill(Color.ink.line)
            .frame(width: InkStroke.rule, height: QuickEntryCapsuleLayout.ruleHeight)
            .padding(.horizontal, 4)
            .accessibilityHidden(true)
    }

    private var modePicker: some View {
        // iPhone: the 44 pt tap frames space the words, until accessibility sizes outgrow them.
        // Mac: the tap target does not grow the word, so the stack spacing is the visual gap.
        HStack(spacing: QuickEntryCapsuleLayout.stackSpacing(for: layout)) {
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
            // Same word drawing as ``InkTabs`` (one tab family).
            Text(verbatim: title)
                .inkTabWord(isSelected: selected, size: .compact)
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
                // Drawing: a filled accent disc. Empty field: the soft accent disc with an accent
                // arrow (a token step, not opacity), so the state still reads.
                .foregroundStyle(canSubmit ? Color.ink.onAccent : Color.ink.accent)
                .frame(width: sendSide, height: sendSide)
                .background {
                    Circle()
                        .fill(canSubmit ? Color.ink.accent : Color.ink.accentSoft)
                        .inkGlowShadow()
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

extension QuickEntryCapsule where Chips == EmptyView {
    init(
        mode: Binding<QuickEntryMode>, canSubmit: Bool, onSubmit: @escaping () -> Void,
        isModeEnabled: Bool = true, @ViewBuilder field: @escaping () -> Field,
        @ViewBuilder accessory: @escaping () -> Accessory
    ) {
        self.init(
            mode: mode, canSubmit: canSubmit, onSubmit: onSubmit, isModeEnabled: isModeEnabled,
            field: field, accessory: accessory, chips: { EmptyView() })
    }
}

extension QuickEntryCapsule where Accessory == EmptyView, Chips == EmptyView {
    init(
        mode: Binding<QuickEntryMode>, canSubmit: Bool, onSubmit: @escaping () -> Void,
        isModeEnabled: Bool = true, @ViewBuilder field: @escaping () -> Field
    ) {
        self.init(
            mode: mode, canSubmit: canSubmit, onSubmit: onSubmit, isModeEnabled: isModeEnabled,
            field: field, accessory: { EmptyView() }, chips: { EmptyView() })
    }
}
