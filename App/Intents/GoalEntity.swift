import AppIntents
import Foundation

struct GoalEntity: AppEntity {
    static let typeDisplayRepresentation = TypeDisplayRepresentation(name: "Hedef")
    static let defaultQuery = GoalEntityQuery()
    let id: String
    let name: String
    var displayRepresentation: DisplayRepresentation { DisplayRepresentation(title: "\(name)") }
    init(_ goal: IntentGoal) {
        id = goal.id
        name = goal.definition.name
    }
}
struct GoalEntityQuery: EntityStringQuery {
    func entities(for identifiers: [GoalEntity.ID]) async throws -> [GoalEntity] {
        try await IntentActions.shared.throwIfLocked()
        let goals = try await IntentActions.shared.goals()
        return identifiers.compactMap { id in goals.first { $0.id == id }.map(GoalEntity.init) }
    }
    func suggestedEntities() async throws -> [GoalEntity] {
        try await IntentActions.shared.goals().map(GoalEntity.init)
    }
    func entities(matching string: String) async throws -> [GoalEntity] {
        let goals = try await IntentActions.shared.goals()
        return goals.filter { $0.definition.name.localizedCaseInsensitiveContains(string) }.map(GoalEntity.init)
    }
}
