#if os(iOS)
    import SwiftUI

    /// The share sheet's form (docs/screens.md, "Paylaşım formu"): one field, filled with what was
    /// shared (a page's title and link, or the selected text). The event goes to today at the
    /// current minute; "Ekle" adds it as one line, "Vazgeç" closes the sheet. Text Core would not
    /// write as an event line (in practice: empty) cannot be added.
    ///
    /// It looks like the app's editing sheets (`.inkSheet`: paper, serif manşet, plain "Vazgeç" and
    /// an accent confirm word, the page's well field) but is built from the design tokens alone: the
    /// extension does not compile the app's components, which depend on its shell. The extension
    /// draws it; the app compiles it too so its screenshot tests can draw it.
    struct ShareFormView: View {
        @Binding var text: String
        let isSaving: Bool
        let failed: Bool
        let onCancel: () -> Void
        let onConfirm: () -> Void
        /// The keyboard comes up with the sheet; screenshots draw the field at rest.
        var focusesOnAppear = true
        @FocusState private var isFocused: Bool

        /// The text as it would be added: one line (`EntryWriting.singleLine`).
        private var canWrite: Bool { EntryWriting.canWrite(EntryWriting.singleLine(text)) }

        var body: some View {
            NavigationStack {
                ScrollView {
                    VStack(alignment: .leading, spacing: InkSpacing.section) {
                        Text("Olay olarak ekle")
                            .font(.ink.display)
                            .foregroundStyle(.ink.text)
                            .accessibilityAddTraits(.isHeader)
                            .padding(.top, 4)
                            .padding(.bottom, 8)
                        VStack(alignment: .leading, spacing: 12) {
                            VStack(alignment: .leading, spacing: 4) {
                                // Visible label; VoiceOver reads the same word as the field's own label.
                                Text("Olay")
                                    .font(.ink.meta)
                                    .foregroundStyle(.ink.secondaryText)
                                    .accessibilityHidden(true)
                                field
                            }
                            Text("Bugüne, şimdiki saatle eklenir.")
                                .font(.ink.meta)
                                .foregroundStyle(.ink.secondaryText)
                            if !text.allSatisfy(\.isWhitespace) && !canWrite {
                                Text("Bu metin olay satırı olarak yazılamaz.")
                                    .font(.ink.meta)
                                    .foregroundStyle(.ink.danger)
                            }
                            if failed {
                                Text("Paylaşım eklenemedi. Yeniden dene.")
                                    .font(.ink.meta)
                                    .foregroundStyle(.ink.danger)
                            }
                        }
                    }
                    .padding(.horizontal, InkSpacing.margin)
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
                .background(Color.ink.paper)
                .tint(.ink.accent)
                .navigationBarTitleDisplayMode(.inline)
                .toolbarBackground(Color.ink.paper, for: .navigationBar)
                .toolbar {
                    // iOS 26 draws every toolbar item in a glass capsule; the app's sheets hide it.
                    ToolbarItem(placement: .cancellationAction) {
                        Button(action: onCancel) { Text("Vazgeç") }
                            .buttonStyle(ShareSheetButtonStyle(isConfirm: false))
                            .disabled(isSaving)
                            .accessibilityIdentifier("button.share.cancel")
                    }
                    .sharedBackgroundVisibility(.hidden)
                    ToolbarItem(placement: .confirmationAction) {
                        Button(action: onConfirm) {
                            Text("Ekle")
                                .opacity(isSaving ? 0 : 1)
                                .overlay {
                                    if isSaving { ProgressView().controlSize(.small) }
                                }
                        }
                        .buttonStyle(ShareSheetButtonStyle(isConfirm: true))
                        .disabled(!canWrite || isSaving)
                        .accessibilityIdentifier("button.share.add")
                    }
                    .sharedBackgroundVisibility(.hidden)
                }
            }
            .interactiveDismissDisabled(isSaving)
            .onAppear { isFocused = focusesOnAppear }
        }

        /// The page's well field (`InkFilterField`), growing to a few lines for a title and link.
        private var field: some View {
            TextField("Olay", text: $text, prompt: Text("Olay").font(.ink.placeholder), axis: .vertical)
                .lineLimit(1...5)
                .textFieldStyle(.plain)
                .font(.ink.content)
                .foregroundStyle(.ink.text)
                .focused($isFocused)
                .disabled(isSaving)
                .accessibilityIdentifier("field.share.text")
                .padding(.horizontal, 12)
                .padding(.vertical, 10)
                .background(
                    Color.ink.well, in: RoundedRectangle(cornerRadius: InkSize.kanbanCorner, style: .continuous)
                )
                .overlay(
                    RoundedRectangle(cornerRadius: InkSize.kanbanCorner, style: .continuous)
                        .strokeBorder(isFocused ? Color.ink.accent : Color.ink.control, lineWidth: InkStroke.control)
                )
        }
    }

    /// The sheet's words, as the app's sheets draw them: "Vazgeç" in secondary text, the confirm
    /// word in accent semibold; disabled steps down a token, pressed is text.
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
