import GoalTracking
import Testing
import VaultFormat

struct GoalBoundaryTests {
    @Test func invalidDefinitionsAndLogValues() {
        for target in [0, -1, Double.infinity, Double.nan] {
            #expect(GoalDefinition(id: "", key: "su", name: "Su", period: .day, kind: .number, target: target) == nil)
        }
        #expect(GoalDefinition(id: "", key: " ", name: "Su", period: .day, kind: .number, target: 1) == nil)
        #expect(!GoalValue.number(-1).isValid)
        #expect(!GoalValue.number(.infinity).isValid)
    }

    @Test func supportedDateBoundariesAndReversedHeatmap() throws {
        let definition = try #require(
            GoalDefinition(id: "", key: "su", name: "Su", period: .week, kind: .boolean, target: 1))
        let minimum = CalendarDate("0100-01-01")!
        let maximum = CalendarDate("9999-12-31")!
        #expect(GoalProgress.compute(definition: definition, logs: [], today: minimum).periodStart == minimum)
        #expect(GoalProgress.compute(definition: definition, logs: [], today: maximum).periodEnd == maximum)
        #expect(GoalProgress.heatmap(definition: definition, logs: [], from: maximum, to: minimum).isEmpty)
        #expect(
            GoalProgress.heatmap(definition: definition, logs: [], from: maximum, to: maximum)[maximum]
                == GoalDayMark.none)
        #expect(minimum.addingDays(Int.min) == nil)
        #expect(maximum.addingDays(Int.max) == nil)
        #expect(CalendarDate("2024-02-01")!.endOfMonth == CalendarDate("2024-02-29"))
        #expect(CalendarDate("2026-10-04")!.startOfWeek == CalendarDate("2026-09-28"))
        #expect(CalendarDate("2026-10-04")!.endOfWeek == CalendarDate("2026-10-04"))
    }

    @Test func invalidNumbersDoNotContributeAndTotalsRemainFinite() throws {
        let definition = try #require(
            GoalDefinition(
                id: "", key: "su", name: "Su", period: .year, kind: .number, target: Double.greatestFiniteMagnitude))
        let day = CalendarDate("2026-10-04")!
        let logs = [
            GoalLog(day: day, value: .number(.infinity)), GoalLog(day: day.addingDays(-1)!, value: .number(-2)),
        ]
        #expect(GoalProgress.compute(definition: definition, logs: logs, today: day).progress.done == 0)
        let large = [
            GoalLog(day: day, value: .number(.greatestFiniteMagnitude)),
            GoalLog(day: day.addingDays(-1)!, value: .number(.greatestFiniteMagnitude)),
        ]
        let status = GoalProgress.compute(definition: definition, logs: large, today: day)
        #expect(status.progress.done.isFinite)
        #expect(status.progress.isComplete)
        #expect(status.progress.fraction == 1)
    }
}
