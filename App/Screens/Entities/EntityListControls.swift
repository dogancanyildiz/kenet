import SwiftUI
import VaultFormat
import VaultStore

/// Sort order as a manşet-row icon; accent while the order differs from the default (by name).
struct EntitySortMenu: View {
    @Binding var order: EntityOrdering

    var body: some View {
        InkHeaderMenu(
            "Sıralama", systemImage: "arrow.up.arrow.down", isActive: order != .name,
            identifier: "button.entities.sort"
        ) {
            Picker("Sıralama", selection: $order) {
                Text("Ada göre").tag(EntityOrdering.name)
                Text("Son geçişe göre").tag(EntityOrdering.recent)
            }
            .pickerStyle(.inline)
        }
    }
}

/// In-page filter of the entity list: the Search page's field as a component.
struct EntityFilterField: View {
    @Binding var search: String

    var body: some View {
        InkFilterField("Süz", text: $search, identifier: "field.entities.filter")
            .autocorrectionDisabled()
    }
}

/// The actions of a Kişiler / Konumlar list, in the order the action row offers them.
enum EntityColumnAction: Hashable {
    /// "Yeni kişi", "Yeni konum" or "Yeni <tip>" for a custom type the vault defines.
    case create(VaultEntityKind)
    /// "Rehberden aktar": people only, and only on iOS (the Mac has no contact picker).
    case importContacts
    /// "Yeni tip…": the type gallery, under every kind.
    case newType

    static func actions(forList kind: String, types: EntityTypeCatalog) -> [Self] {
        var actions = EntityCreateEntry.kind(forList: kind, types: types).map { [Self.create($0)] } ?? []
        #if os(iOS)
            if ContactImportEntry.isShown(forList: kind) { actions.append(.importContacts) }
        #endif
        actions.append(.newType)
        return actions
    }
}

/// One action row (Şafak drawing "+ Yeni kişi"): the create button, then a "…" menu with
/// "Rehberden aktar" (people, iOS) and "Yeni tip…". The phone page and the split shell's
/// column (iPad, Mac) share it, so the list starts right under the filter.
struct EntityActionRow: View {
    let store: IndexStore
    let kind: String
    var create: (VaultEntityKind) -> Void
    var importContacts: () -> Void = {}
    var newType: () -> Void
    @Environment(\.locale) private var locale

    private var actions: [EntityColumnAction] {
        EntityColumnAction.actions(forList: kind, types: store.entityTypes)
    }

    var body: some View {
        HStack(spacing: 12) {
            ForEach(actions, id: \.self) { action in
                if case .create(let creatable) = action {
                    createButton(creatable)
                }
            }
            Spacer(minLength: 0)
            Menu {
                ForEach(actions, id: \.self) { action in
                    menuItem(action)
                }
            } label: {
                Label("Diğer eylemler", systemImage: "ellipsis")
                    .labelStyle(.iconOnly)
                    .foregroundStyle(.ink.accent)
                    .tapTarget()
            }
            .buttonStyle(.borderless)
            .menuIndicator(.hidden)
            .fixedSize()
            .accessibilityIdentifier("menu.entities.more")
        }
    }

    private func createButton(_ creatable: VaultEntityKind) -> some View {
        Button {
            create(creatable)
        } label: {
            HStack(spacing: 8) {
                Image(systemName: "plus").accessibilityHidden(true)
                Text(
                    verbatim: EntityCreateEntry.title(
                        creatable, types: store.entityTypes,
                        language: locale.language.languageCode?.identifier ?? "en"))
            }
            .font(.subheadline.weight(.semibold))
            .foregroundStyle(.ink.accent)
            .frame(minHeight: TapTarget.minimumLength)
            .contentShape(Rectangle())
        }
        // Two controls share the row (a list row on the phone): each keeps its own tap.
        .buttonStyle(.borderless)
        .disabled(!store.canAddEvent)
        .accessibilityIdentifier(EntityCreateEntry.identifier(creatable))
    }

    @ViewBuilder private func menuItem(_ action: EntityColumnAction) -> some View {
        switch action {
        case .create:
            EmptyView()
        case .importContacts:
            #if os(iOS)
                Button {
                    importContacts()
                } label: {
                    ContactImportEntry.label
                }
                .disabled(!store.canAddEvent)
                .accessibilityIdentifier(ContactImportEntry.identifier)
            #endif
        case .newType:
            Button {
                newType()
            } label: {
                Label("Yeni tip…", systemImage: EntityTypeGalleryEntry.systemImage)
            }
            .disabled(!EntityTypeGalleryEntry.isEnabled(store))
            .accessibilityIdentifier(EntityTypeGalleryEntry.identifier)
        }
    }
}
