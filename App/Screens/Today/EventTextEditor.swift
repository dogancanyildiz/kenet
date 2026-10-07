import SwiftUI

struct EventTextEditor: View {
    @Bindable var model: EventEditorModel
    @Environment(\.dismiss) private var dismiss
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
        SingleLineTextEditor(
            text: $model.text, placeholder: "Olay metni", canSave: model.canSave,
            isDisabled: model.target == nil || model.isSaving || model.isSaved,
            isSaving: model.isSaving, errorText: model.errorText, selection: $selection,
            load: {
                await model.load()
            },
            save: {
                let saved = await model.save()
                return saved && model.errorText == nil
            },
            assist: {
                MentionAssistStrip(
                    composer: model.composer, store: model.store, insertionOffset: insertionOffset,
                    isEnabled: model.target != nil && !model.isSaving && !model.isSaved,
                    onDidChangeText: { caret in
                        if let caret,
                            let next = MentionComposer.textSelection(atByteOffset: caret, in: model.text)
                        {
                            selection = next
                        }
                    },
                    onResolved: {
                        Task {
                            if await model.save(), model.errorText == nil { dismiss() }
                        }
                    }
                )
            }
        )
    }
}
