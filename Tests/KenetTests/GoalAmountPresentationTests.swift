import GoalTracking
import Testing

@testable import Kenet

/// The number goal's amount rules: the card's "+" up to 20, the page's quick-add steps and
/// "Hedefe tamamla" (screens.md, Hedef ayrıntısı).
struct GoalAmountPresentationTests {
    private static func goal(_ kind: GoalKind, target: Double) -> GoalDefinition {
        GoalDefinition(
            id: "Goals/G.md", key: "g", name: "G", period: .day, kind: kind, target: target)!
    }

    @Test func plusAddsOneUpToTwentyThenPencil() {
        #expect(GoalAmountPresentation.usesQuickIncrement(Self.goal(.number, target: 8)))
        #expect(GoalAmountPresentation.usesQuickIncrement(Self.goal(.number, target: 20)))
        #expect(!GoalAmountPresentation.usesQuickIncrement(Self.goal(.number, target: 21)))
        #expect(!GoalAmountPresentation.usesQuickIncrement(Self.goal(.number, target: 7500)))
        // Yes/no goals keep their one-tap mark whatever the target.
        #expect(GoalAmountPresentation.usesQuickIncrement(Self.goal(.boolean, target: 30)))
    }

    /// Target → quick steps.
    static let stepCases: [(Double, [Double])] = [
        (7500, [500, 1000, 2500]),
        (10000, [500, 1000, 2500]),
        (8, [1, 2]),
        (20, [1, 2, 5]),
        (30, [2, 10]),
        (2, [1]),
        (1, [1]),
        (100, [5, 10, 25]),
        (1000, [50, 100, 250]),
        (21, [1, 2, 5]),
        (2.5, [1]),
        (0.5, [1]),
        (3, [1]),
    ]

    @Test(arguments: stepCases)
    func quickSteps(target: Double, expected: [Double]) {
        #expect(GoalAmountPresentation.quickSteps(target: target) == expected)
    }

    @Test func quickStepsAreWholeAscendingAndBelowTarget() {
        for target in stride(from: 2.0, through: 50_000, by: 37) {
            let steps = GoalAmountPresentation.quickSteps(target: target)
            #expect(!steps.isEmpty && steps.count <= 3)
            #expect(steps == steps.sorted())
            #expect(Set(steps).count == steps.count)
            #expect(steps.allSatisfy { $0 >= 1 && $0 == $0.rounded() && $0 < target })
        }
    }

    @Test func badTargetsGiveOne() {
        #expect(GoalAmountPresentation.quickSteps(target: 0) == [1])
        #expect(GoalAmountPresentation.quickSteps(target: .infinity) == [1])
    }

    @Test func completionAddsWhatThePeriodLacks() {
        // Daily: the day's value is the period's.
        #expect(GoalAmountPresentation.completionValue(dayValue: 3200, periodDone: 3200, target: 7500) == 7500)
        // Weekly: 30 of 50 km done, 5 of them today → today becomes 25.
        #expect(GoalAmountPresentation.completionValue(dayValue: 5, periodDone: 30, target: 50) == 25)
        #expect(GoalAmountPresentation.completionValue(dayValue: 8, periodDone: 8, target: 8) == nil)
        #expect(GoalAmountPresentation.completionValue(dayValue: 9, periodDone: 9, target: 8) == nil)
    }
}
