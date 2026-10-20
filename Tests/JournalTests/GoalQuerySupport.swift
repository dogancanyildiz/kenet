import Foundation
import GoalTracking
import VaultFormat
import VaultIndex

@testable import Journal

extension IndexStore {
    /// The valid goal definitions in the goal list's order, as the index has them now.
    func goalDefinitions() async throws -> [GoalDefinition] {
        try await computeGoalDefinitions().map(\.definition)
    }
}
