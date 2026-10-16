import SwiftUI
import VaultStore

/// The phone combines people, places and the vault's custom types behind one type picker.
struct EntitiesView: View {
    let store: IndexStore
    @State private var creationKind: VaultEntityKind?
    @State private var createdEntity: EntitySummary?
    @State private var kind: String
    @State private var order: EntityOrdering
    @State private var search: String
    #if os(iOS)
        @State private var showsContactPicker = false
        @State private var showsContactImport = false
        @State private var contactImportModel: ContactImportModel
    #endif

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
        #if os(iOS)
            _contactImportModel = State(initialValue: ContactImportModel(store: store))
        #endif
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
            if let creatable = EntityCreateEntry.kind(forList: kind) {
                createRow(creatable)
            }
            #if os(iOS)
                if kind == "person" {
                    contactImportRow
                }
            #endif
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
        .inkPageScrollColumn()
        .inkPage()
        .inkRootPageNavigationTitle("Kişiler ve Konumlar")
        .accessibilityIdentifier("screen.entities")
        #if os(iOS)
            .sheet(isPresented: $showsContactPicker) {
                ContactPicker(
                    onSelect: { candidates in
                        showsContactPicker = false
                        guard !candidates.isEmpty else { return }
                        contactImportModel.prepare(candidates: candidates)
                        Task { @MainActor in
                            showsContactImport = true
                        }
                    },
                    onCancel: {
                        showsContactPicker = false
                    }
                )
                .ignoresSafeArea()
            }
            .sheet(isPresented: $showsContactImport) {
                // The sheet bar ("Vazgeç" / "Kapat") is a toolbar: it needs the stack.
                NavigationStack {
                    ContactImportView(model: contactImportModel) {
                        showsContactImport = false
                        contactImportModel.cancel()
                    }
                }
            }
        #endif
        .entityCreateSheet(store: store, kind: $creationKind) { createdEntity = $0 }
        .navigationDestination(item: $createdEntity) { entity in
            EntityView(store: store, entity: entity)
        }
        .navigationDestination(for: EntitySummary.self) { entity in
            EntityView(store: store, entity: entity)
        }
    }

    /// "Yeni kişi" / "Yeni konum": a row like contact import, not a manşet symbol (a third
    /// symbol next to sort and search truncates the long title).
    private func createRow(_ creatable: VaultEntityKind) -> some View {
        Button {
            creationKind = creatable
        } label: {
            MarginRow(kind: .external, time: nil) {
                Label(EntityCreateEntry.title(creatable), systemImage: EntityCreateEntry.systemImage(creatable))
                    .font(.body)
                    .foregroundStyle(.ink.accent)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(!store.canAddEvent)
        .accessibilityIdentifier(EntityCreateEntry.identifier(creatable))
        .inkListRow()
    }

    #if os(iOS)
        /// Contact import stays a separate row below the page links (people only).
        private var contactImportRow: some View {
            Button {
                showsContactPicker = true
            } label: {
                MarginRow(kind: .external, time: nil) {
                    Label("Rehberden aktar", systemImage: "person.crop.circle.badge.plus")
                        .font(.body)
                        .foregroundStyle(.ink.accent)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .disabled(!store.canAddEvent)
            .accessibilityIdentifier("button.entities.importContacts")
            .inkListRow()
        }
    #endif

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
