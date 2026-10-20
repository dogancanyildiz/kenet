import CryptoKit
import Foundation
import GoalTracking
import VaultIndex

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
    /// - Parameter goals: the valid definitions with their resolved place files
    ///   (``IndexStore/computeGoalDefinitions()``).
    static func targets(
        goals: [GoalDefinitionRow], places: [NearbyPlace], vaultID: String,
        maximumRadius: Double = .infinity
    ) -> [GeofenceTarget] {
        let byFile = Dictionary(uniqueKeysWithValues: places.map { ($0.entity.file, $0) })
        return goals.sorted { $0.definition.id < $1.definition.id }.compactMap { row in
            let goal = row.definition
            guard goal.kind == .boolean, let file = row.placeFile, let place = byFile[file],
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
