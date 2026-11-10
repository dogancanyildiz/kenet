import MapKit
import SwiftUI
import VaultFormat
import VaultIndex

struct PlacesMapView: View {
    let store: IndexStore
    @Environment(LocationService.self) private var location
    @Environment(\.locale) private var locale
    @State private var camera = MapCameraPosition.automatic
    @State private var selected: EntitySummary?
    /// The pin picked from the cards: framed on the map; its card offers "Sayfayı aç".
    @State private var focused: String?
    /// Last visit, 12-month days per place, read once for all cards.
    @State private var activity: [String: EntityListActivity] = [:]
    @State private var showsUser = false
    private var pins: [PlacePin] { PlacesMapModel.pins(places: store.mapPlaces, usage: store.entityUsage) }
    var body: some View {
        // Pinned manşet above the full-bleed map; its row carries the page's icons.
        VStack(alignment: .leading, spacing: 0) {
            // Both counts from the pins drawn: places with a coordinate and their visits.
            InkPageTitle(
                "Harita",
                byline: String(
                    localized: "\(pins.count) konum · \(pins.reduce(0) { $0 + $1.count }) ziyaret", locale: locale)
            ) {
                InkHeaderAction("Beni göster", systemImage: "location") {
                    showsUser = true
                    location.requestLocationIfNeeded(userInitiated: true)
                    centerUser()
                }
                .disabled(!location.authorization.canLocate || !location.isEnabled)
                SearchButton()
            }
            content
        }
        .inkPageNavigationTitle("Harita")
        .entityListActivity(store: store, into: $activity)
        .task { location.refreshAuthorization() }
        .onChange(of: location.lastFix) { if showsUser { centerUser() } }
        .onChange(of: store.vaultURL) {
            selected = nil
            focused = nil
            showsUser = false
            camera = .automatic
        }
        .sheet(item: $selected) { entity in
            NavigationStack {
                EntityView(store: store, entity: entity)
                    .inkSheet(verbatim: entity.name, onClose: { selected = nil })
            }
        }
    }

    /// The user asked to be shown and a fix arrived: the map opens even without pins.
    private var showsUserPoint: Bool { showsUser && location.coordinate != nil }

    @ViewBuilder private var content: some View {
        if pins.isEmpty && !showsUserPoint {
            emptyContent
        } else {
            Map(position: $camera) {
                ForEach(pins) { pin in
                    Annotation(pin.entity.name, coordinate: coordinate(pin.coordinate)) {
                        Button {
                            focused = pin.id
                            selected = store.content.entities.first { $0.id == pin.id }
                        } label: {
                            placeMarker(pin: pin, isSelected: focused == pin.id)
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel(Text(verbatim: pin.entity.name))
                    }
                }
                if showsUser, let point = location.currentCoordinate {
                    Annotation("Ben", coordinate: coordinate(point)) {
                        Circle()
                            .fill(Color.ink.accent)
                            .frame(width: 14, height: 14)
                            .overlay {
                                Circle().stroke(Color.ink.paper, lineWidth: 2)
                            }
                    }
                }
            }
            .mapControls {
                MapCompass()
                MapScaleView()
            }
            .mapStyle(.standard(elevation: .flat, emphasis: .muted))
            .overlay(alignment: .bottom) {
                if !pins.isEmpty {
                    ScrollView(.horizontal) {
                        LazyHStack(spacing: 10) {
                            ForEach(pins) { pin in
                                PlaceMapCard(pin: pin, activity: activity[pin.id], isSelected: focused == pin.id) {
                                    focus(pin)
                                } onOpen: {
                                    selected = store.content.entities.first { $0.id == pin.id }
                                }
                            }
                        }
                        .padding(.horizontal, InkSpacing.margin)
                        .padding(.bottom, 12)
                    }
                }
            }
        }
    }

    /// Location permission never adds coordinates to a place, so the empty map says what is
    /// missing and opens the places that need it.
    @ViewBuilder private var emptyContent: some View {
        let missing = PlacesMapModel.withoutCoordinates(entities: store.knownEntities, places: store.mapPlaces)
        ScrollView {
            VStack(spacing: 8) {
                Group {
                    if missing.isEmpty {
                        EmptyState("Henüz konum yok")
                        Text("Eklediğin konumlar, koordinatı girilince haritada görünür.")
                    } else {
                        EmptyState("Konumlarında koordinat yok")
                        Text("Konum izni yalnız seni haritada gösterir; konumlara koordinat eklemez.")
                        Text("Bir konumu açıp Düzenle'den koordinatını gir.")
                    }
                }
                .font(.ink.meta)
                .foregroundStyle(Color.ink.secondaryText)
                .multilineTextAlignment(.center)
                ForEach(missing, id: \.file) { place in
                    Button {
                        selected = store.content.entities.first { $0.id == place.file }
                    } label: {
                        Text(verbatim: place.name).tapTarget()
                    }
                    .buttonStyle(InkTextButtonStyle())
                }
            }
            .padding(.horizontal, InkSpacing.margin)
        }
        .inkPage()
    }

    private func placeMarker(pin: PlacePin, isSelected: Bool) -> some View {
        let side = pin.radius * 2
        return ZStack {
            GraphNodeShape(kind: .place)
                .fill(Color.ink.place)
                .frame(width: side, height: side)
            if isSelected {
                GraphNodeShape(kind: .place)
                    .stroke(Color.ink.accent, lineWidth: InkStroke.highPriority)
                    .frame(width: side + 4, height: side + 4)
            }
            Text(pin.count.formatted())
                .font(.ink.meta)
                .foregroundStyle(Color.ink.paper)
                .monospacedDigit()
        }
        .frame(minWidth: 44, minHeight: 44)
    }

    private func coordinate(_ point: PlaceCoordinate) -> CLLocationCoordinate2D {
        CLLocationCoordinate2D(latitude: point.latitude, longitude: point.longitude)
    }
    /// A card picks its pin and brings it to the middle, keeping the current zoom when there is one.
    private func focus(_ pin: PlacePin) {
        focused = pin.id
        let span = camera.region?.span ?? MKCoordinateSpan(latitudeDelta: 0.05, longitudeDelta: 0.05)
        withAnimation { camera = .region(MKCoordinateRegion(center: coordinate(pin.coordinate), span: span)) }
    }

    private func centerUser() {
        if let point = location.currentCoordinate {
            camera = .region(
                MKCoordinateRegion(
                    center: coordinate(point), span: MKCoordinateSpan(latitudeDelta: 0.02, longitudeDelta: 0.02)))
        }
    }
}

private struct PlaceMapCard: View {
    let pin: PlacePin
    let activity: EntityListActivity?
    let isSelected: Bool
    let onTap: () -> Void
    let onOpen: () -> Void
    @Environment(\.locale) private var locale
    @Environment(\.clockNow) private var clockNow
    private var lastDate: CalendarDate? { activity?.lastEncounter }
    private var mentionData: EntityMentionsData? {
        activity?.mentions(today: LocalDay.today(at: clockNow()), locale: locale)
    }

    /// "23 ziyaret · son 19 Eyl"; without a mention only the count.
    private var visitLine: String {
        guard let lastDate else { return String(localized: "\(pin.count) ziyaret", locale: locale) }
        let date = LocalDay.instant(for: lastDate).formatted(.dateTime.day().month(.abbreviated).locale(locale))
        return String(localized: "\(pin.count) ziyaret · son \(date)", locale: locale)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Button(action: onTap) {
                VStack(alignment: .leading, spacing: 8) {
                    Text(verbatim: pin.entity.name).font(.ink.content).foregroundStyle(.ink.text)
                    HStack(alignment: .center) {
                        Text(verbatim: visitLine).font(.ink.meta).foregroundStyle(.ink.secondaryText)
                        Spacer(minLength: 8)
                        if lastDate != nil, let mentionData { EntityMonthlyBarChart(data: mentionData, compact: true) }
                    }
                }
                .frame(minHeight: TapTarget.minimumLength)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityElement(children: .combine)
            .accessibilityAddTraits(isSelected ? .isSelected : [])
            if isSelected {
                Button("Sayfayı aç", action: onOpen)
                    .buttonStyle(InkPrimaryButtonStyle())
            }
        }
        .frame(minWidth: 220, alignment: .leading)
        .padding(12)
        .modifier(InkCardModifier())
        .overlay {
            if isSelected {
                RoundedRectangle(cornerRadius: InkCorner.card, style: .continuous)
                    .stroke(Color.ink.accent, lineWidth: InkStroke.control)
            }
        }
    }
}
