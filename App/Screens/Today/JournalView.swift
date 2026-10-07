import SwiftUI
import VaultFormat

/// Opens raw Journal content in the shared phone/Mac editor.
struct JournalView: View {
    @State private var isClosing = false
    @State private var leavePrompt = false
    @State private var model: JournalEditorModel
    @State private var selection: TextSelection?
    @FocusState private var isFocused: Bool
    @Environment(\.dismiss) private var dismiss

    private let focusesOnLoad: Bool

    /// - Parameter focusesOnLoad: `false` keeps the caret out of snapshot references.
    init(store: IndexStore, date: CalendarDate, focusesOnLoad: Bool = true) {
        _model = State(initialValue: JournalEditorModel(store: store, day: date))
        self.focusesOnLoad = focusesOnLoad
    }

    private var blocksLeave: Bool {
        UnsavedDraftDecision.requiresPrompt(isDirty: model.isDirty, isSaving: model.isSaving)
    }

    private var insertionOffset: Int? {
        if let selection, case .selection(let range) = selection.indices {
            guard range.lowerBound >= model.text.startIndex, range.lowerBound <= model.text.endIndex
            else { return nil }
            return model.text[..<range.lowerBound].utf8.count
        }
        return nil
    }

    var body: some View {
        @Bindable var model = model
        VStack(alignment: .leading, spacing: 0) {
            InkPageTitle("Günlük yazısı")
            editor(text: $model.text)
                .padding(.horizontal, InkSpacing.margin)
                .padding(.bottom, InkSpacing.margin)
        }
        .inkPageColumn()
        .navigationBarBackButtonHidden(blocksLeave)
        .interactiveDismissDisabled(blocksLeave || model.isSaving)
        .inkSheet(
            "Günlük yazısı", isConfirmEnabled: model.canSave, isBusy: model.isSaving,
            // "Vazgeç" stays inert while a write is in flight, as before.
            onCancel: { if !model.isSaving { requestLeave() } },
            onConfirm: saveAndClose
        )
        .confirmationDialog("Kaydedilmemiş değişiklikler", isPresented: $leavePrompt) {
            Button("Kaydet", action: saveAndClose)
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
            isFocused = focusesOnLoad && model.isLoaded
        }
    }

    private func editor(text: Binding<String>) -> some View {
        VStack(alignment: .leading) {
            if let error = model.errorText {
                Text(verbatim: error).font(.ink.meta).foregroundStyle(.ink.danger)
                    .accessibilityAddTraits(.updatesFrequently)
            }
            if !model.isLoaded {
                if model.errorText == nil {
                    ProgressView("Günlük yazısı yükleniyor…")
                } else {
                    Button("Yeniden dene") { Task { await model.load() } }
                        .buttonStyle(InkTextButtonStyle())
                }
            }
            TextEditor(text: text, selection: $selection)
                .font(.ink.content)
                .inkJournalParagraph()
                .foregroundStyle(.ink.text)
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
            // Assist below the field so chips do not push the caret off-screen.
            MentionAssistStrip(
                composer: model.composer, store: model.store, insertionOffset: insertionOffset,
                isEnabled: model.isLoaded && !model.isSaving,
                onDidChangeText: { caret in
                    if let caret,
                        let next = MentionComposer.textSelection(atByteOffset: caret, in: model.text)
                    {
                        selection = next
                    }
                    isFocused = true
                },
                onResolved: {
                    Task { await model.save() }
                }
            )
        }
    }

    private func saveAndClose() {
        isClosing = true
        Task {
            if await model.save(), !model.isDirty && model.errorText == nil {
                dismiss()
            } else {
                isClosing = false
            }
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
