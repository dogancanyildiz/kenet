import GoalTracking
import SwiftUI

struct GoalValueEditor: View {
    @Bindable var model: GoalValueModel
    @Environment(\.dismiss) private var dismiss
    var body: some View {
        Form {
            Section {
                Text(LocalDay.instant(for: model.dayModel.day), format: .dateTime.day().month().year())
                if model.goal.kind == .boolean {
                    Toggle("Yapıldı", isOn: $model.done)
                } else {
                    HStack {
                        Button("Azalt", systemImage: "minus") { model.step(-1) }.labelStyle(.iconOnly)
                        TextField("Miktar", text: $model.amount).textFieldStyle(.roundedBorder)
                            #if os(iOS)
                                .keyboardType(.decimalPad)
                            #endif
                        Button("Artır", systemImage: "plus") { model.step(1) }.labelStyle(.iconOnly)
                    }.buttonStyle(.borderless)
                    LabeledContent("Hedef", value: model.goal.target.formatted() + " " + (model.goal.unit ?? ""))
                    if model.value == nil { Text("Sıfır veya pozitif bir sayı gir.").foregroundStyle(.secondary) }
                }
                if let error = model.dayModel.errorText { Text(verbatim: error).foregroundStyle(.secondary) }
                Button("Kaydı kaldır", role: .destructive) { Task { await save(remove: true) } }
                    .disabled(!model.dayModel.canEdit || model.isSaved)
            }.disabled(model.isSaved)
        }
        .formStyle(.grouped).navigationTitle(Text(verbatim: model.goal.name))
        .toolbar {
            ToolbarItem(placement: .cancellationAction) { Button("Kapat") { dismiss() } }
            ToolbarItem(placement: .confirmationAction) {
                Button("Kaydet") { Task { await save() } }.disabled(!model.canSave)
            }
        }
        .frame(minWidth: 300, minHeight: 250)
    }
    private func save(remove: Bool = false) async {
        if await model.save(remove: remove), model.dayModel.errorText == nil { dismiss() }
    }
}
