import SwiftUI

/// Shared one-line editor for events and tasks.
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
        VStack(alignment: .leading, spacing: 12) {
            TextField(placeholder, text: $text)
                .textFieldStyle(.roundedBorder).focused($isFocused).disabled(isDisabled)
                .onSubmit { submit() }
            if let error = errorText { Text(verbatim: error).foregroundStyle(.red).font(.caption) }
        }
        .padding().navigationTitle("Metni düzenle")
        .interactiveDismissDisabled(isSaving)
        .toolbar {
            ToolbarItem(placement: .confirmationAction) {
                Button("Bitti") { submit() }.disabled(!canSave)
            }
            ToolbarItem(placement: .cancellationAction) {
                Button("Vazgeç") { dismiss() }.disabled(isSaving)
            }
        }
        .task {
            await load()
            isFocused = !isDisabled
        }
    }

    private func submit() {
        Task { if await save() { dismiss() } }
    }
}
