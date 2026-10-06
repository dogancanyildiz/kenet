import GoalTracking
import VaultFormat

extension IndexStore {
    func setGoal(on day: CalendarDate, key: String, value: GoalValue?) async throws {
        try await performEdit(path: "journal/\(day).md") {
            try await $0.settingGoalValue(on: day, key: key, value: value)
        }
    }

    func createGoal(name: String, period: GoalPeriod, kind: GoalKind, target: Double, unit: String?) async throws {
        try await performEdit {
            [try await $0.creatingGoal(name: name, period: period, kind: kind, target: target, unit: unit)]
        }
    }
}
