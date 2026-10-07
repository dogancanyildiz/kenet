import SwiftUI

struct TaskTextEditor: View {
    @Bindable var model: TaskEditorModel

    var body: some View {
        SingleLineTextEditor(
            text: $model.text, placeholder: "Görev metni", canSave: model.canSave,
            isDisabled: model.target == nil || model.isSaving || model.isSaved,
            isSaving: model.isSaving, errorText: model.errorText,
            load: { await model.load() }, save: { await model.save() && model.errorText == nil })
    }
}

struct TaskDateEditor: View {
    @Bindable var model: TaskEditorModel
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        // Each choice writes at once and closes the sheet, so this is a closing sheet: "Kapat" only
        // (inert while a write is in flight, as before).
        InkSheetScaffold(
            "Görev tarihi", onClose: { if !model.isSaving { dismiss() } },
            content: {
                TaskDatePicker(current: model.row.due) { date in
                    Task { if await model.setDue(date), model.errorText == nil { dismiss() } }
                }
                .disabled(model.target == nil || model.isSaving || model.isSaved)
                if let error = model.errorText {
                    InfoBand(kind: .error, verbatim: error)
                }
            }
        )
        .interactiveDismissDisabled(model.isSaving)
        .task { await model.load() }
    }
}
