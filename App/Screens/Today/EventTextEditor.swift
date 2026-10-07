import SwiftUI

struct EventTextEditor: View {
    @Bindable var model: EventEditorModel

    var body: some View {
        SingleLineTextEditor(
            text: $model.text, placeholder: "Olay metni", canSave: model.canSave,
            isDisabled: model.target == nil || model.isSaving || model.isSaved,
            isSaving: model.isSaving, errorText: model.errorText,
            load: { await model.load() }, save: { await model.save() && model.errorText == nil })
    }
}
