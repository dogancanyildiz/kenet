import SwiftUI

struct EventTextEditor: View {
    @Bindable var model: EventEditorModel
    @Environment(\.dismiss) private var dismiss
    @FocusState private var isFocused: Bool
    @State private var selection: TextSelection?

    private var insertionOffset: Int? {
        if let selection, case .selection(let range) = selection.indices {
            guard range.lowerBound >= model.text.startIndex, range.lowerBound <= model.text.endIndex
            else { return nil }
            return model.text[..<range.lowerBound].utf8.count
        }
        return nil
    }

    var body: some View {
        InkSheetScaffold(
            "Metni düzenle", confirm: .save, isConfirmEnabled: model.canSave, isBusy: model.isSaving,
            isCancelEnabled: !model.isSaving, cancelIdentifier: "button.textEditor.cancel",
            confirmIdentifier: "button.textEditor.save", onCancel: nil, onConfirm: submit,
            content: {
                VStack(alignment: .leading, spacing: 12) {
                    MentionAssistStrip(
                        composer: model.composer, store: model.store, insertionOffset: insertionOffset,
                        isEnabled: model.target != nil && !model.isSaving && !model.isSaved,
                        onDidChangeText: {
                            selection = nil
                            isFocused = true
                        },
                        onResolved: submit
                    )
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Olay metni")
                            .font(.ink.meta)
                            .foregroundStyle(Color.ink.secondaryText)
                            .accessibilityHidden(true)
                        InkFilterField(
                            "Olay metni", text: $model.text, selection: $selection, isFocused: $isFocused,
                            identifier: "field.textEditor", showsClearButton: false
                        )
                        .disabled(model.target == nil || model.isSaving || model.isSaved)
                        .onSubmit { submit() }
                    }
                    if let error = model.errorText {
                        Text(verbatim: error).foregroundStyle(.ink.danger).font(.ink.meta)
                    }
                }
            }
        )
        .interactiveDismissDisabled(model.isSaving)
        .task {
            await model.load()
            isFocused = model.target != nil && !model.isSaving && !model.isSaved
        }
    }

    private func submit() {
        Task {
            if await model.save() {
                if model.errorText == nil { dismiss() }
            } else {
                isFocused = true
            }
        }
    }
}
