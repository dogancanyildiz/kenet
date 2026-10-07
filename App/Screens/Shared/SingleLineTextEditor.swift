import SwiftUI

/// Shared one-line editor for events and tasks: an editing sheet ("Vazgeç" / "Kaydet") whose
/// single field is the page's well field. Hosted inside the caller's `NavigationStack`.
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
            "Metni düzenle", isConfirmEnabled: canSave, isBusy: isSaving,
            cancelIdentifier: "button.textEditor.cancel", confirmIdentifier: "button.textEditor.save",
            onCancel: { if !isSaving { dismiss() } }, onConfirm: submit,
            content: {
                VStack(alignment: .leading, spacing: 12) {
                    InkFilterField(
                        placeholder, text: $text, isFocused: $isFocused, identifier: "field.textEditor"
                    )
                    .disabled(isDisabled)
                    .onSubmit { submit() }
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
