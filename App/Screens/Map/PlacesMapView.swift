import MapKit
import SwiftUI

struct PlacesMapView: View {
    let store: IndexStore
    @Environment(LocationService.self) private var location
    @Environment(\.locale) private var locale
    @State private var camera = MapCameraPosition.automatic
    @State private var selected: EntitySummary?
    @State private var showsUser = false
    private var pins: [PlacePin] { PlacesMapModel.pins(places: store.mapPlaces, usage: store.entityUsage) }
    var body: some View {
        // Pinned manşet above the full-bleed map; its row carries the page's icons.
        VStack(alignment: .leading, spacing: 0) {
            InkPageTitle("Harita", byline: String(localized: "\(store.content.entities.filter { $0.kind == "place" }.count) konum · \(pins.reduce(0) { $0 + $1.count }) ziyaret", locale: locale)) {
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
        .inkGlow()
        .task { location.refreshAuthorization() }
        .onChange(of: location.lastFix) { if showsUser { centerUser() } }
        .onChange(of: store.vaultURL) {
            selected = nil
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
                            selected = store.content.entities.first { $0.id == pin.id }
                        } label: {
                            placeMarker(pin: pin, isSelected: selected?.id == pin.id)
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
                        HStack(spacing: 10) {
                            ForEach(pins) { pin in
                                PlaceMapCard(store: store, pin: pin, isSelected: selected?.id == pin.id) {
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
    private func centerUser() {
        if let point = location.currentCoordinate {
            camera = .region(
                MKCoordinateRegion(
                    center: coordinate(point), span: MKCoordinateSpan(latitudeDelta: 0.02, longitudeDelta: 0.02)))
        }
    }
}

private struct PlaceMapCard: View {
    let store: IndexStore
    let pin: PlacePin
    let isSelected: Bool
    let onTap: () -> Void
    @Environment(\.locale) private var locale
    @Environment(\.clockNow) private var clockNow
    @State private var mentionData: EntityMentionsData?
    private var lastDate: CalendarDate? { store.entityUsage.first { $0.file == pin.id }?.lastDate }

    var body: some View {
        Button(action: onTap) {
            VStack(alignment: .leading, spacing: 8) {
                Text(verbatim: pin.entity.name).font(.ink.content).foregroundStyle(.ink.text)
                HStack(alignment: .center) {
                    VStack(alignment: .leading, spacing: 3) {
                        Text(String(localized: "\(pin.count) ziyaret", locale: locale)).font(.ink.meta).foregroundStyle(.ink.secondaryText)
                        if let lastDate {
                            Text(String(localized: "Son ziyaret", locale: locale) + " " + LocalDay.instant(for: lastDate).formatted(.dateTime.day().month(.abbreviated).locale(locale)))
                                .font(.ink.meta).foregroundStyle(.ink.secondaryText)
                        }
                    }
                    Spacer(minLength: 8)
                    if let mentionData { EntityMonthlyBarChart(data: mentionData, compact: true) }
                }
            }
            .frame(minWidth: 220, alignment: .leading)
            .padding(12)
            .background(Color.ink.surface)
            .clipShape(RoundedRectangle(cornerRadius: InkCorner.card))
            .overlay(RoundedRectangle(cornerRadius: InkCorner.card)
                .stroke(isSelected ? Color.ink.accent : Color.ink.rule,
                        lineWidth: isSelected ? InkStroke.control : InkStroke.hairline(scale: 1)))
        }
        .buttonStyle(.plain)
        .accessibilityLabel(Text(verbatim: pin.entity.name))
        .task(id: EntityTimelineRequest(path: pin.id, updated: store.lastUpdated)) {
            guard let days = try? await store.computeEntityTimeline(for: pin.id), !Task.isCancelled else { return }
            let insight = EntityInsights.compute(
                path: pin.id, timeline: days, lastDay: nil, entities: [], today: LocalDay.today(at: clockNow()))
            mentionData = insight.mentions(locale: locale)
        }
    }
}
