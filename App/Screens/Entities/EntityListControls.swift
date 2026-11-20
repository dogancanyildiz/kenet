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
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    private var actions: [EntityColumnAction] {
        EntityColumnAction.actions(forList: kind, types: store.entityTypes)
    }

    var body: some View {
        // The create button leading, the menu trailing. At accessibility sizes a narrow column
        // left the title less than a word ("New per- / son"): the menu then drops under it.
        LeadingTrailingRowLayout(spacing: 12, stacksWhenTight: dynamicTypeSize.isAccessibilitySize) {
            HStack(spacing: 12) {
                ForEach(actions, id: \.self) { action in
                    if case .create(let creatable) = action {
                        createButton(creatable)
                    }
                }
            }
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

/// Two subviews on one row: the first from the leading edge, the second at the trailing edge,
/// centred on each other. With `stacksWhenTight`, a row too narrow for both at their ideal
/// widths puts the second under the first, both from the leading edge, so the first keeps the
/// whole width for its text.
struct LeadingTrailingRowLayout: Layout {
    var spacing: CGFloat
    var stacksWhenTight: Bool

    private func isStacked(_ subviews: Subviews, width: CGFloat?) -> Bool {
        guard stacksWhenTight, subviews.count == 2, let width else { return false }
        let ideal = subviews.map { $0.sizeThatFits(.unspecified).width }
        return ideal[0] + spacing + ideal[1] > width
    }

    /// The sizes of the two subviews in a row `width` wide: the second at its ideal width, the
    /// first in what is left (stacked: each in the whole width).
    private func sizes(_ subviews: Subviews, width: CGFloat?, stacked: Bool) -> [CGSize] {
        guard subviews.count == 2 else { return subviews.map { $0.sizeThatFits(.unspecified) } }
        if stacked {
            return subviews.map { $0.sizeThatFits(ProposedViewSize(width: width, height: nil)) }
        }
        let trailing = subviews[1].sizeThatFits(.unspecified)
        let leading = subviews[0].sizeThatFits(
            ProposedViewSize(width: width.map { max(0, $0 - trailing.width - spacing) }, height: nil))
        return [leading, trailing]
    }

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let stacked = isStacked(subviews, width: proposal.width)
        let sizes = sizes(subviews, width: proposal.width, stacked: stacked)
        let widths = sizes.map(\.width)
        let heights = sizes.map(\.height)
        let content =
            stacked
            ? CGSize(width: widths.max() ?? 0, height: heights.reduce(0, +))
            : CGSize(
                width: widths.reduce(0, +) + spacing * CGFloat(max(0, sizes.count - 1)),
                height: heights.max() ?? 0)
        return CGSize(width: proposal.width ?? content.width, height: content.height)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        guard subviews.count == 2 else { return }
        let stacked = isStacked(subviews, width: bounds.width)
        let sizes = sizes(subviews, width: bounds.width, stacked: stacked)
        if stacked {
            subviews[0].place(
                at: bounds.origin, anchor: .topLeading,
                proposal: ProposedViewSize(width: bounds.width, height: sizes[0].height))
            subviews[1].place(
                at: CGPoint(x: bounds.minX, y: bounds.minY + sizes[0].height), anchor: .topLeading,
                proposal: ProposedViewSize(sizes[1]))
        } else {
            subviews[0].place(
                at: CGPoint(x: bounds.minX, y: bounds.midY), anchor: .leading, proposal: ProposedViewSize(sizes[0]))
            subviews[1].place(
                at: CGPoint(x: bounds.maxX, y: bounds.midY), anchor: .trailing, proposal: ProposedViewSize(sizes[1]))
        }
    }
}
