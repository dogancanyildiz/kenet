import SwiftUI
import VaultFormat

/// Opens raw Journal content in the shared phone/Mac editor.
struct JournalView: View {
    @State private var isClosing = false
    @State private var leavePrompt = false
    @State private var model: JournalEditorModel
    @FocusState private var isFocused: Bool
    @Environment(\.dismiss) private var dismiss

    init(store: IndexStore, date: CalendarDate) {
        _model = State(initialValue: JournalEditorModel(store: store, day: date))
    }

    private var blocksLeave: Bool {
        UnsavedDraftDecision.requiresPrompt(isDirty: model.isDirty, isSaving: model.isSaving)
    }

    var body: some View {
        @Bindable var model = model
        VStack(alignment: .leading) {
            if let error = model.errorText {
                InfoBand(kind: .error, verbatim: error)
                    .accessibilityAddTraits(.updatesFrequently)
            }
            if !model.isLoaded {
                if model.errorText == nil {
                    InkProgress(kind: .indeterminate(label: "Günlük yazısı yükleniyor…"))
                } else {
                    Button("Yeniden dene") { Task { await model.load() } }
                        .buttonStyle(InkTextButtonStyle())
                }
            }
            TextEditor(text: $model.text)
                .font(.ink.content)
                .foregroundStyle(Color.ink.text)
                .scrollContentBackground(.hidden)
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
        .padding(InkSpacing.margin)
        .inkPage()
        .navigationTitle("Günlük yazısı")
        .navigationBarBackButtonHidden(blocksLeave)
        .interactiveDismissDisabled(blocksLeave || model.isSaving)
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
                    requestLeave()
                }.disabled(model.isSaving)
            }
        }
        .confirmationDialog("Kaydedilmemiş değişiklikler", isPresented: $leavePrompt) {
            Button("Kaydet") {
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
            Button("At", role: .destructive) {
                isClosing = true
                dismiss()
            }
            Button("Vazgeç", role: .cancel) {}
        } message: {
            Text("Kaydedilmemiş günlük metni var.")
        }
        .onChange(of: model.store.vaultURL) { _, _ in
            if UnsavedDraftDecision.requiresPrompt(isDirty: model.isDirty, isSaving: model.isSaving) {
                leavePrompt = true
            }
        }
        .task {
            await model.load()
            isFocused = model.isLoaded
        }
    }

    private func requestLeave() {
        if UnsavedDraftDecision.canLeaveImmediately(isDirty: model.isDirty, isSaving: model.isSaving) {
            isClosing = true
            dismiss()
        } else {
            leavePrompt = true
        }
    }
}
