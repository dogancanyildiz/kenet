import SwiftUI

struct EntityView: View {
    let store: IndexStore
    let entity: EntitySummary
    @State private var model: EntityDetailModel
    @State private var newKey = ""
    @State private var newValue = ""

    init(store: IndexStore, entity: EntitySummary) {
        self.store = store
        self.entity = entity
        _model = State(initialValue: EntityDetailModel(store: store, path: entity.id))
    }

    private var current: EntitySummary { store.content.entities.first { $0.id == entity.id } ?? entity }

    var body: some View {
        Form {
            Section("Varlık") {
                LabeledContent("Ad") { Text(verbatim: current.name) }
                if let qualifier = current.qualifier { LabeledContent("Ayırt edici") { Text(verbatim: qualifier) } }
                LabeledContent("Gelen bağlantılar") { Text(current.incomingLinks, format: .number) }
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
                    ForEach(model.fields) { field in
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
            Section("Zaman akışı") {
                let timeline = store.content.entityTimeline[entity.id] ?? []
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
        .task(id: store.lastUpdated) { await model.load() }
    }
}
