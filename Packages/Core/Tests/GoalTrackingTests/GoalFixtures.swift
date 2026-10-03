import Foundation
import GoalTracking
import Testing
import VaultFormat

struct GoalFixture: Decodable, Sendable {
    struct Definition: Decodable, Sendable {
        let id: String, key: String, name: String, period: String, kind: String
        let target: Double
    }
    struct Log: Decodable, Sendable {
        let day: String
        let value: Value
    }
    enum Value: Decodable, Sendable {
        case boolean(Bool)
        case number(Double)
        init(from decoder: any Decoder) throws {
            let container = try decoder.singleValueContainer()
            if let flag = try? container.decode(Bool.self) {
                self = .boolean(flag)
            } else {
                self = .number(try container.decode(Double.self))
            }
        }
        var value: GoalValue {
            switch self {
            case .boolean(let flag): .boolean(flag)
            case .number(let amount): .number(amount)
            }
        }
    }
    struct Expected: Decodable, Sendable {
        let done: Double, target: Double, yearDone: Double
        let streak: Int, longestStreak: Int
        let isPendingToday: Bool
        let periodStart: String, periodEnd: String
        let heatmap: [String: String]
    }
    let id: String
    let definition: Definition
    let logs: [Log]
    let today: String, heatmapFrom: String, heatmapTo: String
    let expected: Expected
}

func goalCases() throws -> [GoalFixture] {
    var root = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
    while root.path != "/" && !FileManager.default.fileExists(atPath: root.appendingPathComponent("Fixtures").path) {
        root.deleteLastPathComponent()
    }
    let fixtures =
        ProcessInfo.processInfo.environment["FIXTURES_DIR"].map { URL(fileURLWithPath: $0) }
        ?? root.appendingPathComponent("Fixtures")
    return try JSONDecoder().decode(
        [GoalFixture].self, from: Data(contentsOf: fixtures.appendingPathComponent("goals/cases.json")))
}

@Test(arguments: try goalCases())
func goalFixtures(_ fixture: GoalFixture) throws {
    let source = fixture.definition
    let period = try #require(GoalPeriod(rawValue: source.period))
    let kind = try #require(GoalKind(rawValue: source.kind))
    let definition = try #require(
        GoalDefinition(
            id: source.id, key: source.key, name: source.name,
            period: period,
            kind: kind, target: source.target))
    let logs = try fixture.logs.map { GoalLog(day: try #require(CalendarDate($0.day)), value: $0.value.value) }
    let result = GoalProgress.compute(
        definition: definition, logs: logs, today: try #require(CalendarDate(fixture.today)))
    #expect(result.progress.done == fixture.expected.done, "\(fixture.id)")
    #expect(result.progress.target == fixture.expected.target)
    #expect(result.streak == fixture.expected.streak, "\(fixture.id)")
    #expect(result.longestStreak == fixture.expected.longestStreak, "\(fixture.id)")
    #expect(result.isPendingToday == fixture.expected.isPendingToday)
    #expect(result.yearDone == fixture.expected.yearDone)
    #expect(result.periodStart.description == fixture.expected.periodStart)
    #expect(result.periodEnd.description == fixture.expected.periodEnd)
    if definition.period == .year {
        #expect(result.yearProgress?.done == fixture.expected.yearDone)
    } else {
        #expect(result.yearProgress == nil)
    }
    let marks = GoalProgress.heatmap(
        definition: definition, logs: logs,
        from: try #require(CalendarDate(fixture.heatmapFrom)), to: try #require(CalendarDate(fixture.heatmapTo)))
    let actual = Dictionary(uniqueKeysWithValues: marks.map { ($0.key.description, $0.value.rawValue) })
    #expect(actual == fixture.expected.heatmap, "\(fixture.id)")
}
