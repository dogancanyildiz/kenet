import SwiftUI

/// Shared one-line editor for events and tasks: an editing sheet ("Vazgeç" / "Kaydet") whose
/// single field is the page's well field under a visible label. While saving, "Vazgeç" is
/// drawn disabled. Hosted inside the caller's `NavigationStack`.
struct SingleLineTextEditor: View {
    @Binding var text: String
    let placeholder: LocalizedStringKey
    let canSave: Bool
    let isDisabled: Bool
    let isSaving: Bool
    let errorText: String?
    let load: () async -> Void
    let save: () async -> Bool
    @Environment(\.dismiss) private var dismiss
    @FocusState private var isFocused: Bool

    var body: some View {
        InkSheetScaffold(
            "Metni düzenle", confirm: .save, isConfirmEnabled: canSave, isBusy: isSaving,
            isCancelEnabled: !isSaving, cancelIdentifier: "button.textEditor.cancel",
            confirmIdentifier: "button.textEditor.save", onCancel: nil, onConfirm: submit,
            content: {
                VStack(alignment: .leading, spacing: 12) {
                    VStack(alignment: .leading, spacing: 4) {
                        // Visible label; VoiceOver reads the same words as the field's own label.
                        Text(placeholder)
                            .font(.ink.meta)
                            .foregroundStyle(Color.ink.secondaryText)
                            .accessibilityHidden(true)
                        InkFilterField(
                            placeholder, text: $text, isFocused: $isFocused, identifier: "field.textEditor"
                        )
                        .disabled(isDisabled)
                        .onSubmit { submit() }
                    }
                    if let error = errorText {
                        Text(verbatim: error).foregroundStyle(.ink.danger).font(.ink.meta)
                    }
                }
            }
        )
        .interactiveDismissDisabled(isSaving)
        .task {
            await load()
            isFocused = !isDisabled
        }
    }

    private func submit() {
        Task { if await save() { dismiss() } }
    }
}
