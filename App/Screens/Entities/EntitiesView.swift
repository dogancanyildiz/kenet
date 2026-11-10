import Summaries
import SwiftUI
import VaultFormat
import VaultIndex
import VaultStore

/// The phone combines people, places and the vault's custom types behind one type picker.
struct EntitiesView: View {
    let store: IndexStore
    @State private var editingEntity: EntitySummary?
    /// Every row's last encounter, 12-month days and relation count, read once for the list.
    @State private var activity: [String: EntityListActivity] = [:]
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
            // Şafak drawing: the filter sits right under the type tabs, above the page cards.
            EntityFilterField(search: $search)
                .inkListRow()
            // Side by side; stacked at accessibility text sizes (docs/screens.md).
            (dynamicTypeSize.isAccessibilitySize
                ? AnyLayout(VStackLayout(spacing: 10)) : AnyLayout(HStackLayout(alignment: .top, spacing: 12))) {
                    let peopleCount = store.content.entities.filter { $0.kind == "person" }.count
                    let placeCount = store.content.entities.filter { $0.kind == "place" }.count
                    pageCard(
                        "Graph", detail: String(localized: "\(peopleCount) kişi · \(placeCount) konum", locale: locale),
                        systemImage: "point.3.connected.trianglepath.dotted", page: .graph
                    )
                    pageCard(
                        "Harita", detail: String(localized: "\(store.mapPlaces.count) konum", locale: locale),
                        systemImage: "map", page: .map
                    )
                }
                .inkListRow()
            actionRow
            if kind == "person" {
                UnseenPeopleSection(
                    store: store, people: entities, initiallyExpanded: initialUnseenExpanded)
            }
            let rows = entities
            if !rows.isEmpty {
                SectionHeader(title: currentPlural, count: rows.count)
                    .inkListRow()
            }
            // Each entity is its own card (Şafak "kartlı liste"); the row opens the entity page
            // without a list disclosure arrow.
            ForEach(rows) { entity in
                Button {
                    openedEntity = entity
                } label: {
                    EntityRow(
                        entity: entity, store: store, activity: activity[entity.id],
                        onEdit: { editingEntity = entity }
                    )
                    .padding(.vertical, 8)
                    .padding(.horizontal, 12)
                    .frame(minHeight: 56)
                    .modifier(InkCardModifier(cornerRadius: InkCorner.md))
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .inkListRow()
            }
            if !store.content.entities.contains(where: { $0.kind == kind }) {
                EmptyState("Bu tipteki varlıklar burada görünecek.")
                    .inkListRow()
            }
        }
        .listStyle(.plain)
        .inkPageScrollColumn()
        .entityListActivity(store: store, into: $activity)
        .inkGlow()
        .inkPage()
        .inkRootPageNavigationTitle("Kişiler ve Konumlar")
        .accessibilityIdentifier("screen.entities")
        #if os(iOS)
            .contactImportFlow(store: store, showsPicker: $showsContactPicker)
        #endif
        .entityDefinitionActions(store: store, editing: $editingEntity)
        .entityCreateSheet(store: store, kind: $creationKind) { createdEntity = $0 }
        // The picker shows the type just added.
        .entityTypeGallerySheet(isPresented: $showsTypeGallery, store: store) { kind = $0.id }
        .navigationDestination(item: $createdEntity) { entity in
            EntityView(store: store, entity: entity)
        }
        .navigationDestination(item: $openedEntity) { entity in
            EntityView(store: store, entity: entity)
        }
        .navigationDestination(item: $openedPage) { page in
            switch page {
            case .graph: GraphView(store: store)
            case .map: PlacesMapView(store: store)
            }
        }
        .navigationDestination(for: EntitySummary.self) { entity in
            EntityView(store: store, entity: entity)
        }
    }

    @Environment(\.locale) private var locale
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @State private var showsTypeGallery = false
    @State private var openedEntity: EntitySummary?
    @State private var openedPage: EntitiesPage?

    /// The section title over the cards: the selected type's plural ("Kişiler", "Konumlar", "Kitaplar").
    private var currentPlural: String {
        EntityTypeChoices.choices(store.entityTypes, language: locale.language.languageCode?.identifier ?? "en")
            .first { $0.id == kind }?.plural ?? kind
    }

    /// One action row (Şafak drawing "+ Yeni kişi"): the create button, then a "…" menu with
    /// "Rehberden aktar" (people, iPhone) and "Yeni tip…", so the list starts on the first screen.
    private var actionRow: some View {
        HStack(spacing: 12) {
            if let creatable = EntityCreateEntry.kind(forList: kind, types: store.entityTypes) {
                Button {
                    creationKind = creatable
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
                // Two controls share the list row: each keeps its own tap.
                .buttonStyle(.borderless)
                .disabled(!store.canAddEvent)
                .accessibilityIdentifier(EntityCreateEntry.identifier(creatable))
            }
            Spacer(minLength: 0)
            Menu {
                #if os(iOS)
                    if ContactImportEntry.isShown(forList: kind) {
                        Button {
                            showsContactPicker = true
                        } label: {
                            ContactImportEntry.label
                        }
                        .disabled(!store.canAddEvent)
                        .accessibilityIdentifier(ContactImportEntry.identifier)
                    }
                #endif
                Button {
                    showsTypeGallery = true
                } label: {
                    Label("Yeni tip…", systemImage: EntityTypeGalleryEntry.systemImage)
                }
                .disabled(!EntityTypeGalleryEntry.isEnabled(store))
                .accessibilityIdentifier(EntityTypeGalleryEntry.identifier)
            } label: {
                Label("Diğer eylemler", systemImage: "ellipsis")
                    .labelStyle(.iconOnly)
                    .foregroundStyle(.ink.accent)
                    .tapTarget()
            }
            .buttonStyle(.borderless)
            .accessibilityIdentifier("menu.entities.more")
        }
        .inkListRow()
    }

    /// A page entry at the top of the list: icon box, name and short count, glow-tinted card
    /// (Şafak drawing). A button, not a list `NavigationLink`, so no disclosure arrow is drawn.
    private func pageCard(
        _ title: LocalizedStringKey, detail: String, systemImage: String, page: EntitiesPage
    ) -> some View {
        Button {
            openedPage = page
        } label: {
            VStack(alignment: .leading, spacing: 10) {
                Image(systemName: systemImage)
                    .font(.body)
                    .foregroundStyle(.ink.text)
                    .frame(width: iconBox, height: iconBox)
                    .background(
                        Color.ink.surface.opacity(0.6),
                        in: RoundedRectangle(cornerRadius: InkCorner.sm, style: .continuous)
                    )
                    .overlay {
                        RoundedRectangle(cornerRadius: InkCorner.sm, style: .continuous)
                            .stroke(Color.ink.rule, lineWidth: 1)
                    }
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 2) {
                    Text(title).font(.body.weight(.semibold)).foregroundStyle(.ink.text)
                    Text(verbatim: detail).font(.caption).foregroundStyle(.ink.secondaryText)
                }
            }
            .frame(maxWidth: .infinity, minHeight: 96, alignment: .topLeading)
            .padding(12)
            .background {
                RoundedRectangle(cornerRadius: InkCorner.card, style: .continuous)
                    .fill(Color.ink.accentSoft.opacity(0.5))
            }
            .modifier(InkCardModifier(cornerRadius: InkCorner.card))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.isButton)
    }

    @ScaledMetric(relativeTo: .body) private var iconBox: CGFloat = 36
}

/// The two page cards at the top of the list.
enum EntitiesPage: Hashable {
    case graph, map
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
    var store: IndexStore? = nil
    /// The list's bulk read for this row (`IndexStore.computeEntityListActivity`); nil draws the
    /// name only (rows outside the people/places lists).
    var activity: EntityListActivity? = nil
    var onEdit: () -> Void = {}
    var onDeleted: (String) -> Void = { _ in }
    @State private var deletion = DefinitionDeletionModel()
    @Environment(\.locale) private var locale
    @Environment(\.clockNow) private var clockNow

    private var lastDate: CalendarDate? { activity?.lastEncounter }
    private var relationCount: Int { activity?.relationCount ?? 0 }

    private var mentionData: EntityMentionsData? {
        activity?.mentions(today: LocalDay.today(at: clockNow()), locale: locale)
    }

    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    /// "iş · Son görüşme 3 gün önce · 9 bağ": the qualifier joins the meta line.
    private var rowMeta: String? {
        let meta = EntityRowPresentation.meta(
            kind: entity.kind, lastDate: lastDate, links: relationCount,
            today: LocalDay.today(at: clockNow()), locale: locale)
        let parts = [entity.qualifier, meta].compactMap { $0 }
        return parts.isEmpty ? nil : parts.joined(separator: " · ")
    }

    var body: some View {
        // One row view: the error band below the row, not a second row with the same tag.
        VStack(alignment: .leading, spacing: 0) {
            // Şafak list row: badge, name and one meta line, the 12-month mini bar on the right.
            HStack(alignment: .center, spacing: 12) {
                EntityInitialBadge(entity: entity)
                VStack(alignment: .leading, spacing: 2) {
                    Text(verbatim: entity.name)
                        .font(.subheadline)
                        .foregroundStyle(.ink.text)
                        .lineLimit(dynamicTypeSize.isAccessibilitySize ? nil : 1)
                    if let meta = rowMeta {
                        Text(verbatim: meta)
                            .font(.footnote)
                            .foregroundStyle(.ink.secondaryText)
                            .lineLimit(dynamicTypeSize.isAccessibilitySize ? nil : 1)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                // Never-mentioned entities have no bar (docs/screens.md, Liste satırı).
                if lastDate != nil, let mentionData {
                    EntityMonthlyBarChart(data: mentionData, compact: true)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .contextMenu {
                if let store {
                    DefinitionMenuButtons(items: DefinitionMenu.items(forEntity: entity), canEdit: store.canAddEvent) {
                        item in
                        switch item {
                        case .edit: onEdit()
                        case .copyLink: DefinitionMenu.copyLink(for: entity.name)
                        case .delete:
                            deletion = DefinitionDeletionModel()
                            deletion.request(path: entity.id)
                        default: break
                        }
                    }
                }
            }
            .destructiveConfirmationDialog(
                "Varlığı sil", confirmation: $deletion.confirmation,
                message: "\(entity.name) silinsin mi? Günlük kayıtlarındaki geçişler kalır."
            ) { path in
                guard let store else { return }
                Task {
                    if await deletion.delete(store: store, path: path, goal: false) { onDeleted(path) }
                }
            }
            if let error = deletion.errorText {
                InfoBand(kind: .error, verbatim: error)
            }
        }
    }
}

/// Loads the people/places list's per-row activity in one query when the index or the day changes.
private struct EntityListActivityLoader: ViewModifier {
    let store: IndexStore
    @Binding var activity: [String: EntityListActivity]
    @Environment(\.clockNow) private var clockNow

    func body(content: Content) -> some View {
        let today = LocalDay.today(at: clockNow())
        content.task(id: LastEncountersRequest(asOf: today, updated: store.lastUpdated)) {
            guard let loaded = try? await store.computeEntityListActivity(today: today), !Task.isCancelled
            else { return }
            activity = loaded
        }
    }
}

extension EntityListActivity {
    /// The row's 12-month bar; nil for a never-mentioned entity.
    func mentions(today: CalendarDate, locale: Locale) -> EntityMentionsData? {
        guard let lastEncounter else { return nil }
        let density = EntityMentionDensity.compute(days: recentDays + [lastEncounter], today: today)
        return EntityInsights.presentationMentions(density: density, locale: locale)
    }
}

extension View {
    func entityListActivity(store: IndexStore, into activity: Binding<[String: EntityListActivity]>) -> some View {
        modifier(EntityListActivityLoader(store: store, activity: activity))
    }
}

/// Tür renkli baş harf rozeti: tinted circle with up to two initials ("BT"), person or place
/// colour (custom types use person).
private struct EntityInitialBadge: View {
    let entity: EntitySummary
    @Environment(\.locale) private var locale
    @ScaledMetric(relativeTo: .body) private var side: CGFloat = 40

    private var tint: Color { entity.kind == "place" ? Color.ink.place : Color.ink.person }

    var body: some View {
        Text(verbatim: EntityInitials.of(entity.name, locale: locale))
            .font(.footnote.weight(.bold))
            .foregroundStyle(tint)
            .lineLimit(1)
            .minimumScaleFactor(0.7)
            .frame(width: side, height: side)
            .background(tint.opacity(0.2), in: Circle())
            .accessibilityHidden(true)
    }
}

/// Up to two initials from the first two words; locale-aware ("ilker" → "İ" in Turkish).
enum EntityInitials {
    static func of(_ name: String, locale: Locale) -> String {
        name.split(whereSeparator: { $0.isWhitespace }).prefix(2)
            .compactMap { $0.first.map { String($0).uppercased(with: locale) } }
            .joined()
    }
}

/// The row's meta line: "Son görüşme 3 gün önce · 14 bağ" ("Son ziyaret" for places).
enum EntityRowPresentation {
    static func meta(
        kind: String, lastDate: CalendarDate?, links: Int, today: CalendarDate, locale: Locale
    ) -> String? {
        let bundle = PresentationLocalization.bundle(locale)
        var parts: [String] = []
        if let lastDate, lastDate.ordinal <= today.ordinal {
            let formatter = RelativeDateTimeFormatter()
            formatter.locale = locale
            formatter.dateTimeStyle = .named
            formatter.unitsStyle = .full
            let relative = formatter.localizedString(from: DateComponents(day: lastDate.ordinal - today.ordinal))
            parts.append(
                kind == "place"
                    ? String(localized: "Son ziyaret \(relative)", bundle: bundle, locale: locale)
                    : String(localized: "Son görüşme \(relative)", bundle: bundle, locale: locale))
        }
        if links > 0 || !parts.isEmpty {
            parts.append(String(localized: "\(links) bağ", bundle: bundle, locale: locale))
        }
        return parts.isEmpty ? nil : parts.joined(separator: " · ")
    }
}
