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
                TextField("Ad", text: $model.name)
                    .font(.ink.content)
                    .inkListRow()
            }
            if !templates.isEmpty {
                Section {
                    InkCard(padded: false) {
                        ForEach(Array(templates.enumerated()), id: \.element.id) { index, template in
                            if index > 0 { InkCardDivider() }
                            templateRow(template)
                                .padding(.horizontal, InkSpacing.cardPadding)
                        }
                    }
                    .inkListRow()
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
                if model.kind != .milestone {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Dönem")
                            .font(.ink.meta)
                            .foregroundStyle(Color.ink.secondaryText)
                            .accessibilityHidden(true)
                        InkTabs(
                            selection: $model.period,
                            items: [GoalPeriod.day, .week, .year].map {
                                InkTabItem(
                                    verbatim: GoalListPresentation.periodChip($0, locale: locale),
                                    value: $0)
                            },
                            identifier: "goal.create.period",
                            accessibilityLabelPrefix: String(localized: "Dönem")
                        )
                    }
                    .inkListRow()
                }
                VStack(alignment: .leading, spacing: 4) {
                    Text("Tür")
                        .font(.ink.meta)
                        .foregroundStyle(Color.ink.secondaryText)
                        .accessibilityHidden(true)
                    InkTabs(
                        selection: $model.kind,
                        items: [GoalKind.boolean, .number, .milestone].map {
                            InkTabItem(
                                verbatim: GoalListPresentation.kindTab($0, locale: locale),
                                value: $0)
                        },
                        identifier: "goal.create.kind",
                        accessibilityLabelPrefix: String(localized: "Tür")
                    )
                }
                .inkListRow()
                if model.kind != .milestone {
                    HStack(alignment: .firstTextBaseline, spacing: 12) {
                        VStack(alignment: .leading, spacing: 4) {
                            Text("Hedef miktar")
                                .font(.ink.meta)
                                .foregroundStyle(Color.ink.secondaryText)
                            TextField("Hedef miktar", text: $model.target)
                                .font(.ink.value)
                                #if os(iOS)
                                    .keyboardType(.decimalPad)
                                #endif
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        if model.kind == .number {
                            VStack(alignment: .leading, spacing: 4) {
                                Text("Birim")
                                    .font(.ink.meta)
                                    .foregroundStyle(Color.ink.secondaryText)
                                TextField("Birim (isteğe bağlı)", text: $model.unit)
                                    .font(.ink.content)
                            }
                            .frame(maxWidth: .infinity, alignment: .leading)
                        }
                    }
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
                        .font(.ink.content)
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
