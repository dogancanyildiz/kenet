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
            if let creatable = EntityCreateEntry.kind(forList: kind, types: store.entityTypes) {
                createRow(creatable)
            }
            #if os(iOS)
                if ContactImportEntry.isShown(forList: kind) {
                    contactImportRow
                }
            #endif
            newTypeRow
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
            .contactImportFlow(store: store, showsPicker: $showsContactPicker)
        #endif
        .entityCreateSheet(store: store, kind: $creationKind) { createdEntity = $0 }
        // The picker shows the type just added.
        .entityTypeGallerySheet(isPresented: $showsTypeGallery, store: store) { kind = $0.id }
        .navigationDestination(item: $createdEntity) { entity in
            EntityView(store: store, entity: entity)
        }
        .navigationDestination(for: EntitySummary.self) { entity in
            EntityView(store: store, entity: entity)
        }
    }

    @Environment(\.locale) private var locale
    @State private var showsTypeGallery = false

    /// "Yeni kişi" / "Yeni konum" / "Yeni <tip>": a row like contact import, not a manşet symbol
    /// (a third symbol next to sort and search truncates the long title).
    private func createRow(_ creatable: VaultEntityKind) -> some View {
        Button {
            creationKind = creatable
        } label: {
            MarginRow(kind: .external, time: nil) {
                Label(
                    EntityCreateEntry.title(
                        creatable, types: store.entityTypes,
                        language: locale.language.languageCode?.identifier ?? "en"),
                    systemImage: EntityCreateEntry.systemImage(creatable, types: store.entityTypes)
                )
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

    /// "Yeni tip…": always under the create rows; opens the gallery of ready-made types.
    private var newTypeRow: some View {
        Button {
            showsTypeGallery = true
        } label: {
            MarginRow(kind: .external, time: nil) {
                Label("Yeni tip…", systemImage: EntityTypeGalleryEntry.systemImage)
                    .font(.body)
                    .foregroundStyle(.ink.accent)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(!EntityTypeGalleryEntry.isEnabled(store))
        .accessibilityIdentifier(EntityTypeGalleryEntry.identifier)
        .inkListRow()
    }

    #if os(iOS)
        /// Contact import stays a separate row below the page links (people only).
        private var contactImportRow: some View {
            Button {
                showsContactPicker = true
            } label: {
                MarginRow(kind: .external, time: nil) {
                    ContactImportEntry.label
                        .font(.body)
                        .foregroundStyle(.ink.accent)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .disabled(!store.canAddEvent)
            .accessibilityIdentifier(ContactImportEntry.identifier)
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

#if os(iOS)
    /// "Rehberden aktar", people only: a row on the phone's Kişiler ve Konumlar page and a text
    /// button in the split shell's Kişiler column. The Mac has no contact picker.
    enum ContactImportEntry {
        static let identifier = "button.entities.importContacts"

        static var label: some View {
            Label("Rehberden aktar", systemImage: "person.crop.circle.badge.plus")
        }

        static func isShown(forList kind: String) -> Bool { kind == "person" }
    }

    extension View {
        /// The contact picker, then the import sheet with what was picked. Both entries to
        /// "Rehberden aktar" open this; `showsPicker` is the entry's tap.
        func contactImportFlow(store: IndexStore, showsPicker: Binding<Bool>) -> some View {
            modifier(ContactImportFlow(store: store, showsPicker: showsPicker))
        }
    }

    private struct ContactImportFlow: ViewModifier {
        @Binding var showsPicker: Bool
        @State private var showsImport = false
        @State private var model: ContactImportModel

        init(store: IndexStore, showsPicker: Binding<Bool>) {
            _showsPicker = showsPicker
            _model = State(initialValue: ContactImportModel(store: store))
        }

        func body(content: Content) -> some View {
            content
                .sheet(isPresented: $showsPicker) {
                    ContactPicker(
                        onSelect: { candidates in
                            showsPicker = false
                            guard !candidates.isEmpty else { return }
                            model.prepare(candidates: candidates)
                            Task { @MainActor in
                                showsImport = true
                            }
                        },
                        onCancel: {
                            showsPicker = false
                        }
                    )
                    .ignoresSafeArea()
                }
                .sheet(isPresented: $showsImport) {
                    // The sheet bar ("Vazgeç" / "Kapat") is a toolbar: it needs the stack.
                    NavigationStack {
                        ContactImportView(model: model) {
                            showsImport = false
                            model.cancel()
                        }
                    }
                }
        }
    }
#endif

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
