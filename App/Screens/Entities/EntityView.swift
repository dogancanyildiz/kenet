import SwiftUI

struct EntityView: View {
    let store: IndexStore
    let entity: EntitySummary
    let onRenamed: (String) -> Void
    @State private var model: EntityDetailModel
    @State private var renamePresented = false
    @State private var newKey = ""
    @State private var newValue = ""

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

    var body: some View {
        Form {
            if ["person", "place"].contains(current.kind) {
                Section { NavigationLink("Graph'ta göster") { GraphView(store: store, focus: model.path) } }
                EntityInsightsCard(store: store, entity: current)
            }
            Section("Varlık") {
                LabeledContent("Ad") { Text(verbatim: current.name) }
                if let qualifier = current.qualifier { LabeledContent("Ayırt edici") { Text(verbatim: qualifier) } }
                LabeledContent("Gelen bağlantılar") { Text(current.incomingLinks, format: .number) }
                Button("Adı değiştir") { renamePresented = true }.disabled(!model.canEdit)
                if let result = model.renameResult { EntityRenameSummary(result: result) }
            }
            if let error = model.errorText { Text(verbatim: error).foregroundStyle(.red).font(.caption) }
            if !model.isLoaded {
                if model.errorText == nil {
                    ProgressView("Yükleniyor…")
                } else {
                    Button("Yeniden dene") { Task { await model.load() } }
                }
            } else if model.unreadableFrontmatter {
                Text("Frontmatter okunamıyor.").foregroundStyle(.secondary)
            } else {
                Section("Takma adlar") {
                    if model.aliasesEditable {
                        EntityAliasesEditor(model: model).id(model.aliases)
                    } else {
                        Text(verbatim: model.aliasesSource).textSelection(.enabled)
                        Text("Takma ad alanı salt okunur.").font(.caption)
                    }
                }
                Section("Alanlar") {
                    let definitions = store.entityTypes.types.first { $0.id == current.kind }?.fields ?? []
                    ForEach(definitions, id: \.key) { definition in
                        let value = model.fields.first { $0.key == definition.key }
                        if EntityTypedField.supports(value?.value, kind: definition.kind) {
                            EntityTypedFieldEditor(definition: definition, value: value?.value, model: model)
                                .id(definition.key + String(describing: value?.value))
                        } else if let value {
                            EntityFieldEditor(field: value, model: model).id(value.value)
                        }
                    }
                    ForEach(model.fields.filter { field in !definitions.contains { $0.key == field.key } }) { field in
                        EntityFieldEditor(field: field, model: model).id(field.value)
                    }
                    VStack(alignment: .leading) {
                        TextField("Alan adı", text: $newKey)
                        TextField("Değer", text: $newValue)
                        Button("Alan ekle") {
                            let key = newKey
                            let value = newValue
                            Task {
                                if await model.addField(key: key, text: value), newKey == key && newValue == value {
                                    newKey = ""
                                    newValue = ""
                                }
                            }
                        }
                    }.disabled(!model.canEdit)
                }
            }
            EntityOpenTasksView(store: store, path: model.path).id(model.path)
            Section("Zaman akışı") {
                let timeline = store.content.entityTimeline[model.path] ?? []
                if timeline.isEmpty { Text("Henüz günlük kaydı yok.").foregroundStyle(.secondary) }
                ForEach(timeline) { day in
                    Text(LocalDay.instant(for: day.date), format: .dateTime.day().month().year()).font(.headline)
                    ForEach(day.rows) { row in
                        NavigationLink {
                            DayView(store: store, date: day.date)
                        } label: {
                            Text(verbatim: row.text.plainText)
                        }
                    }
                }
            }
            Section("Serbest notlar") {
                Text(verbatim: model.body).textSelection(.enabled)
            }
        }
        .formStyle(.grouped)
        .navigationTitle(current.name)
        .toolbar { SearchButton() }
        .sheet(isPresented: $renamePresented) {
            EntityRenameView(model: EntityRenameModel(detail: model, name: current.name, qualifier: current.qualifier))
        }
        .onChange(of: model.path) { _, path in onRenamed(path) }
        .task(id: store.lastUpdated) { await model.load() }
    }
}
