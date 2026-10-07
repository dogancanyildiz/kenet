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
            InkPageTitle("Kişiler ve Konumlar")
            if store.entityTypes.issue != nil {
                InfoBand(
                    kind: .warning,
                    "Varlık tipleri okunamıyor. Yalnız yerleşik tipler kullanılıyor. Kasadaki .app/types.json dosyasını kontrol et."
                )
            }
            EntityTypePicker(store: store, selection: $kind).padding()
            EntityListControls(order: $order, search: $search)
            List {
                if kind == "person" {
                    UnseenPeopleSection(store: store, people: entities)
                }
                ForEach(entities) { entity in
                    NavigationLink(value: entity) { EntityRow(entity: entity) }
                        .inkListRow()
                }
            }
            .listStyle(.plain)
            .inkPage()
            .overlay {
                if !store.content.entities.contains(where: { $0.kind == kind }) {
                    EmptyState("Bu tipteki varlıklar burada görünecek.")
                }
            }
        }
        .inkPage()
        .inkPageColumn()
        .inkPageNavigationTitle("Kişiler ve Konumlar")
        .accessibilityIdentifier("screen.entities")
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
        MarginRow(kind: .vault, time: nil) {
            Text(verbatim: entity.name)
                .foregroundStyle(.ink.text)
        } secondary: {
            if let qualifier = entity.qualifier {
                Text(verbatim: qualifier)
                    .font(.ink.meta)
                    .foregroundStyle(.ink.secondaryText)
            }
        }
    }
}
