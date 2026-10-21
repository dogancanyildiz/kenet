import Foundation
import GoalTracking
import Summaries
import Testing
import VaultFormat

struct GraceDaySummaryTests {
    @Test func endedPeriodUsesGraceAndKeepsContributionsUnchanged() throws {
        struct Fixture: Decodable {
            struct Expected: Decodable { let streak: Int }
            let start: String, sequence: String, summary: Bool
            let expected: Expected
        }
        let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
            .appendingPathComponent("../../../..", isDirectory: true).standardizedFileURL
        let fixtures =
            ProcessInfo.processInfo.environment["FIXTURES_DIR"].map { URL(fileURLWithPath: $0) }
            ?? root.appendingPathComponent("Fixtures")
        let cases = try JSONDecoder().decode(
            [Fixture].self, from: Data(contentsOf: fixtures.appendingPathComponent("goal-chain/cases.json")))
        let fixture = try #require(cases.first { $0.summary })
        let first = try #require(CalendarDate(fixture.start))
        let definition = try #require(
            GoalDefinition(id: "orbit", key: "orbit", name: "Orbit", period: .day, kind: .boolean))
        let logs = try fixture.sequence.enumerated().map { offset, symbol in
            GoalLog(day: try #require(first.addingDays(offset)), value: .boolean(symbol == "1"))
        }
        let data = SummaryInput(goals: [.init(definition: definition, logs: logs)])
        let summary = PeriodSummary.compute(
            period: .week, containing: CalendarDate("2026-09-20")!, data: data, today: CalendarDate("2026-10-01")!)
        let goal = try #require(summary.goals.first)
        #expect(goal.streak == fixture.expected.streak)
        #expect(goal.streakChange == 5)
        #expect(goal.contribution == 5)
        #expect(goal.progress.done == 5)
    }
}
