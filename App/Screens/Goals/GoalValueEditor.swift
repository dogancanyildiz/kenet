import GoalTracking
import SwiftUI

struct GoalValueEditor: View {
    @Bindable var model: GoalValueModel
    @Environment(\.dismiss) private var dismiss
    @Environment(\.locale) private var locale
    @FocusState private var amountFocused: Bool
    @State private var deleteConfirmation = DestructiveConfirmation<DestructiveConfirmationToken>()

    var body: some View {
        List {
            InkPageTitleRow(
                verbatim: model.goal.name,
                byline: LocalDay.instant(for: model.dayModel.day)
                    .formatted(.dateTime.day().month().year().locale(locale)))
            Group {
                if model.goal.kind != .number {
                    Toggle("Yapıldı", isOn: $model.done)
                        .font(.ink.content)
                        .foregroundStyle(Color.ink.text)
                        .inkListRow()
                } else {
                    HStack(spacing: InkSpacing.row) {
                        Button {
                            model.step(-1)
                        } label: {
                            Label("Azalt", systemImage: "minus")
                                .labelStyle(.iconOnly)
                                .foregroundStyle(Color.ink.accent)
                                .tapTarget()
                        }
                        amountField
                        Button {
                            model.step(1)
                        } label: {
                            Label("Artır", systemImage: "plus")
                                .labelStyle(.iconOnly)
                                .foregroundStyle(Color.ink.accent)
                                .tapTarget()
                        }
                    }
                    // Inside a List row every bordered button fires on one tap.
                    .buttonStyle(.borderless)
                    .inkListRow()
                    LabeledContent("Hedef") {
                        Text(
                            verbatim: model.goal.target.formatted() + " " + (model.goal.unit ?? "")
                        )
                        .font(.ink.value)
                        .foregroundStyle(Color.ink.text)
                    }
                    .font(.ink.meta)
                    .foregroundStyle(Color.ink.secondaryText)
                    .inkListRow()
                    if model.value == nil {
                        Text("Sıfır veya pozitif bir sayı gir.")
                            .font(.ink.meta)
                            .foregroundStyle(Color.ink.secondaryText)
                            .inkListRow()
                    }
                }
                if let error = model.dayModel.errorText {
                    InfoBand(kind: .error, verbatim: error)
                        .inkListRow()
                }
                Button("Kaydı kaldır", role: .destructive) { deleteConfirmation.request(.pending) }
                    .buttonStyle(InkDestructiveButtonStyle())
                    .disabled(!model.dayModel.canEdit || model.isSaved)
                    .inkListRow()
            }
            .disabled(model.isSaved)
        }
        .listStyle(.plain)
        .inkSheet(
            verbatim: model.goal.name, isConfirmEnabled: model.canSave,
            onConfirm: { Task { await save() } }
        )
        .destructiveConfirmationDialog(
            "Kaydı kaldır?", confirmation: $deleteConfirmation, confirmTitle: "Kaydı kaldır"
        ) { _ in
            Task { await save(remove: true) }
        }
        .frame(minWidth: 300, minHeight: 250)
    }

    /// Well-backed amount field: same chrome as the page filter field, no system box.
    private var amountField: some View {
        TextField("Miktar", text: $model.amount)
            .textFieldStyle(.plain)
            .font(.ink.value)
            .foregroundStyle(Color.ink.text)
            .multilineTextAlignment(.center)
            #if os(iOS)
                .keyboardType(.decimalPad)
            #endif
            .focused($amountFocused)
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
            .background(
                Color.ink.well,
                in: RoundedRectangle(cornerRadius: InkSize.kanbanCorner, style: .continuous)
            )
            .overlay(
                RoundedRectangle(cornerRadius: InkSize.kanbanCorner, style: .continuous)
                    .strokeBorder(
                        InkButtonChrome.color(
                            for: InkFilterFieldChrome.borderToken(isFocused: amountFocused)),
                        lineWidth: InkStroke.control)
            )
    }

    private func save(remove: Bool = false) async {
        if await model.save(remove: remove), model.dayModel.errorText == nil { dismiss() }
    }
}
