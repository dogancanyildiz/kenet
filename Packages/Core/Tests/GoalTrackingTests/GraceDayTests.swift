import Foundation
import GoalTracking
import Testing
import VaultFormat

struct GraceCase: Decodable, Sendable {
    struct Expected: Decodable, Sendable {
        let streak: Int, longestStreak: Int, graceDaysAvailable: Int
        let score: Int?
        let graceSpentDays: [String]
        let isPendingToday: Bool
    }
    let id: String, start: String, sequence: String, period: String, kind: String
    let expected: Expected
}

func graceCases() throws -> [GraceCase] {
    let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
        .appendingPathComponent("../../../..", isDirectory: true).standardizedFileURL
    let fixtures =
        ProcessInfo.processInfo.environment["FIXTURES_DIR"].map { URL(fileURLWithPath: $0) }
        ?? root.appendingPathComponent("Fixtures")
    return try JSONDecoder().decode(
        [GraceCase].self, from: Data(contentsOf: fixtures.appendingPathComponent("goal-chain/cases.json")))
}

@Test(arguments: try graceCases())
func graceDayFixtures(_ fixture: GraceCase) throws {
    let start = try #require(CalendarDate(fixture.start))
    let period = try #require(GoalPeriod(rawValue: fixture.period))
    let kind = try #require(GoalKind(rawValue: fixture.kind))
    let definition = try #require(
        GoalDefinition(
            id: "orbit", key: "orbit", name: "Orbit", period: period,
            kind: kind, target: fixture.kind == "number" ? 2 : 1))
    let logs = try fixture.sequence.enumerated().compactMap { offset, symbol -> GoalLog? in
        guard symbol != "?" else { return nil }
        let value: GoalValue = fixture.kind == "number" ? .number(symbol == "1" ? 2 : 1) : .boolean(symbol == "1")
        return GoalLog(day: try #require(start.addingDays(offset)), value: value)
    }
    let today = try #require(start.addingDays(fixture.sequence.count - 1))
    let result = GoalProgress.compute(definition: definition, logs: logs, today: today)
    #expect(result.streak == fixture.expected.streak, "\(fixture.id)")
    #expect(result.longestStreak == fixture.expected.longestStreak, "\(fixture.id)")
    #expect(result.graceDaysAvailable == fixture.expected.graceDaysAvailable, "\(fixture.id)")
    #expect(result.graceSpentDays.map(\.description) == fixture.expected.graceSpentDays, "\(fixture.id)")
    #expect(result.score == fixture.expected.score, "\(fixture.id)")
    #expect(result.isPendingToday == fixture.expected.isPendingToday, "\(fixture.id)")
    // Neither future logs nor their rewards can change an earlier standing.
    let future = GoalLog(day: try #require(today.addingDays(1)), value: .boolean(true))
    #expect(GoalProgress.compute(definition: definition, logs: logs + [future], today: today) == result)
}
