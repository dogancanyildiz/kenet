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
                .font(.ink.content)
            LabeledContent("Anahtar") {
                Text(verbatim: model.key)
                    .font(.ink.meta)
                    .foregroundStyle(Color.ink.secondaryText)
            }
            if model.kind != .milestone {
                Picker("Dönem", selection: $model.period) {
                    Text(GoalPeriod.day.title).tag(GoalPeriod.day)
                    Text(GoalPeriod.week.title).tag(GoalPeriod.week)
                    Text(GoalPeriod.year.title).tag(GoalPeriod.year)
                }
            }
            Picker("Tür", selection: $model.kind) {
                Text(GoalKind.boolean.title).tag(GoalKind.boolean)
                Text(GoalKind.number.title).tag(GoalKind.number)
                Text(GoalKind.milestone.title).tag(GoalKind.milestone)
            }
            if model.kind != .milestone {
                TextField("Hedef miktar", text: $model.target)
                    .font(.ink.value)
                    #if os(iOS)
                        .keyboardType(.decimalPad)
                    #endif
            }
            if model.kind == .number {
                TextField("Birim (isteğe bağlı)", text: $model.unit)
                    .font(.ink.content)
            }
            if let error = model.errorText {
                InfoBand(kind: .error, verbatim: error)
            }
        }
        .formStyle(.grouped)
        .scrollContentBackground(.hidden)
        .background(Color.ink.surface)
        .disabled(model.isWriting || model.isSaved)
        .navigationTitle("Yeni hedef")
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button("Kapat") { dismiss() }
                    .buttonStyle(InkTextButtonStyle())
            }
            ToolbarItem(placement: .confirmationAction) {
                Button("Oluştur") {
                    Task { if await model.save(), model.errorText == nil { dismiss() } }
                }
                .buttonStyle(InkPrimaryButtonStyle())
                .disabled(!model.canSave)
            }
        }
        .frame(minWidth: 320, minHeight: 350)
    }
}
