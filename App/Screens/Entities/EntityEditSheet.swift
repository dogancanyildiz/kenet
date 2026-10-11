import Summaries
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
                        if entity.kind == "person" { PersonCadenceEditor(model: model) }
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
            .id(model.coordinatesSource)
            .inkListRow()
    }

    /// A place's `coordinates` has its own editor, which also shows a value it cannot use.
    private func hasOwnEditor(_ field: EntityField) -> Bool {
        entity.kind == "place" && field.key == "coordinates"
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

enum CadenceMenuValue: Hashable {
    case none
    case days(Int)
    case custom

    static let presets = [7, 14, 30, 60, 90]

    static func selection(for days: Int?) -> Self {
        guard let days else { return .none }
        return presets.contains(days) ? .days(days) : .custom
    }
}

/// What the rhythm editor holds before "Kaydet". Nothing here writes.
struct CadenceDraft: Equatable {
    enum Outcome: Equatable {
        case unchanged
        case clear
        case set(Int)
        case invalid
    }

    var choice: CadenceMenuValue
    var customText: String
    /// The valid day count in the file; nil for a missing field and for a value the app ignores.
    private(set) var savedDays: Int?

    init(days: Int?) {
        savedDays = days
        choice = CadenceMenuValue.selection(for: days)
        customText = choice == .custom ? (days.map(String.init) ?? "") : ""
    }

    private var customSpelling: String { customText.trimmingCharacters(in: .whitespacesAndNewlines) }

    /// What "Kaydet" does. A draft equal to the file writes nothing, so "Yok" over an ignored
    /// spelling (`cadence_days: aylık`) leaves that line alone; only a chosen number replaces it.
    var outcome: Outcome {
        let target: Int?
        switch choice {
        case .none: target = nil
        case .days(let days): target = days
        case .custom:
            guard let days = PersonCadence.positiveDays(spelling: customSpelling) else { return .invalid }
            target = days
        }
        if target == savedDays { return .unchanged }
        return target.map(Outcome.set) ?? .clear
    }

    /// An empty custom box holds nothing the close prompt could lose.
    var isDirty: Bool {
        if choice == .custom, customSpelling.isEmpty { return false }
        return outcome != .unchanged
    }

    /// Follows the file after a save or an outside change; unsaved input is kept.
    mutating func rebase(onto days: Int?) {
        savedDays = days
        if !isDirty { self = CadenceDraft(days: days) }
    }
}

/// Meeting rhythm for a person. Like every editor in the sheet it writes on "Kaydet" only.
private struct PersonCadenceEditor: View {
    let model: EntityDetailModel
    @Environment(\.entityEditorDraft) private var editorDraft
    @State private var draft: CadenceDraft
    @State private var invalid = false
    @State private var saveFailed = false

    private static let draftID = "cadence"

    init(model: EntityDetailModel) {
        self.model = model
        _draft = State(initialValue: CadenceDraft(days: model.personCadence.days))
    }

    private var options: [InkMenuOption<CadenceMenuValue>] {
        [
            InkMenuOption("Yok", value: .none),
            InkMenuOption("7 gün", value: .days(7)),
            InkMenuOption("14 gün", value: .days(14)),
            InkMenuOption("30 gün", value: .days(30)),
            InkMenuOption("60 gün", value: .days(60)),
            InkMenuOption("90 gün", value: .days(90)),
            InkMenuOption("Özel", value: .custom),
        ]
    }

    var body: some View {
        SectionHeader("Görüşme ritmi")
            .inkListRow()
        VStack(alignment: .leading, spacing: InkSpacing.section) {
            InkLabeledMenu(
                "Görüşme ritmi", selection: $draft.choice, options: options,
                identifier: "entity.cadence.menu")
            if draft.choice == .custom {
                InkFilterField("Gün sayısı", text: $draft.customText)
                    .onSubmit { save() }
            }
            Button("Kaydet") { save() }
                .buttonStyle(InkTextButtonStyle())
            if invalid {
                Text("Alan için geçerli bir değer gir.")
                    .font(.ink.meta)
                    .foregroundStyle(.ink.danger)
            } else if saveFailed {
                Text(
                    verbatim: model.errorText
                        ?? String(localized: "Değişiklik kaydedilemedi. Kasayı kontrol edip yeniden dene.")
                )
                .font(.ink.meta)
                .foregroundStyle(.ink.danger)
            }
        }
        .disabled(!model.canEdit)
        .inkListRow()
        .onAppear { editorDraft?.report(id: Self.draftID, dirty: draft.isDirty) }
        .onChange(of: draft) {
            invalid = false
            editorDraft?.report(id: Self.draftID, dirty: draft.isDirty)
        }
        .onChange(of: model.personCadence.days) { _, days in draft.rebase(onto: days) }
    }

    private func save() {
        let outcome = draft.outcome
        invalid = outcome == .invalid
        Task {
            switch outcome {
            case .unchanged, .invalid: return
            case .clear: saveFailed = !(await model.clearCadenceDays())
            case .set(let days): saveFailed = !(await model.setCadenceDays(days))
            }
            draft.rebase(onto: model.personCadence.days)
        }
    }
}
