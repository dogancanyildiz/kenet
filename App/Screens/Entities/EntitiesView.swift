import SwiftUI

/// The phone combines people, places and the vault's custom types behind one type picker.
struct EntitiesView: View {
    let store: IndexStore
    @State private var kind: String
    @State private var order: EntityOrdering
    @State private var search: String

    private let initialUnseenExpanded: Bool

    /// The initial values exist for previews and snapshots; the app starts on people, by name.
    init(
        store: IndexStore, initialKind: String = "person", initialOrder: EntityOrdering = .name,
        initialSearch: String = "", initialUnseenExpanded: Bool = false
    ) {
        self.store = store
        _kind = State(initialValue: initialKind)
        _order = State(initialValue: initialOrder)
        _search = State(initialValue: initialSearch)
        self.initialUnseenExpanded = initialUnseenExpanded
    }

    private var entities: [EntitySummary] {
        EntityListQuery.entities(in: store.content, usage: store.entityUsage, kind: kind, search: search, order: order)
    }

    var body: some View {
        List {
            InkPageTitleRow(verbatim: String(localized: "Kişiler ve Konumlar"), fitsOneLine: true) {
                EntitySortMenu(order: $order)
                SearchButton()
            }
            if store.entityTypes.issue != nil {
                InfoBand(
                    kind: .warning,
                    "Varlık tipleri okunamıyor. Yalnız yerleşik tipler kullanılıyor. Kasadaki .app/types.json dosyasını kontrol et."
                )
                .inkListRow()
            }
            EntityTypePicker(store: store, selection: $kind)
                .inkListRow()
            pageLink("Graph", systemImage: "point.3.connected.trianglepath.dotted") {
                GraphView(store: store)
            }
            pageLink("Harita", systemImage: "map") {
                PlacesMapView(store: store)
            }
            EntityFilterField(search: $search)
                .inkListRow()
            if kind == "person" {
                UnseenPeopleSection(
                    store: store, people: entities, initiallyExpanded: initialUnseenExpanded)
            }
            ForEach(entities) { entity in
                NavigationLink(value: entity) { EntityRow(entity: entity) }
                    .inkListRow()
            }
            if !store.content.entities.contains(where: { $0.kind == kind }) {
                EmptyState("Bu tipteki varlıklar burada görünecek.")
                    .inkListRow()
            }
        }
        .listStyle(.plain)
        .inkPage()
        .inkPageScrollColumn()
        .inkRootPageNavigationTitle("Kişiler ve Konumlar")
        .accessibilityIdentifier("screen.entities")
        .navigationDestination(for: EntitySummary.self) { entity in
            EntityView(store: store, entity: entity)
        }
    }

    /// A page entry at the top of the list (the pattern of the "Özetler" row in Günlük).
    private func pageLink<Destination: View>(
        _ title: LocalizedStringKey, systemImage: String, @ViewBuilder destination: () -> Destination
    ) -> some View {
        NavigationLink {
            destination()
        } label: {
            MarginRow(kind: .external, time: nil) {
                Label(title, systemImage: systemImage)
                    .font(.body)
                    .foregroundStyle(.ink.text)
            }
        }
        .inkListRow()
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
