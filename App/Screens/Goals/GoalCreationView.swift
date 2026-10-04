import GoalTracking
import SwiftUI

struct GoalCreationView: View {
    @State private var model: GoalCreationModel
    @Environment(\.dismiss) private var dismiss
    init(store: IndexStore) { _model = State(initialValue: GoalCreationModel(store: store)) }
    var body: some View {
        @Bindable var model = model
        Form {
            TextField("Ad", text: $model.name)
            LabeledContent("Anahtar", value: model.key)
            Picker("Dönem", selection: $model.period) {
                Text(GoalPeriod.day.title).tag(GoalPeriod.day)
                Text(GoalPeriod.week.title).tag(GoalPeriod.week)
                Text(GoalPeriod.year.title).tag(GoalPeriod.year)
            }
            Picker("Tür", selection: $model.kind) {
                Text(GoalKind.boolean.title).tag(GoalKind.boolean)
                Text(GoalKind.number.title).tag(GoalKind.number)
            }
            TextField("Hedef miktar", text: $model.target)
                #if os(iOS)
                    .keyboardType(.decimalPad)
                #endif
            if model.kind == .number { TextField("Birim (isteğe bağlı)", text: $model.unit) }
            if let error = model.errorText { Text(verbatim: error).foregroundStyle(.secondary) }
        }
        .formStyle(.grouped).disabled(model.isWriting || model.isSaved)
        .navigationTitle("Yeni hedef")
        .toolbar {
            ToolbarItem(placement: .cancellationAction) { Button("Kapat") { dismiss() } }
            ToolbarItem(placement: .confirmationAction) {
                Button("Oluştur") { Task { if await model.save(), model.errorText == nil { dismiss() } } }.disabled(
                    !model.canSave)
            }
        }
        .frame(minWidth: 320, minHeight: 350)
    }
}
