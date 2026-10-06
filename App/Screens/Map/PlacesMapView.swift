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
        Group {
            if pins.isEmpty {
                VStack(spacing: 8) {
                    EmptyState("Koordinatlı konum yok")
                    Text("Koordinat eklenen konumlar burada görünür.")
                        .font(.ink.meta)
                        .foregroundStyle(Color.ink.secondaryText)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, InkSpacing.margin)
                }
                .inkPage()
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
        .navigationTitle("Harita")
        .toolbar {
            Button("Beni göster", systemImage: "location") {
                showsUser = true
                location.requestLocationIfNeeded()
                centerUser()
            }.disabled(!location.authorization.canLocate || !location.isEnabled)
        }
        .task { location.refreshAuthorization() }
        .onChange(of: location.coordinate) { if showsUser { centerUser() } }
        .onChange(of: store.vaultURL) {
            selected = nil
            showsUser = false
            camera = .automatic
        }
        .sheet(item: $selected) { entity in
            NavigationStack {
                EntityView(store: store, entity: entity)
                    .toolbar {
                        Button("Kapat") { selected = nil }
                            .buttonStyle(InkTextButtonStyle())
                    }
            }
        }
    }

    private func placeMarker(pin: PlacePin, isSelected: Bool) -> some View {
        let side = pin.radius * 2
        return ZStack {
            GraphNodeShape(kind: .place)
                .fill(Color.ink.place.opacity(0.45 + pin.intensity * 0.55))
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
