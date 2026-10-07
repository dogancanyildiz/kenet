import SwiftUI
import VaultFormat

struct EntityView: View {
    let store: IndexStore
    let entity: EntitySummary
    let onRenamed: (String) -> Void
    @Environment(\.locale) private var locale
    @State private var model: EntityDetailModel
    @State private var isEditing = false

    init(store: IndexStore, entity: EntitySummary, onRenamed: @escaping (String) -> Void = { _ in }) {
        self.store = store
        self.entity = entity
        self.onRenamed = onRenamed
        _model = State(initialValue: EntityDetailModel(store: store, path: entity.id))
    }

    private var current: EntitySummary {
        if let current = store.content.entities.first(where: { $0.id == model.path }) { return current }
        guard let name = model.renamedName else { return entity }
        return EntitySummary(
            id: model.path, kind: entity.kind, name: name, qualifier: model.renamedQualifier,
            aliases: model.aliases, incomingLinks: 0)
    }

    private var kindLabel: String {
        EntityTypeChoices.choices(store.entityTypes, language: locale.language.languageCode?.identifier ?? "en")
            .first { $0.id == current.kind }?.name
            ?? current.kind
    }

    private var lastSeen: CalendarDate? {
        store.entityUsage.first { $0.file == model.path }?.lastDate
    }

    private var schemaKeys: Set<String> {
        Set(store.entityTypes.allTypes.first { $0.id == current.kind }?.fields.map(\.key) ?? [])
    }

    var body: some View {
        List {
            if !model.isLoaded {
                if model.errorText == nil {
                    ProgressView("Yükleniyor…")
                        .inkListRow()
                } else {
                    Button("Yeniden dene") { Task { await model.load() } }
                        .buttonStyle(InkTextButtonStyle())
                        .inkListRow()
                }
            } else {
                readingContent
            }
            if let error = model.errorText {
                Text(verbatim: error).font(.ink.meta).foregroundStyle(.ink.danger)
                    .inkListRow()
            }
        }
        .listStyle(.plain)
        .inkPage()
        .inkPageColumn()
        .environment(\.entityLookup, LinkedTextInk.lookup(entities: store.content.entities))
        // Manşet carries the name; keep the bar chrome compact (jury condition 4).
        .navigationTitle(current.name)
        #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
        #endif
        .toolbar {
            SearchButton()
            if model.isLoaded && model.canEdit {
                Button("Düzenle") { isEditing = true }
            }
        }
        .sheet(isPresented: $isEditing) {
            EntityEditSheet(store: store, model: model, entity: current)
        }
        .onChange(of: model.path) { _, path in onRenamed(path) }
        .task(id: store.lastUpdated) { await model.load() }
    }

    @ViewBuilder private var readingContent: some View {
        Section {
            PageHeadline(
                title: current.name,
                byline: EntityReadPresentation.byline(
                    kindLabel: kindLabel, aliases: model.aliases, lastSeen: lastSeen, locale: locale)
            )
            .inkListRow()
            if !model.aliasesEditable, !model.aliasesSource.isEmpty {
                Text(verbatim: model.aliasesSource)
                    .font(.ink.meta)
                    .foregroundStyle(.ink.secondaryText)
                    .textSelection(.enabled)
                    .inkListRow()
            }
            if let qualifier = current.qualifier {
                labeledRow(String(localized: "Ayırt edici"), qualifier, valueFont: .ink.content)
                    .inkListRow()
            }
            labeledRow(
                String(localized: "Gelen bağlantılar"),
                current.incomingLinks.formatted(.number),
                valueFont: .ink.value
            )
            .inkListRow()
            if let result = model.renameResult {
                EntityRenameSummary(result: result)
                    .inkListRow()
            }
        }
        if ["person", "place"].contains(current.kind) {
            Section {
                NavigationLink {
                    GraphView(store: store, focus: model.path)
                } label: {
                    Text("Graph'ta göster")
                        .font(.body)
                        .foregroundStyle(.ink.accent)
                }
                .inkListRow()
            }
            EntityInsightsCard(store: store, entity: current)
        }
        if model.unreadableFrontmatter {
            Section {
                Text("Frontmatter okunamıyor.")
                    .font(.ink.meta)
                    .foregroundStyle(.ink.secondaryText)
                    .inkListRow()
            }
        } else {
            fieldSections
        }
        EntityOpenTasksView(store: store, path: model.path).id(model.path)
        timelineSection
        notesSection
    }

    @ViewBuilder private var fieldSections: some View {
        let grouped = EntityReadPresentation.fieldRows(
            fields: model.fields, schemaKeys: schemaKeys, locale: locale)
        if !grouped.known.isEmpty {
            Section {
                SectionHeader(title: String(localized: "Alanlar"))
                    .inkListRow()
                ForEach(grouped.known) { row in
                    labeledRow(row.label, row.value.isEmpty ? "\u{2014}" : row.value, valueFont: .ink.content)
                        .inkListRow()
                }
            }
        }
        if !grouped.other.isEmpty {
            Section {
                SectionHeader(title: String(localized: "Diğer alanlar"))
                    .inkListRow()
                ForEach(grouped.other) { row in
                    VStack(alignment: .leading, spacing: 2) {
                        Text(verbatim: row.key)
                            .font(.ink.meta)
                            .foregroundStyle(.ink.secondaryText)
                        Text(verbatim: row.value.isEmpty ? "\u{2014}" : row.value)
                            .font(.ink.content)
                            .foregroundStyle(.ink.secondaryText)
                            .textSelection(.enabled)
                    }
                    .padding(.vertical, 2)
                    .inkListRow()
                }
            }
        }
    }

    @ViewBuilder private var timelineSection: some View {
        let timeline = store.content.entityTimeline[model.path] ?? []
        Section {
            SectionHeader(title: String(localized: "Zaman akışı"), count: timeline.count)
                .inkListRow()
            if timeline.isEmpty {
                Text("Henüz günlük kaydı yok.")
                    .font(.ink.meta)
                    .foregroundStyle(.ink.secondaryText)
                    .inkListRow()
            }
            ForEach(timeline) { day in
                Text(LocalDay.instant(for: day.date), format: .dateTime.day().month().year())
                    .font(.ink.section)
                    .foregroundStyle(.ink.text)
                    .inkListRow()
                ForEach(day.rows) { row in
                    NavigationLink {
                        DayView(store: store, date: day.date)
                    } label: {
                        LinkedTextView(text: row.text, store: store)
                    }
                    .inkListRow()
                }
            }
        }
    }

    @ViewBuilder private var notesSection: some View {
        Section {
            SectionHeader(title: String(localized: "Serbest notlar"))
                .inkListRow()
            let display = VaultDisplayText.multiline(model.body)
            if display.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                Text(verbatim: "\u{2014}")
                    .font(.ink.meta)
                    .foregroundStyle(.ink.secondaryText)
                    .inkListRow()
            } else {
                Text(verbatim: display)
                    .font(.ink.content)
                    .inkJournalParagraph()
                    .foregroundStyle(.ink.text)
                    .textSelection(.enabled)
                    .inkListRow()
            }
        }
    }

    private func labeledRow(_ label: String, _ value: String, valueFont: Font) -> some View {
        HStack(alignment: .firstTextBaseline) {
            Text(verbatim: label)
                .font(.ink.meta)
                .foregroundStyle(.ink.secondaryText)
            Spacer(minLength: 12)
            Text(verbatim: value)
                .font(valueFont)
                .foregroundStyle(.ink.text)
                .multilineTextAlignment(.trailing)
                .textSelection(.enabled)
        }
    }
}

/// Edit mode: reuses existing field / alias / rename editors inside a sheet.
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

    var body: some View {
        NavigationStack {
            ScrollViewReader { proxy in
                Form {
                    if let error = model.errorText {
                        Section {
                            InfoBand(kind: .error, verbatim: error)
                                .id("entity-edit-error")
                        }
                    }
                    Section("Varlık") {
                        LabeledContent("Ad") { Text(verbatim: entity.name) }
                        if let qualifier = entity.qualifier {
                            LabeledContent("Ayırt edici") { Text(verbatim: qualifier) }
                        }
                        Button("Adı değiştir") { renamePresented = true }.disabled(!model.canEdit)
                    }
                    if model.unreadableFrontmatter {
                        Text("Frontmatter okunamıyor.").foregroundStyle(.ink.secondaryText)
                    } else {
                        Section("Takma adlar") {
                            if model.aliasesEditable {
                                EntityAliasesEditor(model: model).id(model.aliases)
                            } else {
                                Text(verbatim: model.aliasesSource).textSelection(.enabled)
                                Text("Takma ad alanı salt okunur.").font(.ink.meta)
                            }
                        }
                        Section("Alanlar") {
                            let definitions = store.entityTypes.allTypes.first { $0.id == entity.kind }?.fields ?? []
                            ForEach(definitions, id: \.key) { definition in
                                let value = model.fields.first { $0.key == definition.key }
                                if EntityTypedField.supports(value?.value, kind: definition.kind) {
                                    EntityTypedFieldEditor(
                                        definition: definition, value: value?.value, model: model
                                    )
                                    .id(definition.key + String(describing: value?.value))
                                } else if let value {
                                    EntityFieldEditor(field: value, model: model).id(value.value)
                                }
                            }
                            ForEach(
                                model.fields.filter { field in !definitions.contains { $0.key == field.key } }
                            ) { field in
                                EntityFieldEditor(field: field, model: model).id(field.value)
                            }
                            VStack(alignment: .leading) {
                                TextField("Alan adı", text: $newKey)
                                TextField("Değer", text: $newValue)
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
                            }.disabled(!model.canEdit)
                        }
                    }
                }
                .formStyle(.grouped)
                .onChange(of: model.errorText) { _, error in
                    guard error != nil else { return }
                    withAnimation { proxy.scrollTo("entity-edit-error", anchor: .top) }
                }
            }
            .navigationTitle("Düzenle")
            .navigationBarBackButtonHidden(blocksLeave)
            .interactiveDismissDisabled(blocksLeave || model.isWriting)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Bitti") { requestLeave() }
                }
            }
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
        .inkPage()
    }

    private func requestLeave() {
        if UnsavedDraftDecision.canLeaveImmediately(isDirty: isDirty, isSaving: model.isWriting) {
            dismiss()
        } else {
            leavePrompt = true
        }
    }
}
