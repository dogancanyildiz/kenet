import AppIntents
import Foundation

struct MarkGoalIntent: AppIntent {
    static let title: LocalizedStringResource = "Hedefi işaretle"
    static let openAppWhenRun = false
    @Parameter(title: "Hedef") var goal: GoalEntity
    @Parameter(title: "Miktar") var amount: Double?
    @MainActor
    func perform() async throws -> some IntentResult & ReturnsValue<String> & ProvidesDialog {
        let result = try await IntentActions.shared.markGoal(id: goal.id, amount: amount)
        return .result(value: result.text, dialog: IntentDialog(result.dialog))
    }
}
