import Foundation
import Testing
import VaultFormat

@testable import Journal

/// Optional scale measurement of the day layer and the day's own graph on the five-year synthetic
/// vault. Enable with MEASURE_READ_MODEL=1 (TEST_RUNNER_MEASURE_READ_MODEL=1 under xcodebuild;
/// skipped in default CI).
@MainActor struct DayGraphMeasureTests {
    @Test(.enabled(if: ProcessInfo.processInfo.environment["MEASURE_READ_MODEL"] == "1"))
    func fiveYearDayLayerAndDayGraphCost() async throws {
        let context = try TaskTestContext()
        defer { context.clean() }
        let manifest = try SyntheticVault.generate(at: context.root, configuration: .fiveYears)
        await context.start()
        #expect(context.store.lastUpdated != nil)
        let today = manifest.endDate
        var lines = [
            "MEASURE_READ_MODEL day graph fiveYears (case | nodes | edges | query ms | compute ms | layout ms):"
        ]

        let queryStart = DispatchTime.now()
        let input = try await context.store.computeGraphInput()
        let queryMs = milliseconds(since: queryStart)
        var quarter = GraphFilter()
        quarter.setDays(true)
        let cases: [(String, GraphFilter)] = [
            ("days off, all", GraphFilter()),
            ("days on, all", GraphFilter(days: true)),
            ("days on, 90 days (switch)", quarter),
        ]
        for (name, filter) in cases {
            let computeStart = DispatchTime.now()
            let graph = GraphModel.compute(input: input, filter: filter, today: today)
            let computeMs = milliseconds(since: computeStart)
            let layoutStart = DispatchTime.now()
            _ = GraphLayout.compute(graph)
            let layoutMs = milliseconds(since: layoutStart)
            lines.append(
                "\(name) | \(graph.nodes.count) | \(graph.edges.count) | \(Int(queryMs)) | \(Int(computeMs)) | \(Int(layoutMs))"
            )
        }

        let dayStart = DispatchTime.now()
        let dayInput = try await context.store.computeDayGraphInput(on: today)
        let dayQueryMs = milliseconds(since: dayStart)
        let computeStart = DispatchTime.now()
        let dayGraph = GraphModel.compute(input: dayInput, filter: GraphFilter(scope: .day(today)), today: today)
        let dayComputeMs = milliseconds(since: computeStart)
        let layoutStart = DispatchTime.now()
        _ = GraphLayout.compute(dayGraph)
        let dayLayoutMs = milliseconds(since: layoutStart)
        lines.append(
            "day \(today) | \(dayGraph.nodes.count) | \(dayGraph.edges.count) | \(String(format: "%.1f", dayQueryMs)) | \(String(format: "%.2f", dayComputeMs)) | \(Int(dayLayoutMs))"
        )
        #expect(dayGraph.nodes.count > 1)
        print(lines.joined(separator: "\n"))
    }

    private func milliseconds(since start: DispatchTime) -> Double {
        Double(DispatchTime.now().uptimeNanoseconds - start.uptimeNanoseconds) / 1_000_000
    }
}
