import GoalTracking
import SwiftUI

struct GoalCreationView: View {
    @State private var model: GoalCreationModel
    @Environment(\.locale) private var locale
    @Environment(\.dismiss) private var dismiss

    init(store: IndexStore) { _model = State(initialValue: GoalCreationModel(store: store)) }

    init(model: GoalCreationModel) { _model = State(initialValue: model) }

    private var templates: [GoalTemplate] {
        GoalTemplate.all.filter { GoalCreationModel.matches($0, query: model.name, locale: locale) }
    }

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
            }
            if !templates.isEmpty {
                Section {
                    SectionHeader("Hazır hedefler")
                        .inkListRow()
                    ForEach(templates) { template in
                        templateRow(template)
                            .inkListRow()
                    }
                }
            }
            Section {
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
        .inkPageScrollColumn()
        .disabled(model.isWriting || model.isSaved)
        .inkSheet(
            "Yeni hedef", confirm: .create, isConfirmEnabled: model.canSave, isBusy: model.isWriting,
            onConfirm: { Task { if await model.save(), model.errorText == nil { dismiss() } } }
        )
        .frame(minWidth: 320, minHeight: 350)
        .task(id: model.store.lastUpdated) { await model.load() }
    }

    private func templateRow(_ template: GoalTemplate) -> some View {
        let selected = model.templateID == template.id
        return Button {
            model.apply(template, locale: locale)
        } label: {
            HStack(spacing: 12) {
                Image(systemName: template.symbol)
                    .frame(width: InkSpacing.gutter)
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: InkSpacing.row) {
                    Text(verbatim: template.localizedName(locale: locale))
                        .font(.body)
                        .foregroundStyle(Color.ink.text)
                    Text(verbatim: template.summary(locale: locale))
                        .font(.ink.meta)
                        .foregroundStyle(Color.ink.secondaryText)
                }
                .multilineTextAlignment(.leading)
                .fixedSize(horizontal: false, vertical: true)
                Spacer(minLength: 0)
                if selected {
                    Image(systemName: "checkmark")
                        .foregroundStyle(Color.ink.accent)
                        .accessibilityHidden(true)
                }
            }
            .foregroundStyle(Color.ink.secondaryText)
            .frame(minHeight: 44)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(selected ? [.isSelected] : [])
        .accessibilityIdentifier("button.goal.template.\(template.id)")
    }
}
