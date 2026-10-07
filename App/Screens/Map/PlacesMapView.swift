import MapKit
import SwiftUI

struct PlacesMapView: View {
    let store: IndexStore
    @Environment(LocationService.self) private var location
    @State private var camera = MapCameraPosition.automatic
    @State private var selected: EntitySummary?
    @State private var showsUser = false
    private var pins: [PlacePin] { PlacesMapModel.pins(places: store.mapPlaces, usage: store.entityUsage) }
    var body: some View {
        // Pinned manşet above the full-bleed map; its row carries the page's icons.
        VStack(alignment: .leading, spacing: 0) {
            InkPageTitle("Harita") {
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
