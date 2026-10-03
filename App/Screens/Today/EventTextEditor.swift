import SwiftUI

struct EventTextEditor: View {
    @Bindable var model: EventEditorModel
    @Environment(\.dismiss) private var dismiss
    @FocusState private var isFocused: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            TextField("Olay metni", text: $model.text)
                .textFieldStyle(.roundedBorder)
                .focused($isFocused)
                .disabled(model.target == nil || model.isSaving || model.isSaved)
                .onSubmit { save() }
            if let error = model.errorText { Text(verbatim: error).foregroundStyle(.red).font(.caption) }
        }
        .padding()
        .navigationTitle("Metni düzenle")
        .interactiveDismissDisabled(model.isSaving)
        .toolbar {
            ToolbarItem(placement: .confirmationAction) {
                Button("Bitti") { save() }.disabled(!model.canSave)
            }
            ToolbarItem(placement: .cancellationAction) {
                Button("Vazgeç") { dismiss() }.disabled(model.isSaving)
            }
        }
        .task {
            await model.load()
            isFocused = model.target != nil
        }
    }

    private func save() {
        Task {
            if await model.save(), model.errorText == nil { dismiss() }
        }
    }
}
