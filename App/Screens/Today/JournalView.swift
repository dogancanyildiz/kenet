import SwiftUI
import VaultFormat

/// Opens raw Journal content in the shared phone/Mac editor.
struct JournalView: View {
    @State private var isClosing = false
    @State private var model: JournalEditorModel
    @FocusState private var isFocused: Bool
    @Environment(\.dismiss) private var dismiss

    init(store: IndexStore, date: CalendarDate) {
        _model = State(initialValue: JournalEditorModel(store: store, day: date))
    }

    var body: some View {
        @Bindable var model = model
        VStack(alignment: .leading) {
            if let error = model.errorText {
                Text(verbatim: error).font(.caption).foregroundStyle(.red)
                    .accessibilityAddTraits(.updatesFrequently)
            }
            if !model.isLoaded {
                if model.errorText == nil {
                    ProgressView("Günlük yazısı yükleniyor…")
                } else {
                    Button("Yeniden dene") { Task { await model.load() } }
                }
            }
            TextEditor(text: $model.text)
                .accessibilityLabel("Günlük yazısı")
                .focused($isFocused)
                .disabled(!model.isLoaded || model.isSaving)
                .onChange(of: isFocused) { _, focused in
                    if !focused && !isClosing && !model.isSaving && model.isDirty {
                        Task {
                            guard !isClosing else { return }
                            await model.save()
                        }
                    }
                }
        }
        .padding()
        .navigationTitle("Günlük yazısı")
        .interactiveDismissDisabled(model.isDirty || model.isSaving)
        .toolbar {
            ToolbarItem(placement: .confirmationAction) {
                Button("Bitti") {
                    isClosing = true
                    Task {
                        if await model.save(), !model.isDirty && model.errorText == nil {
                            dismiss()
                        } else {
                            isClosing = false
                        }
                    }
                }
                .disabled(!model.canSave)
            }
            ToolbarItem(placement: .cancellationAction) {
                Button("Vazgeç") {
                    isClosing = true
                    dismiss()
                }.disabled(model.isSaving)
            }
        }
        .task {
            await model.load()
            isFocused = model.isLoaded
        }
    }
}
