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
                ContentUnavailableView(
                    "Koordinatlı konum yok", systemImage: "map",
                    description: Text("Koordinat eklenen konumlar burada görünür."))
            } else {
                Map(position: $camera) {
                    ForEach(pins) { pin in
                        Annotation(pin.entity.name, coordinate: coordinate(pin.coordinate)) {
                            Button {
                                selected = store.content.entities.first { $0.id == pin.id }
                            } label: {
                                Circle().fill(Color.accentColor.opacity(0.4 + pin.intensity * 0.6))
                                    .frame(width: pin.radius * 2, height: pin.radius * 2)
                                    .overlay { Text(pin.count.formatted()).font(.caption2).foregroundStyle(.white) }
                            }.buttonStyle(.plain).accessibilityLabel(Text(verbatim: pin.entity.name))
                        }
                    }
                    if showsUser, let point = location.currentCoordinate {
                        Annotation("Ben", coordinate: coordinate(point)) {
                            Circle().fill(.blue).frame(width: 14, height: 14).overlay {
                                Circle().stroke(.white, lineWidth: 2)
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
            NavigationStack { EntityView(store: store, entity: entity).toolbar { Button("Kapat") { selected = nil } } }
        }
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
