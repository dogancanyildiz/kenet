import EntityRecognition
import Foundation
import VaultFormat

struct PlaceCoordinate: Equatable, Sendable {
    let latitude: Double
    let longitude: Double
    var isValid: Bool {
        latitude.isFinite && longitude.isFinite && (-90...90).contains(latitude) && (-180...180).contains(longitude)
    }
}

struct NearbyPlace: Equatable, Sendable {
    let entity: KnownEntity
    let coordinate: PlaceCoordinate
    let radius: Double
    let hasExplicitRadius: Bool

    init?(entity: KnownEntity, document: RawDocument) {
        guard entity.kind == .place, case .parsed(let fields) = document.frontmatter,
            case .list(let values, _) = fields.field(named: "coordinates")?.value,
            values.count == 2, values.allSatisfy({ $0.kind == .number }),
            let latitude = Double(values[0].text), let longitude = Double(values[1].text)
        else { return nil }
        let coordinate = PlaceCoordinate(latitude: latitude, longitude: longitude)
        guard coordinate.isValid else { return nil }
        var radius = 100.0
        if let field = fields.field(named: "radius") {
            guard case .scalar(let value) = field.value, value.kind == .number,
                let number = Double(value.text), number.isFinite, number > 0
            else { return nil }
            radius = number
        }
        self.entity = entity
        self.coordinate = coordinate
        self.radius = radius
        hasExplicitRadius = fields.field(named: "radius") != nil
    }
}

enum NearbyPlaces {
    static func distance(from first: PlaceCoordinate, to second: PlaceCoordinate) -> Double {
        let radians = Double.pi / 180
        let latitude = (second.latitude - first.latitude) * radians
        let longitude = (second.longitude - first.longitude) * radians
        let a =
            pow(sin(latitude / 2), 2)
            + cos(first.latitude * radians) * cos(second.latitude * radians) * pow(sin(longitude / 2), 2)
        return 6_371_000 * 2 * asin(sqrt(min(1, max(0, a))))
    }

    static func nearest(to coordinate: PlaceCoordinate, among places: [NearbyPlace]) -> NearbyPlace? {
        guard coordinate.isValid else { return nil }
        return places.compactMap { place -> (NearbyPlace, Double)? in
            let meters = distance(from: coordinate, to: place.coordinate)
            return meters <= place.radius ? (place, meters) : nil
        }.min {
            $0.1 == $1.1 ? $0.0.entity.file < $1.0.entity.file : $0.1 < $1.1
        }?.0
    }
}
