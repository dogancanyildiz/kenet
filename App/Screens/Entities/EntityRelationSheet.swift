import SwiftUI
import VaultFormat

struct EntityRelationSheet: View {
    let model: EntityRelationsModel
    @Environment(\.dismiss) private var dismiss
    @State private var search = ""
    @State private var selected: EntitySummary?
    @State private var label = ""

    private var candidates: [EntitySummary] {
        let kinds = GraphInput.kinds.union(model.store.entityTypes.types.map(\.id))
        return kinds.sorted().flatMap {
            EntityListQuery.entities(
                in: model.store.content, usage: model.store.entityUsage,
                kind: $0, search: search, order: .name)
        }.filter { $0.id != model.path }
    }

    var body: some View {
        NavigationStack {
            List {
                InkPageTitleRow("Bağ kur")
                // Above the list: the confirm word sits in the bar, so a failed save is read here.
                if let error = model.sheetErrorText { InfoBand(kind: .error, verbatim: error).inkListRow() }
                // The optional label comes before the target list, which grows with the vault.
                InkFilterField("Etiket", text: $label, identifier: "field.relation.label", showsClearButton: false)
                    .inkListRow()
                ForEach(model.labels, id: \.self) { suggestion in
                    Button {
                        label = suggestion
                    } label: {
                        Text(verbatim: suggestion).font(.ink.meta)
                    }
                    .buttonStyle(InkTextButtonStyle())
                    .tapTarget()
                    .inkListRow()
                }
                InkFilterField("Varlık ara", text: $search, identifier: "field.entities.filter")
                    .autocorrectionDisabled()
                    .inkListRow()
                ForEach(candidates) { entity in
                    Button {
                        selected = entity
                    } label: {
                        HStack(alignment: .firstTextBaseline) {
                            Text(verbatim: entity.name + (entity.qualifier.map { " (" + $0 + ")" } ?? ""))
                                .fixedSize(horizontal: false, vertical: true)
                            Spacer()
                            if selected?.id == entity.id { Image(systemName: "checkmark").accessibilityHidden(true) }
                        }
                        .font(.ink.content)
                    }
                    .buttonStyle(InkTextButtonStyle())
                    .accessibilityAddTraits(selected?.id == entity.id ? .isSelected : [])
                    .accessibilityIdentifier("row.relationTarget." + entity.id)
                    .inkListRow()
                }
            }
            .listStyle(.plain)
            .inkPageScrollColumn()
            .disabled(model.isWriting)
            .inkSheet(
                "Bağ kur", confirm: .save, isConfirmEnabled: selected != nil && model.canWrite,
                isBusy: model.isWriting, isCancelEnabled: !model.isWriting,
                cancelIdentifier: "button.relation.cancel", confirmIdentifier: "button.relation.save"
            ) {
                guard let selected else { return }
                Task { if await model.save(target: selected, label: label) { dismiss() } }
            }
            .accessibilityIdentifier("sheet.relation")
            .interactiveDismissDisabled(model.isWriting)
            .task { await model.load() }
            .onDisappear { model.clearSheetError() }
        }
    }
}
