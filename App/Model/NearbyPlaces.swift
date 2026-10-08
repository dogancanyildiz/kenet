import EntityRecognition
import Foundation
import VaultFormat

struct PlaceCoordinate: Equatable, Sendable {
    let latitude: Double
    let longitude: Double
    init(latitude: Double, longitude: Double) {
        self.latitude = latitude
        self.longitude = longitude
    }
    init?(document: RawDocument) {
        guard case .parsed(let fields) = document.frontmatter,
            case .list(let values, _) = fields.field(named: "coordinates")?.value,
            values.count == 2, values.allSatisfy({ $0.kind == .number }),
            let latitude = Double(values[0].text), let longitude = Double(values[1].text)
        else { return nil }
        self.init(latitude: latitude, longitude: longitude)
        guard isValid else { return nil }
    }
    var isValid: Bool {
        latitude.isFinite && longitude.isFinite && (-90...90).contains(latitude) && (-180...180).contains(longitude)
    }
}

/// Text the user types for a place's `coordinates` field, and the spelling written to the file.
enum PlaceCoordinateInput {
    /// A valid pair, or nil. Accepts a decimal comma and a typographic minus.
    static func coordinate(latitude: String, longitude: String) -> PlaceCoordinate? {
        guard let latitude = spelling(latitude).flatMap(Double.init),
            let longitude = spelling(longitude).flatMap(Double.init)
        else { return nil }
        let coordinate = PlaceCoordinate(latitude: latitude, longitude: longitude)
        return coordinate.isValid ? coordinate : nil
    }

    /// More fraction digits than a `Double` can hold are refused, not written.
    static let maximumFractionDigits = 15

    /// The typed number in the spelling the file accepts (`-?(0|[1-9][0-9]*)(\.[0-9]+)?`), with
    /// the digits the user gave; nil when it is not such a number or has too many fraction
    /// digits. A plus sign and leading zeros are dropped and a signed zero is `0`, the same
    /// spellings a measured position gets.
    static func spelling(_ text: String) -> String? {
        let text = text.trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: ",", with: ".").replacingOccurrences(of: "\u{2212}", with: "-")
        guard let match = text.wholeMatch(of: /([+-]?)0*([0-9]+)(\.([0-9]+))?/),
            (match.4?.count ?? 0) <= maximumFractionDigits
        else { return nil }
        let digits = String(match.2) + (match.3.map(String.init) ?? "")
        guard digits.contains(where: { $0 != "0" && $0 != "." }) else { return "0" }
        return (match.1 == "-" ? "-" : "") + digits
    }

    /// Plain decimal spelling with at most six fraction digits (about 0.1 m), never an exponent.
    static func text(_ value: Double) -> String {
        var text = String(format: "%.6f", locale: Locale(identifier: "en_US_POSIX"), value)
        while text.hasSuffix("0") { text.removeLast() }
        if text.hasSuffix(".") { text.removeLast() }
        return text == "-0" ? "0" : text
    }

    static func literals(_ coordinate: PlaceCoordinate) -> [FrontmatterLiteral] {
        [.number(text(coordinate.latitude)), .number(text(coordinate.longitude))]
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
