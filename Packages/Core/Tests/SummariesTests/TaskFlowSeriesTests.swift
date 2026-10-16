import Foundation
import Summaries
import Testing
import VaultFormat
import VaultIndex

struct TaskFlowSeriesTests {
    @Test func taskOnlyQueryMatchesFixtureTaskCounts() throws {
        let fixtures = fixtureDirectory()
        let cases = try #require(
            JSONSerialization.jsonObject(
                with: Data(contentsOf: fixtures.appendingPathComponent("summaries/cases.json")))
                as? [[String: Any]])
        let index = try VaultIndex()
        try index.rebuild(vaultRoot: fixtures.appendingPathComponent("vaults/sample"))
        let data = SummaryInput(tasks: try index.summaryTasks())
        for fixture in cases {
            let period = try #require((fixture["period"] as? String).flatMap(SummaryPeriod.init(rawValue:)))
            let day = try #require((fixture["containing"] as? String).flatMap(CalendarDate.init))
            let expected = try #require(fixture["expected"] as? [String: Any])
            let counts = try #require(expected["counts"] as? [String: Any])
            let summary = PeriodSummary.compute(period: period, containing: day, data: data)
            let actual = [
                "createdTasks": summary.counts.createdTasks, "completedTasks": summary.counts.completedTasks,
                "overdueTasks": summary.counts.overdueTasks, "undatedTasks": summary.counts.undatedTasks,
            ]
            for (key, value) in actual {
                #expect(value == counts[key] as? Int, Comment(rawValue: fixture["id"] as? String ?? ""))
            }
        }
    }

    @Test(arguments: [
        "empty", "running-week", "finished-leap-month", "inventory-exclusions", "running-year",
        "future-period", "calendar-lower-bound", "running-month",
    ])
    func inventoryFixturesMatchHandCountedExpectations(id: String) throws {
        let fixtures = try #require(
            JSONSerialization.jsonObject(
                with: Data(contentsOf: fixtureDirectory().appendingPathComponent("summaries/task-flow.json")))
                as? [[String: Any]])
        let fixture = try #require(fixtures.first { $0["id"] as? String == id })
        let period = try #require((fixture["period"] as? String).flatMap(SummaryPeriod.init(rawValue:)))
        let day = try #require((fixture["containing"] as? String).flatMap(CalendarDate.init))
        let today = (fixture["today"] as? String).flatMap(CalendarDate.init)
        let rows = try #require(fixture["tasks"] as? [[String: Any]])
        let tasks = try rows.map { row in
            let status = try #require((row["status"] as? String).flatMap(TaskStatus.init(rawValue:)))
            return SummaryInput.Task(
                created: (row["created"] as? String).flatMap(CalendarDate.init), status: status,
                due: (row["due"] as? String).flatMap(CalendarDate.init),
                done: (row["done"] as? String).flatMap(CalendarDate.init))
        }
        let result = TaskFlowSeries.compute(tasks: tasks, period: period, containing: day, today: today)
        let expected = try #require(fixture["expected"] as? [String: Any])
        #expect(try canonical(snapshot(result)) == canonical(expected))
    }
}

private func snapshot(_ value: TaskFlowSeries) -> [String: Any] {
    func units(_ rows: [TaskFlowSeries.Unit]) -> [[String: Any]] {
        rows.map {
            [
                "id": $0.id, "range": [$0.range.lowerBound.description, $0.range.upperBound.description],
                "measuredEnd": $0.measuredEnd.description, "open": $0.open,
            ]
        }
    }
    return [
        "units": units(value.units), "previous": units(value.previous), "unitCount": value.unitCount,
        "opening": value.opening, "closing": value.closing, "peak": value.peak.map { $0.id as Any } ?? NSNull(),
    ]
}
