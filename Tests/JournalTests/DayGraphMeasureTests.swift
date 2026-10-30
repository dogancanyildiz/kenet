import Foundation
import Testing
import VaultFormat
import VaultIndex

@testable import Journal

/// Optional scale measurement of the day layer and the day's own graph on the five-year synthetic
/// vault. Enable with MEASURE_READ_MODEL=1 (TEST_RUNNER_MEASURE_READ_MODEL=1 under xcodebuild;
/// skipped in default CI).
@MainActor struct DayGraphMeasureTests {
    @Test(.enabled(if: ProcessInfo.processInfo.environment["MEASURE_READ_MODEL"] == "1"))
    func fiveYearDayLayerAndDayGraphCost() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(
            "day-graph-measure-" + UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        // The index is closed (released at the end of `measure`) before its vault folder goes.
        defer { try? FileManager.default.removeItem(at: root) }
        let manifest = try SyntheticVault.generate(at: root, configuration: .fiveYears)
        try measure(root: root, today: manifest.endDate)
    }

    private func measure(root: URL, today: CalendarDate) throws {
        let index = try VaultIndex()
        try index.rebuild(vaultRoot: root)
        let entities = VaultReadModel(snapshot: try index.snapshot(), today: today).entities
        var lines = [
            "MEASURE_READ_MODEL day graph fiveYears (case | nodes | edges | query ms | compute ms | layout ms):"
        ]

        let queryStart = DispatchTime.now()
        let input = GraphInput(entities: entities, mentions: try index.graphMentions(kinds: GraphInput.kinds))
        let queryMs = milliseconds(since: queryStart)
        let cases: [(String, GraphFilter)] = [
            ("90 days (default)", GraphFilter()),
            ("all", GraphFilter(period: .all)),
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
        let day = try index.dayGraphMentions(on: today, kinds: GraphInput.kinds)
        let dayInput = GraphInput(entities: entities, mentions: GraphMentions(totals: day.mentions, days: [day]))
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
