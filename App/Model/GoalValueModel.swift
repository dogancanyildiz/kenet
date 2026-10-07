import Foundation
import GoalTracking
import Observation

@MainActor @Observable
final class GoalValueModel: Identifiable {
    let id = UUID()
    let dayModel: GoalDayModel
    let goal: GoalDefinition
    var amount: String
    var done: Bool
    private(set) var isSaved = false
    var value: Double? { Self.number(amount) }
    var canSave: Bool { !isSaved && dayModel.canEdit && (goal.kind != .number || value != nil) }

    init(dayModel: GoalDayModel, goal: GoalDefinition) {
        self.dayModel = dayModel
        self.goal = goal
        if case .number(let value) = dayModel.value(for: goal) { amount = String(value) } else { amount = "0" }
        done = dayModel.value(for: goal) == .boolean(true)
    }

    static func number(_ text: String) -> Double? {
        guard
            let value = Double(
                text.trimmingCharacters(in: .whitespacesAndNewlines).replacingOccurrences(of: ",", with: ".")),
            value.isFinite, value >= 0
        else { return nil }
        return value
    }
    func step(_ delta: Double) { amount = String(max(0, (value ?? 0) + delta)) }
    func save(remove: Bool = false) async -> Bool {
        guard !isSaved, dayModel.canEdit, remove || canSave else { return false }
        let value: GoalValue? = remove ? nil : (goal.kind != .number ? (done ? .boolean(true) : nil) : .number(value!))
        isSaved = await dayModel.set(goal, value: value)
        return isSaved
    }
}
