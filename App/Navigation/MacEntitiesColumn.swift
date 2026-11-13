import SwiftUI
import VaultFormat
import VaultIndex
import VaultStore

/// Kişiler / Konumlar list column: manşet with the sort icon, kind tabs, filter and the list.
struct MacEntitiesColumn: View {
    let store: IndexStore
    /// Manşet for a custom kind, which has no sidebar row of its own.
    let sectionTitle: LocalizedStringKey
    @Binding var kind: String
    @Binding var order: EntityOrdering
    @Binding var search: String
    @Binding var selection: String?
    var unseenReveal: UUID? = nil
    @State private var creationKind: VaultEntityKind?
    @State private var showsTypeGallery = false
    #if os(iOS)
        @State private var showsContactPicker = false
    #endif

    var body: some View {
        VStack(spacing: 0) {
            if store.entityTypes.issue != nil {
                Text(
                    "Varlık tipleri okunamıyor. Yalnız yerleşik tipler kullanılıyor. Kasadaki .app/types.json dosyasını kontrol et."
                )
                .font(.ink.meta)
                .foregroundStyle(Color.ink.warning)
                .padding()
            }
            InkPageTitle(title) {
                EntitySortMenu(order: $order)
            }
            .macListColumnTitle()
            EntityTypePicker(store: store, selection: $kind)
                .padding(.horizontal, InkSpacing.margin)
                .padding(.bottom, InkSpacing.section)
            // Şafak drawing: the filter right under the kind tabs, then one action row.
            EntityFilterField(search: $search)
                .padding(.horizontal, InkSpacing.margin)
                .padding(.bottom, 4)
            EntityActionRow(
                store: store, kind: kind, create: { creationKind = $0 },
                importContacts: {
                    #if os(iOS)
                        showsContactPicker = true
                    #endif
                },
                newType: { showsTypeGallery = true }
            )
            .padding(.horizontal, InkSpacing.margin)
            .padding(.bottom, 4)
            MacEntityList(
                store: store,
                entities: EntityListQuery.entities(
                    in: store.content, usage: store.entityUsage, kind: kind, search: search, order: order),
                showsUnseen: kind == "person", unseenReveal: unseenReveal, selection: $selection)
        }
        // The new entity opens in the detail column like a row the user picked.
        .entityCreateSheet(store: store, kind: $creationKind) { selection = $0.id }
        // The kind tabs show the type just added.
        .entityTypeGallerySheet(isPresented: $showsTypeGallery, store: store) { kind = $0.id }
        #if os(iOS)
            .contactImportFlow(store: store, showsPicker: $showsContactPicker)
        #endif
    }

    /// The manşet follows the kind tab, which can differ from the sidebar row.
    private var title: LocalizedStringKey {
        switch kind {
        case "person": "Kişiler"
        case "place": "Konumlar"
        default: sectionTitle
        }
    }
}
