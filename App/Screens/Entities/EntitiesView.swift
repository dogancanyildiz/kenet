import SwiftUI

/// The phone combines people and places with a segmented filter.
struct EntitiesView: View {
    let store: IndexStore
    @State private var kind = "person"
    @State private var order = EntityOrdering.name
    @State private var search = ""

    private var entities: [EntitySummary] {
        EntityListQuery.entities(in: store.content, usage: store.entityUsage, kind: kind, search: search, order: order)
    }

    var body: some View {
        VStack(spacing: 0) {
            Picker("Varlık türü", selection: $kind) {
                Text("Kişiler").tag("person")
                Text("Konumlar").tag("place")
            }
            .pickerStyle(.segmented).padding()
            EntityListControls(order: $order, search: $search)
            List(entities) { entity in
                NavigationLink {
                    EntityView(store: store, entity: entity).id(entity.id)
                } label: {
                    EntityRow(entity: entity)
                }
            }
            .overlay {
                if !store.content.entities.contains(where: { $0.kind == kind }) {
                    ContentUnavailableView(
                        "Henüz varlık yok", systemImage: "person.2",
                        description: Text("Kişiler ve konumlar burada görünecek."))
                }
            }
        }
        .navigationTitle("Kişiler ve Konumlar")
        .toolbar { SearchButton() }
    }
}

struct EntityRow: View {
    let entity: EntitySummary

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(verbatim: entity.name)
            if let qualifier = entity.qualifier {
                Text(verbatim: qualifier).font(.subheadline).foregroundStyle(.secondary)
            }
        }
    }
}
