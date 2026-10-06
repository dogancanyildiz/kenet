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
                    Text(verbatim: GoalPeriod.day.title).tag(GoalPeriod.day)
                    Text(verbatim: GoalPeriod.week.title).tag(GoalPeriod.week)
                    Text(verbatim: GoalPeriod.year.title).tag(GoalPeriod.year)
                }
            }
            Picker("Tür", selection: $model.kind) {
                Text(verbatim: GoalKind.boolean.title).tag(GoalKind.boolean)
                Text(verbatim: GoalKind.number.title).tag(GoalKind.number)
                Text(verbatim: GoalKind.milestone.title).tag(GoalKind.milestone)
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
            // Content action stays reachable at AX sizes when the trailing toolbar item is clipped.
            Button("Oluştur") {
                Task { if await model.save(), model.errorText == nil { dismiss() } }
            }
            .buttonStyle(InkPrimaryButtonStyle())
            .disabled(!model.canSave || model.isWriting || model.isSaved)
            .listRowBackground(Color.clear)
        }
        .formStyle(.grouped)
        .scrollContentBackground(.hidden)
        .background(Color.ink.surface)
        .disabled(model.isWriting || model.isSaved)
        .navigationTitle("Yeni hedef")
        #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
        #endif
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button("Kapat") { dismiss() }
            }
            ToolbarItem(placement: .confirmationAction) {
                Button("Oluştur") {
                    Task { if await model.save(), model.errorText == nil { dismiss() } }
                }
                .disabled(!model.canSave)
            }
        }
        .frame(minWidth: 320, minHeight: 350)
    }
}
