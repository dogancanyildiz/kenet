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
            List {
                if kind == "person" { UnseenPeopleSection(store: store, people: entities) }
                ForEach(entities) { entity in
                    NavigationLink(value: entity) { EntityRow(entity: entity) }
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
        .toolbar {
            SearchButton()
            NavigationLink {
                GraphView(store: store)
            } label: {
                Label("Graph", systemImage: "point.3.connected.trianglepath.dotted")
            }
            NavigationLink {
                PlacesMapView(store: store)
            } label: {
                Label("Harita", systemImage: "map")
            }
        }
        .navigationDestination(for: EntitySummary.self) { entity in
            EntityView(store: store, entity: entity)
        }
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
