import GoalTracking
import SwiftUI

struct GoalCreationView: View {
    @State private var model: GoalCreationModel
    @Environment(\.dismiss) private var dismiss

    init(store: IndexStore) { _model = State(initialValue: GoalCreationModel(store: store)) }

    var body: some View {
        @Bindable var model = model
        List {
            InkPageTitleRow("Yeni hedef")
            Section {
                SectionHeader("Hedef")
                    .inkListRow()
                TextField("Ad", text: $model.name)
                    .font(.ink.content)
                    .inkListRow()
                LabeledContent("Anahtar") {
                    Text(verbatim: model.key)
                        .font(.ink.meta)
                        .foregroundStyle(Color.ink.secondaryText)
                }
                .inkListRow()
            }
            Section {
                SectionHeader("Ayarlar")
                    .inkListRow()
                if model.kind != .milestone {
                    InkLabeledMenu(
                        "Dönem", selection: $model.period,
                        options: [GoalPeriod.day, .week, .year].map {
                            InkMenuOption(verbatim: $0.title, value: $0)
                        }
                    )
                    .inkListRow()
                }
                InkLabeledMenu(
                    "Tür", selection: $model.kind,
                    options: [GoalKind.boolean, .number, .milestone].map {
                        InkMenuOption(verbatim: $0.title, value: $0)
                    }
                )
                .inkListRow()
                if model.kind != .milestone {
                    LabeledContent("Hedef miktar") {
                        TextField("Hedef miktar", text: $model.target)
                            .font(.ink.value)
                            .labelsHidden()
                            .multilineTextAlignment(.trailing)
                            #if os(iOS)
                                .keyboardType(.decimalPad)
                            #endif
                    }
                    .inkListRow()
                }
                if model.kind == .number {
                    TextField("Birim (isteğe bağlı)", text: $model.unit)
                        .font(.ink.content)
                        .inkListRow()
                }
            }
            if let error = model.errorText {
                Section {
                    InfoBand(kind: .error, verbatim: error)
                        .inkListRow()
                }
            }
        }
        .listStyle(.plain)
        .inkPageColumn()
        .disabled(model.isWriting || model.isSaved)
        .inkSheet(
            "Yeni hedef", confirm: .create, isConfirmEnabled: model.canSave, isBusy: model.isWriting,
            onConfirm: { Task { if await model.save(), model.errorText == nil { dismiss() } } }
        )
        .frame(minWidth: 320, minHeight: 350)
    }
}
