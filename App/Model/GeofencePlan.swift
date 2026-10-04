import CryptoKit
import Foundation
import GoalTracking

struct GeofenceRegion: Equatable, Sendable, Identifiable {
    static let prefix = "journal-geofence-"
    let id: String
    let coordinate: PlaceCoordinate
    let radius: Double
}

enum GeofenceMode: String, CaseIterable, Sendable { case off, notify, automatic }

struct GeofenceTarget: Identifiable, Sendable {
    let goal: GoalDefinition
    let place: NearbyPlace
    let region: GeofenceRegion
    var id: String { region.id }
}

enum GeofencePlan {
    static func vaultID(_ root: URL) -> String { digest(root.resolvingSymlinksInPath().standardizedFileURL.path) }
    static func digest(_ text: String) -> String {
        SHA256.hash(data: Data(text.utf8)).map { String(format: "%02x", $0) }.joined()
    }
    static func targets(
        snapshot: VaultReadModel, places: [NearbyPlace], vaultID: String,
        maximumRadius: Double = .infinity
    ) -> [GeofenceTarget] {
        let byFile = Dictionary(uniqueKeysWithValues: places.map { ($0.entity.file, $0) })
        return snapshot.goals.sorted { $0.id < $1.id }.compactMap { goal in
            guard goal.kind == .boolean, let file = snapshot.goalPlaceFiles[goal.id], let place = byFile[file],
                place.hasExplicitRadius
            else {
                return nil
            }
            let radius = min(place.radius, maximumRadius)
            let signature =
                "\(vaultID)|\(goal.id)|\(goal.key)|\(file)|\(place.coordinate.latitude)|\(place.coordinate.longitude)|\(radius)"
            return GeofenceTarget(
                goal: goal, place: place,
                region: GeofenceRegion(
                    id: GeofenceRegion.prefix + digest(signature), coordinate: place.coordinate, radius: radius))
        }
    }
}
