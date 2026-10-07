import SwiftUI
import VaultFormat

/// Edit mode: field, alias and rename editors inside a sheet. Each editor saves its own value.
struct EntityEditSheet: View {
    let store: IndexStore
    let model: EntityDetailModel
    let entity: EntitySummary
    @Environment(\.dismiss) private var dismiss
    @State private var newKey = ""
    @State private var newValue = ""
    @State private var renamePresented = false
    @State private var draft = EntityEditorDraft()
    @State private var leavePrompt = false

    private var addFieldDirty: Bool {
        !newKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            || !newValue.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private var isDirty: Bool { draft.isDirty || addFieldDirty }

    private var blocksLeave: Bool {
        UnsavedDraftDecision.requiresPrompt(isDirty: isDirty, isSaving: model.isWriting)
    }

    private var definitions: [EntityTypeField] {
        store.entityTypes.allTypes.first { $0.id == entity.kind }?.fields ?? []
    }

    var body: some View {
        NavigationStack {
            ScrollViewReader { proxy in
                List {
                    InkPageTitleRow("Düzenle")
                    if let error = model.errorText {
                        InfoBand(kind: .error, verbatim: error)
                            .id("entity-edit-error")
                            .inkListRow()
                    }
                    identityRows
                    if model.unreadableFrontmatter {
                        Text("Frontmatter okunamıyor.")
                            .font(.ink.meta)
                            .foregroundStyle(.ink.secondaryText)
                            .inkListRow()
                    } else {
                        aliasRows
                        if entity.kind == "place" { coordinateRows }
                        fieldRows
                    }
                }
                .listStyle(.plain)
                .onChange(of: model.errorText) { _, error in
                    guard error != nil else { return }
                    withAnimation { proxy.scrollTo("entity-edit-error", anchor: .top) }
                }
            }
            // Every editor row writes its own field; the sheet itself has nothing to confirm,
            // so its single button closes it (after the unsaved-text prompt).
            .inkSheet("Düzenle", closeIdentifier: "button.entity.edit.close", onClose: requestLeave)
            .navigationBarBackButtonHidden(blocksLeave)
            .interactiveDismissDisabled(blocksLeave || model.isWriting)
            .confirmationDialog("Kaydedilmemiş değişiklikler", isPresented: $leavePrompt) {
                Button("At", role: .destructive) { dismiss() }
                Button("Vazgeç", role: .cancel) {}
            } message: {
                Text("Kaydedilmemiş alan metni var.")
            }
            .sheet(isPresented: $renamePresented) {
                EntityRenameView(
                    model: EntityRenameModel(detail: model, name: entity.name, qualifier: entity.qualifier))
            }
        }
        .environment(\.entityEditorDraft, draft)
    }

    @ViewBuilder private var identityRows: some View {
        SectionHeader("Varlık")
            .inkListRow()
        labeledRow("Ad", entity.name)
            .inkListRow()
        if let qualifier = entity.qualifier {
            labeledRow("Ayırt edici", qualifier)
                .inkListRow()
        }
        Button("Adı değiştir") { renamePresented = true }
            .buttonStyle(InkTextButtonStyle())
            .disabled(!model.canEdit)
            .inkListRow()
    }

    @ViewBuilder private var aliasRows: some View {
        SectionHeader("Takma adlar")
            .inkListRow()
        if model.aliasesEditable {
            EntityAliasesEditor(model: model).id(model.aliases)
                .inkListRow()
        } else {
            Text(verbatim: model.aliasesSource)
                .font(.ink.content)
                .foregroundStyle(.ink.text)
                .textSelection(.enabled)
                .inkListRow()
            Text("Takma ad alanı salt okunur.")
                .font(.ink.meta)
                .foregroundStyle(.ink.secondaryText)
                .inkListRow()
        }
    }

    @ViewBuilder private var coordinateRows: some View {
        SectionHeader("Koordinat")
            .inkListRow()
        PlaceCoordinateEditor(model: model)
            .id(model.coordinate.map { [$0.latitude, $0.longitude] })
            .inkListRow()
    }

    /// A place's `coordinates` has its own editor; only a raw value stays in the generic rows.
    private func hasOwnEditor(_ field: EntityField) -> Bool {
        guard entity.kind == "place", field.key == "coordinates" else { return false }
        if case .raw = field.value { return false }
        return true
    }

    @ViewBuilder private var fieldRows: some View {
        let definitions = definitions.filter { entity.kind != "place" || $0.key != "coordinates" }
        SectionHeader("Alanlar")
            .inkListRow()
        ForEach(definitions, id: \.key) { definition in
            let value = model.fields.first { $0.key == definition.key }
            if EntityTypedField.supports(value?.value, kind: definition.kind) {
                EntityTypedFieldEditor(
                    definition: definition, value: value?.value, model: model
                )
                .id(definition.key + String(describing: value?.value))
                .inkListRow()
            } else if let value {
                EntityFieldEditor(field: value, model: model).id(value.value)
                    .inkListRow()
            }
        }
        ForEach(
            model.fields.filter { field in
                !definitions.contains { $0.key == field.key } && !hasOwnEditor(field)
            }
        ) { field in
            EntityFieldEditor(field: field, model: model).id(field.value)
                .inkListRow()
        }
        VStack(alignment: .leading, spacing: InkSpacing.section) {
            InkFilterField("Alan adı", text: $newKey)
            InkFilterField("Değer", text: $newValue)
            Button("Alan ekle") {
                let key = newKey
                let value = newValue
                Task {
                    if await model.addField(key: key, text: value), newKey == key,
                        newValue == value
                    {
                        newKey = ""
                        newValue = ""
                    }
                }
            }
            .buttonStyle(InkTextButtonStyle())
        }
        .disabled(!model.canEdit)
        .inkListRow()
    }

    private func labeledRow(_ label: LocalizedStringKey, _ value: String) -> some View {
        HStack(alignment: .firstTextBaseline) {
            Text(label)
                .font(.ink.meta)
                .foregroundStyle(.ink.secondaryText)
            Spacer(minLength: 12)
            Text(verbatim: value)
                .font(.ink.content)
                .foregroundStyle(.ink.text)
                .multilineTextAlignment(.trailing)
        }
    }

    private func requestLeave() {
        if UnsavedDraftDecision.canLeaveImmediately(isDirty: isDirty, isSaving: model.isWriting) {
            dismiss()
        } else {
            leavePrompt = true
        }
    }
}
