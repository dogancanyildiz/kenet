import GoalTracking
import SwiftUI

struct GoalCreationView: View {
    @State private var model: GoalCreationModel
    @Environment(\.dismiss) private var dismiss
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    init(store: IndexStore) { _model = State(initialValue: GoalCreationModel(store: store)) }

    private var stacksChrome: Bool { dynamicTypeSize.isAccessibilitySize }

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
                LabeledContent("Hedef miktar") {
                    TextField("Hedef miktar", text: $model.target)
                        .font(.ink.value)
                        .labelsHidden()
                        .multilineTextAlignment(.trailing)
                        #if os(iOS)
                            .keyboardType(.decimalPad)
                        #endif
                }
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
        .background(Color.ink.paper)
        .disabled(model.isWriting || model.isSaved)
        .navigationTitle("Yeni hedef")
        #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
        #endif
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button("Kapat") { dismiss() }
            }
            // AX sizes often fold confirmation into the overflow menu; keep it for medium type.
            if !stacksChrome {
                ToolbarItem(placement: .confirmationAction) {
                    createButton
                }
            }
        }
        .safeAreaInset(edge: .bottom) {
            if stacksChrome {
                createButton
                    .buttonStyle(InkPrimaryButtonStyle())
                    .padding(.horizontal, InkSpacing.margin)
                    .padding(.vertical, 10)
                    .frame(maxWidth: .infinity)
                    .background(Color.ink.paper)
            }
        }
        .frame(minWidth: 320, minHeight: 350)
    }

    private var createButton: some View {
        Button("Oluştur") {
            Task { if await model.save(), model.errorText == nil { dismiss() } }
        }
        .disabled(!model.canSave)
    }
}
