import SwiftUI

struct UnresolvedEntityView: View {
    let store: IndexStore
    @Environment(\.locale) private var locale
    @State private var model: UnresolvedEntityModel

    init(store: IndexStore, target: String) {
        self.store = store
        _model = State(initialValue: UnresolvedEntityModel(store: store, target: target))
    }

    var body: some View {
        @Bindable var model = model
        if let created = model.created {
            let entity =
                store.content.entities.first { $0.id == created.file }
                ?? EntitySummary(
                    id: created.file, kind: created.kind.rawValue, name: created.name, qualifier: created.qualifier,
                    aliases: [], incomingLinks: 0)
            EntityView(store: store, entity: entity).id(entity.id)
        } else {
            Form {
                Text("Bu ad için bir varlık oluştur.")
                TextField("Ad", text: $model.name)
                if model.needsQualifier {
                    TextField("Ayırt edici (ör. iş)", text: $model.qualifier)
                    Button("Oluştur") { if let kind = model.kind { Task { await model.create(kind) } } }
                        .disabled(model.qualifier.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                } else {
                    Button("Kişi olarak ekle") { Task { await model.create(.person) } }
                    Button("Konum olarak ekle") { Task { await model.create(.place) } }
                    ForEach(
                        EntityTypeChoices.choices(
                            store.entityTypes, language: locale.language.languageCode?.identifier ?? "en"
                        ).filter { $0.id != "person" && $0.id != "place" }
                    ) { type in
                        Button {
                            Task { await model.create(type.kind) }
                        } label: {
                            Text("\(type.name) olarak ekle")
                        }
                    }
                }
                if let error = model.errorText { Text(verbatim: error).foregroundStyle(.red) }
            }
            .disabled(model.isCreating || !store.canAddEvent)
            .navigationTitle("Bağlantı bulunamadı")
        }
    }
}
