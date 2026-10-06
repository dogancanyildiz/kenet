import GoalTracking
import SwiftUI

struct GoalValueEditor: View {
    @Bindable var model: GoalValueModel
    @Environment(\.dismiss) private var dismiss
    @State private var deleteConfirmation = DestructiveConfirmation<DestructiveConfirmationToken>()

    var body: some View {
        Form {
            Section {
                Text(LocalDay.instant(for: model.dayModel.day), format: .dateTime.day().month().year())
                    .font(.ink.meta)
                    .foregroundStyle(Color.ink.secondaryText)
                if model.goal.kind != .number {
                    Toggle("Yapıldı", isOn: $model.done)
                } else {
                    HStack {
                        Button {
                            model.step(-1)
                        } label: {
                            Label("Azalt", systemImage: "minus")
                                .labelStyle(.iconOnly)
                                .foregroundStyle(Color.ink.accent)
                                .tapTarget()
                        }
                        TextField("Miktar", text: $model.amount)
                            .font(.ink.value)
                            .textFieldStyle(.roundedBorder)
                            #if os(iOS)
                                .keyboardType(.decimalPad)
                            #endif
                        Button {
                            model.step(1)
                        } label: {
                            Label("Artır", systemImage: "plus")
                                .labelStyle(.iconOnly)
                                .foregroundStyle(Color.ink.accent)
                                .tapTarget()
                        }
                    }.buttonStyle(.borderless)
                    LabeledContent("Hedef") {
                        Text(
                            verbatim: model.goal.target.formatted() + " " + (model.goal.unit ?? "")
                        )
                        .font(.ink.value)
                    }
                    if model.value == nil {
                        Text("Sıfır veya pozitif bir sayı gir.")
                            .font(.ink.meta)
                            .foregroundStyle(Color.ink.secondaryText)
                    }
                }
                if let error = model.dayModel.errorText {
                    InfoBand(kind: .error, verbatim: error)
                }
                Button("Kaydı kaldır", role: .destructive) { deleteConfirmation.request(.pending) }
                    .buttonStyle(InkDestructiveButtonStyle())
                    .disabled(!model.dayModel.canEdit || model.isSaved)
            }.disabled(model.isSaved)
        }
        .formStyle(.grouped)
        .scrollContentBackground(.hidden)
        .background(Color.ink.surface)
        .navigationTitle(Text(verbatim: model.goal.name))
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button("Kapat") { dismiss() }
                    .buttonStyle(InkTextButtonStyle())
            }
            ToolbarItem(placement: .confirmationAction) {
                Button("Kaydet") { Task { await save() } }
                    .buttonStyle(InkPrimaryButtonStyle())
                    .disabled(!model.canSave)
            }
        }
        .destructiveConfirmationDialog(
            "Kaydı kaldır?", confirmation: $deleteConfirmation, confirmTitle: "Kaydı kaldır"
        ) { _ in
            Task { await save(remove: true) }
        }
        .frame(minWidth: 300, minHeight: 250)
    }
    private func save(remove: Bool = false) async {
        if await model.save(remove: remove), model.dayModel.errorText == nil { dismiss() }
    }
}
