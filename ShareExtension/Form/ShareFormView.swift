#if os(iOS)
    import SwiftUI

    /// The share sheet's form (docs/screens.md, "Paylaşım formu"): a preview card with the shared
    /// content, mode tabs (`Olay | Görev`), a time chip (`Bugün · 14:32`) that opens a time picker
    /// in event mode, and a full-width primary capsule button ("Kenet'e ekle"). "Vazgeç" stays in
    /// the top bar.
    ///
    /// Built from the shared design tokens (`Color.ink`, `Font.ink`, `InkSpacing`, `InkCorner`,
    /// `InkStroke`, `InkSize`, `InkButtonChrome`) so both the extension target and the app's
    /// snapshot tests compile it without depending on the app's shell.
    struct ShareFormView: View {
        static let defaultTime: Date = {
            var components = DateComponents()
            components.year = 2026
            components.month = 4
            components.day = 20
            components.hour = 14
            components.minute = 32
            return Calendar.current.date(from: components) ?? Date(timeIntervalSince1970: 1_776_695_520)
        }()

        @Binding var text: String
        var kind: Binding<ShareEntryKind> = .constant(.event)
        var time: Binding<Date> = .constant(Self.defaultTime)
        var isTimed: Binding<Bool>? = nil
        let isSaving: Bool
        let failed: Bool
        let onCancel: () -> Void
        let onConfirm: () -> Void
        /// The keyboard comes up with the sheet; screenshots draw the field at rest.
        var focusesOnAppear = true
        @FocusState private var isFocused: Bool
        @State private var isPickingTime = false
        @State private var localIsTimed = true

        private var timedBinding: Binding<Bool> {
            isTimed ?? $localIsTimed
        }

        /// The text as it would be added: one line (`EntryWriting.singleLine`).
        private var canWrite: Bool {
            EntryWriting.canWrite(
                EntryWriting.singleLine(text), kind: kind.wrappedValue,
                timed: kind.wrappedValue == .event && timedBinding.wrappedValue)
        }

        /// What the confirm button will do (docs/screens.md, "Açıklama"). An event whose time was
        /// removed with ✕ goes in untimed, so it does not promise the chosen time.
        private var explanation: LocalizedStringKey {
            switch kind.wrappedValue {
            case .event:
                timedBinding.wrappedValue ? "Bugüne, seçilen saatle eklenir." : "Bugüne, saatsiz eklenir."
            case .task:
                "Bugüne görev olarak eklenir."
            }
        }

        private var formattedClock: String {
            let clock = LocalDay.clock(at: time.wrappedValue)
            let hour = (clock.hour < 10 ? "0" : "") + "\(clock.hour)"
            let minute = (clock.minute < 10 ? "0" : "") + "\(clock.minute)"
            return "\(hour):\(minute)"
        }

        var body: some View {
            NavigationStack {
                ScrollView {
                    VStack(alignment: .leading, spacing: InkSpacing.row) {
                        Text("Kenet'e ekle")
                            .font(.ink.display)
                            .foregroundStyle(.ink.text)
                            .accessibilityAddTraits(.isHeader)
                            .padding(.top, 4)
                        ShareModeTabs(selection: kind)
                            .disabled(isSaving)
                        previewCard
                        timeRow
                        if kind.wrappedValue == .event && timedBinding.wrappedValue && isPickingTime {
                            DatePicker(
                                "Saat",
                                selection: time,
                                displayedComponents: .hourAndMinute
                            )
                            .datePickerStyle(.wheel)
                            .labelsHidden()
                            .accessibilityLabel("Saat")
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 6)
                            .background(
                                Color.ink.surface,
                                in: RoundedRectangle(cornerRadius: InkCorner.card, style: .continuous)
                            )
                            .overlay(
                                RoundedRectangle(cornerRadius: InkCorner.card, style: .continuous)
                                    .strokeBorder(Color.ink.rule, lineWidth: InkStroke.rule)
                            )
                        }
                        Text(explanation)
                            .font(.ink.meta)
                            .foregroundStyle(.ink.secondaryText)
                        if !text.allSatisfy(\.isWhitespace) && !canWrite {
                            Text(
                                kind.wrappedValue == .event
                                    ? "Bu metin olay satırı olarak yazılamaz."
                                    : "Bu metin görev satırı olarak yazılamaz."
                            )
                            .font(.ink.meta)
                            .foregroundStyle(.ink.danger)
                        }
                        if failed {
                            Text("Paylaşım eklenemedi. Yeniden dene.")
                                .font(.ink.meta)
                                .foregroundStyle(.ink.danger)
                        }
                        Button(action: onConfirm) {
                            Text("Kenet'e ekle")
                                .opacity(isSaving ? 0 : 1)
                                .overlay {
                                    if isSaving { ProgressView().controlSize(.small) }
                                }
                        }
                        .buttonStyle(SharePrimaryCapsuleButtonStyle())
                        .disabled(!canWrite || isSaving)
                        .accessibilityIdentifier("button.share.add")
                        .padding(.top, 4)
                    }
                    .padding(.horizontal, InkSpacing.margin)
                    .padding(.vertical, InkSpacing.row)
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
                .background(Color.ink.elevated.ignoresSafeArea())
                .tint(.ink.accent)
                .navigationBarTitleDisplayMode(.inline)
                .toolbarBackground(Color.ink.elevated, for: .navigationBar)
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button(action: onCancel) { Text("Vazgeç") }
                            .buttonStyle(ShareSheetButtonStyle(isConfirm: false))
                            .disabled(isSaving)
                            .accessibilityIdentifier("button.share.cancel")
                    }
                    .sharedBackgroundVisibility(.hidden)
                }
            }
            .interactiveDismissDisabled(isSaving)
            .onAppear { isFocused = focusesOnAppear }
        }

        private var previewCard: some View {
            let promptKey: LocalizedStringKey = kind.wrappedValue == .event ? "Olay" : "Görev"
            return VStack(alignment: .leading, spacing: 8) {
                Text("Paylaşılan")
                    .font(.ink.meta)
                    .foregroundStyle(.ink.secondaryText)
                    .accessibilityHidden(true)
                TextField(
                    promptKey, text: $text, prompt: Text(promptKey).font(.ink.placeholder),
                    axis: .vertical
                )
                .lineLimit(1...5)
                .textFieldStyle(.plain)
                .font(.ink.content)
                .foregroundStyle(.ink.text)
                .focused($isFocused)
                .disabled(isSaving)
                .accessibilityIdentifier("field.share.text")
            }
            .padding(InkSpacing.cardPadding)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                Color.ink.surface,
                in: RoundedRectangle(cornerRadius: InkCorner.card, style: .continuous)
            )
            .overlay(
                RoundedRectangle(cornerRadius: InkCorner.card, style: .continuous)
                    .strokeBorder(
                        isFocused ? Color.ink.accent : Color.ink.rule,
                        lineWidth: isFocused ? InkStroke.control : InkStroke.rule)
            )
        }

        @ViewBuilder
        private var timeRow: some View {
            if kind.wrappedValue == .event {
                HStack(spacing: 4) {
                    if timedBinding.wrappedValue {
                        Button {
                            withAnimation(.easeOut(duration: 0.16)) {
                                isPickingTime.toggle()
                            }
                        } label: {
                            HStack(spacing: 6) {
                                Image(systemName: "clock")
                                    .font(.ink.meta)
                                    .foregroundStyle(.ink.secondaryText)
                                Text("Bugün · \(formattedClock)")
                                    .font(.ink.meta.weight(.medium))
                                    .monospacedDigit()
                                    .foregroundStyle(.ink.text)
                            }
                            .padding(.horizontal, 12)
                            .padding(.vertical, 6)
                            .background(Color.ink.well, in: Capsule())
                            .overlay(
                                Capsule()
                                    .strokeBorder(Color.ink.rule, lineWidth: InkStroke.rule)
                            )
                            .frame(minHeight: InkButtonChrome.minimumHeight)
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .disabled(isSaving)
                        .accessibilityLabel(Text("Saat, \(formattedClock)"))
                        .accessibilityHint(Text("Saati değiştirir"))
                        .accessibilityIdentifier("button.share.time")

                        Button {
                            withAnimation(.easeOut(duration: 0.16)) {
                                isPickingTime = false
                                timedBinding.wrappedValue = false
                            }
                        } label: {
                            Image(systemName: "xmark")
                                .font(.caption2.weight(.semibold))
                                .foregroundStyle(.ink.secondaryText)
                                .frame(
                                    minWidth: InkButtonChrome.minimumHeight,
                                    minHeight: InkButtonChrome.minimumHeight
                                )
                                .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .disabled(isSaving)
                        .accessibilityLabel("Saati kaldır")
                        .accessibilityIdentifier("button.share.clearTime")
                    } else {
                        Button {
                            withAnimation(.easeOut(duration: 0.16)) {
                                timedBinding.wrappedValue = true
                                isPickingTime = true
                            }
                        } label: {
                            HStack(spacing: 6) {
                                Image(systemName: "plus")
                                    .font(.ink.meta)
                                    .foregroundStyle(.ink.secondaryText)
                                Text("Saati ekle")
                                    .font(.ink.meta.weight(.medium))
                                    .foregroundStyle(.ink.secondaryText)
                            }
                            .padding(.horizontal, 12)
                            .padding(.vertical, 6)
                            .background(Color.ink.well, in: Capsule())
                            .overlay(
                                Capsule()
                                    .strokeBorder(Color.ink.rule, lineWidth: InkStroke.rule)
                            )
                            .frame(minHeight: InkButtonChrome.minimumHeight)
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .disabled(isSaving)
                        .accessibilityIdentifier("button.share.addTime")
                    }
                    Spacer(minLength: 0)
                }
            }
        }
    }

    /// Underlined mode tabs (`Olay | Görev`), drawn with the same rules as `InkTabs` (left-aligned
    /// words on a hairline rule, 44 pt touch targets, accent underline on the selected word).
    private struct ShareModeTabs: View {
        @Binding var selection: ShareEntryKind
        @Environment(\.displayScale) private var displayScale

        var body: some View {
            VStack(alignment: .leading, spacing: 0) {
                ViewThatFits(in: .horizontal) {
                    HStack(spacing: 20) { words(wraps: false) }
                    VStack(alignment: .leading, spacing: 0) { words(wraps: true) }
                }
                Rectangle()
                    .fill(Color.ink.rule)
                    .frame(height: InkStroke.hairline(scale: displayScale))
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .accessibilityElement(children: .contain)
            .accessibilityAddTraits(.isTabBar)
        }

        @ViewBuilder
        private func words(wraps: Bool) -> some View {
            tab(.event, title: "Olay", wraps: wraps)
            tab(.task, title: "Görev", wraps: wraps)
        }

        private func tab(_ value: ShareEntryKind, title: LocalizedStringKey, wraps: Bool) -> some View {
            let isSelected = selection == value
            return Button {
                withAnimation(.easeOut(duration: 0.16)) {
                    selection = value
                }
            } label: {
                Text(title)
                    .font(.ink.byline)
                    .fontWeight(isSelected ? .semibold : .regular)
                    .foregroundStyle(isSelected ? Color.ink.text : Color.ink.secondaryText)
                    .fixedSize(horizontal: !wraps, vertical: true)
                    .padding(.vertical, 8)
                    .overlay(alignment: .bottom) {
                        Rectangle()
                            .fill(isSelected ? Color.ink.accent : Color.clear)
                            .frame(height: InkSize.modeUnderline)
                    }
                    .frame(
                        minWidth: InkButtonChrome.minimumHeight,
                        minHeight: InkButtonChrome.minimumHeight,
                        alignment: .bottomLeading
                    )
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityAddTraits(isSelected ? [.isSelected] : [])
        }
    }

    private struct SharePrimaryCapsuleButtonStyle: ButtonStyle {
        @Environment(\.isEnabled) private var isEnabled

        func makeBody(configuration: Configuration) -> some View {
            let role = InkButtonChrome.primary.role(
                isPressed: configuration.isPressed, isEnabled: isEnabled)
            return configuration.label
                .font(.ink.byline)
                .foregroundStyle(isEnabled ? Color.ink.onAccent : Color.ink.secondaryText)
                .padding(.horizontal, 22)
                .padding(.vertical, 12)
                .frame(maxWidth: .infinity, minHeight: 50)
                .background(
                    Capsule()
                        .fill(backgroundColor(for: role.background))
                )
                .overlay(
                    Capsule()
                        .strokeBorder(
                            isEnabled ? Color.clear : Color.ink.control,
                            lineWidth: InkStroke.control)
                )
                .contentShape(Capsule())
        }

        private func backgroundColor(for token: InkButtonChrome.Token?) -> Color {
            switch token {
            case .accent: .ink.accent
            case .text: .ink.text
            default: .ink.well
            }
        }
    }

    /// The sheet's cancel button in the top bar.
    private struct ShareSheetButtonStyle: ButtonStyle {
        let isConfirm: Bool
        @Environment(\.isEnabled) private var isEnabled

        func makeBody(configuration: Configuration) -> some View {
            configuration.label
                .font(.ink.byline)
                .fontWeight(isConfirm ? .semibold : .regular)
                .foregroundStyle(color(isPressed: configuration.isPressed))
                .lineLimit(1)
                .fixedSize()
                .frame(minHeight: InkButtonChrome.minimumHeight)
                .contentShape(Rectangle())
                // One fixed-height bar: the words stop growing at AX2, as in the app's sheets.
                .dynamicTypeSize(...DynamicTypeSize.accessibility2)
        }

        private func color(isPressed: Bool) -> Color {
            if isPressed { return .ink.text }
            if !isEnabled { return isConfirm ? .ink.secondaryText : .ink.control }
            return isConfirm ? .ink.accent : .ink.secondaryText
        }
    }
#endif
