import Foundation
import GoalTracking
import Testing
import VaultFormat

private struct SeriesFixtures: Decodable {
    struct Daily: Decodable, Sendable {
        struct Expected: Decodable, Sendable {
            struct Average: Decodable, Sendable {
                let index: Int
                let value: Double
                let segment: Int
            }
            let values: [Double]
            let indices, segments: [Int]
            let average: Double?
            let metCount: Int
            let peakIndex: Int?
            let averages: [Average]
        }
        let id, today: String
        let span: Int
        let target: Double
        let logs: [GoalFixture.Log]
        let expected: Expected
    }
    struct Period: Decodable, Sendable {
        struct Expected: Decodable, Sendable {
            let totals: [Double]
            let starts: [String]
            let pace, total: Double
            let peakIndex: Int
        }
        let id, period, kind, today: String
        let target: Double
        let count: Int
        let logs: [GoalFixture.Log]
        let expected: Expected?
    }
    let daily: [Daily]
    let periods: [Period]
}

private func seriesFixtures() throws -> SeriesFixtures {
    var root = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
    while root.path != "/" && !FileManager.default.fileExists(atPath: root.appendingPathComponent("Fixtures").path) {
        root.deleteLastPathComponent()
    }
    let fixtures =
        ProcessInfo.processInfo.environment["FIXTURES_DIR"].map { URL(fileURLWithPath: $0) }
        ?? root.appendingPathComponent("Fixtures")
    // JSON has no NaN: the string "nan" stands for one, so invalid numbers stay testable.
    let decoder = JSONDecoder()
    decoder.nonConformingFloatDecodingStrategy = .convertFromString(
        positiveInfinity: "inf", negativeInfinity: "-inf", nan: "nan")
    return try decoder.decode(
        SeriesFixtures.self, from: Data(contentsOf: fixtures.appendingPathComponent("goals/series.json")))
}

private func seriesLogs(_ logs: [GoalFixture.Log]) throws -> [GoalLog] {
    try logs.map { GoalLog(day: try #require(CalendarDate($0.day)), value: $0.value.value) }
}

@Test(arguments: try seriesFixtures().daily)
private func dailyValueSeries(_ fixture: SeriesFixtures.Daily) throws {
    let today = try #require(CalendarDate(fixture.today))
    let result = GoalValueSeries.daily(
        logs: try seriesLogs(fixture.logs), target: fixture.target, today: today, span: fixture.span)
    let expected = fixture.expected
    #expect(result.span == fixture.span)
    #expect(result.start == today.addingDays(1 - fixture.span))
    #expect(result.points.map(\.value) == expected.values, "\(fixture.id)")
    #expect(result.points.map(\.index) == expected.indices)
    #expect(result.points.map(\.segment) == expected.segments)
    #expect(result.points.allSatisfy { $0.day == result.start.addingDays($0.index) })
    #expect(result.average == expected.average)
    #expect(result.metCount == expected.metCount)
    #expect(result.peak?.index == expected.peakIndex)
    #expect(result.averages.map(\.index) == expected.averages.map(\.index))
    #expect(result.averages.map(\.segment) == expected.averages.map(\.segment))
    for (actual, wanted) in zip(result.averages, expected.averages) {
        #expect(abs(actual.value - wanted.value) < 0.000_001, "\(fixture.id), day \(wanted.index)")
    }
}

@Test(arguments: try seriesFixtures().periods)
private func goalPeriodTotals(_ fixture: SeriesFixtures.Period) throws {
    let period = try #require(GoalPeriod(rawValue: fixture.period))
    let kind = try #require(GoalKind(rawValue: fixture.kind))
    let goal = try #require(
        GoalDefinition(
            id: fixture.id, key: "sample", name: "Sample", period: period,
            kind: kind, target: fixture.target))
    let result = GoalPeriodTotals.make(
        goal: goal, logs: try seriesLogs(fixture.logs), today: try #require(CalendarDate(fixture.today)),
        count: fixture.count)
    guard let expected = fixture.expected else {
        #expect(result == nil)
        return
    }
    let totals = try #require(result)
    #expect(totals.unit == (goal.period == .week ? .week : .month))
    #expect(totals.buckets.map(\.index) == Array(0..<fixture.count))
    #expect(totals.buckets.map { $0.start.description } == expected.starts)
    #expect(totals.buckets.map(\.total) == expected.totals, "\(fixture.id)")
    #expect(totals.pace == expected.pace)
    #expect(totals.total == expected.total)
    #expect(totals.peak?.index == expected.peakIndex)
}
