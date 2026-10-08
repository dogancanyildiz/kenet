import EntityRecognition
import Foundation

struct MapPlace: Sendable {
    let entity: KnownEntity
    let coordinate: PlaceCoordinate
}
struct PlacePin: Identifiable, Sendable {
    let entity: KnownEntity
    let coordinate: PlaceCoordinate
    let count: Int
    let intensity: Double
    var id: String { entity.file }
    var radius: Double { 10 + min(14, sqrt(Double(max(0, count))) * 3) }
}
enum PlacesMapModel {
    static func pins(places: [MapPlace], usage: [EntityUsage]) -> [PlacePin] {
        let places = places.filter { $0.coordinate.isValid && $0.entity.kind == .place }
        let counts = Dictionary(uniqueKeysWithValues: usage.map { ($0.file, $0.totalCount) })
        let maximum = max(1, places.map { counts[$0.entity.file] ?? 0 }.max() ?? 0)
        return places.map {
            let count = max(0, counts[$0.entity.file] ?? 0)
            return PlacePin(
                entity: $0.entity, coordinate: $0.coordinate, count: count,
                intensity: Double(count) / Double(maximum))
        }.sorted { $0.id < $1.id }
    }

    /// Places the map cannot show yet, by name: the empty map offers them for editing.
    static func withoutCoordinates(entities: [KnownEntity], places: [MapPlace]) -> [KnownEntity] {
        let shown = Set(places.filter { $0.coordinate.isValid }.map(\.entity.file))
        return entities.filter { $0.kind == .place && !shown.contains($0.file) }.sorted {
            let order = $0.name.localizedStandardCompare($1.name)
            return order == .orderedSame ? $0.file < $1.file : order == .orderedAscending
        }
    }
}
