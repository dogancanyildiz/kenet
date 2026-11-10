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
            // Side by side; stacked at accessibility text sizes (docs/screens.md).
            (dynamicTypeSize.isAccessibilitySize
                ? AnyLayout(VStackLayout(spacing: 10)) : AnyLayout(HStackLayout(alignment: .top, spacing: 10))) {
                    let peopleCount = store.content.entities.filter { $0.kind == "person" }.count
                    let placeCount = store.content.entities.filter { $0.kind == "place" }.count
                    pageCard(
                        "Graph", detail: String(localized: "\(peopleCount) kişi · \(placeCount) konum", locale: locale),
                        systemImage: "point.3.connected.trianglepath.dotted"
                    ) {
                        GraphView(store: store)
                    }
                    pageCard(
                        "Harita", detail: String(localized: "\(store.mapPlaces.count) konum", locale: locale),
                        systemImage: "map"
                    ) {
                        PlacesMapView(store: store)
                    }
                }
                .inkListRow()
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
            // One list card drawn across the rows (first and last round, hairlines between), so
            // each entity stays its own lazy `List` row (docs/screens.md, Liste satırı).
            let rows = entities
            ForEach(Array(rows.enumerated()), id: \.element.id) { index, entity in
                NavigationLink(value: entity) {
                    EntityRow(
                        entity: entity, store: store, activity: activity[entity.id],
                        onEdit: { editingEntity = entity }
                    )
                    .padding(.vertical, 4)
                    .padding(.trailing, InkSpacing.cardPadding)
                }
                .buttonStyle(.plain)
                .inkListRow(cardSegment: .position(index, of: rows.count))
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
        .navigationDestination(for: EntitySummary.self) { entity in
            EntityView(store: store, entity: entity)
        }
    }

    @Environment(\.locale) private var locale
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
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
    private func pageCard<Destination: View>(
        _ title: LocalizedStringKey, detail: String, systemImage: String, @ViewBuilder destination: () -> Destination
    ) -> some View {
        NavigationLink {
            destination()
        } label: {
            InkCard {
                VStack(alignment: .leading, spacing: 8) {
                    Image(systemName: systemImage).foregroundStyle(.ink.accent)
                    Text(title).font(.ink.content).foregroundStyle(.ink.text)
                    Text(verbatim: detail).font(.ink.meta).foregroundStyle(.ink.secondaryText)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .buttonStyle(.plain)
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

    var body: some View {
        // One row view: the error band below the row, not a second row with the same tag.
        VStack(alignment: .leading, spacing: 0) {
            MarginRow(
                kind: .vault,
                mark: {
                    EntityInitialBadge(entity: entity)
                }, time: nil,
                primary: {
                    VStack(alignment: .leading, spacing: 3) {
                        Text(verbatim: entity.name).foregroundStyle(.ink.text)
                        if let qualifier = entity.qualifier {
                            Text(verbatim: qualifier).font(.ink.meta).foregroundStyle(.ink.secondaryText)
                        }
                    }
                },
                secondary: {
                    if let meta = EntityRowPresentation.meta(
                        kind: entity.kind, lastDate: lastDate, links: relationCount,
                        today: LocalDay.today(at: clockNow()), locale: locale)
                    {
                        Text(verbatim: meta).font(.ink.meta).foregroundStyle(.ink.secondaryText)
                    }
                },
                trailing: {
                    // Never-mentioned entities have no bar (docs/screens.md, Liste satırı).
                    if lastDate != nil, let mentionData {
                        EntityMonthlyBarChart(data: mentionData, compact: true)
                    }
                }
            )
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

/// Tür renkli baş harf rozeti: `well` circle, person or place colour (custom types use person).
private struct EntityInitialBadge: View {
    let entity: EntitySummary
    @Environment(\.locale) private var locale
    @ScaledMetric(relativeTo: .body) private var side: CGFloat = 36

    var body: some View {
        // Locale-aware: "ilker" → "İ" in Turkish.
        Text(verbatim: String(entity.name.prefix(1)).uppercased(with: locale))
            .font(.ink.section)
            .foregroundStyle(entity.kind == "place" ? Color.ink.place : Color.ink.person)
            .frame(width: side, height: side)
            .background(Color.ink.well, in: Circle())
            .accessibilityHidden(true)
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
