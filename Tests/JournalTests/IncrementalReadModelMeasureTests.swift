import Foundation
import Testing
import VaultFormat
import VaultIndex
import VaultStore

@testable import Journal

/// Optional scale measurement. Enable with MEASURE_READ_MODEL=1 (skipped in default CI).
struct IncrementalReadModelMeasureTests {
    @Test(
        .enabled(if: ProcessInfo.processInfo.environment["MEASURE_READ_MODEL"] == "1")
    )
    func fiveYearEventUpdateCost() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(
            "read-model-measure-" + UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }

        _ = try SyntheticVault.generate(at: root, configuration: .fiveYears)
        let index = try VaultIndex()
        try index.rebuild(vaultRoot: root)
        let today = CalendarDate("2026-10-05")!
        let store = VaultStore(vaultRoot: root, index: index)
        let baseline = VaultReadModel(snapshot: try index.snapshot(), today: today)

        _ = try await store.addingEvent(on: today, text: "Measure event", time: nil)
        let day = "journal/\(today).md"

        let fullStart = DispatchTime.now()
        let full = VaultReadModel(snapshot: try index.snapshot(), today: today)
        let fullMs = Double(DispatchTime.now().uptimeNanoseconds - fullStart.uptimeNanoseconds) / 1_000_000

        let incStart = DispatchTime.now()
        let incremental = try VaultPublishedContent.applying(
            previous: baseline, index: index, changedPaths: [day], today: today
        ).content
        let incMs = Double(DispatchTime.now().uptimeNanoseconds - incStart.uptimeNanoseconds) / 1_000_000
        let peakMB = Int(residentMemoryBytes() / 1_024 / 1_024)

        print(
            """
            MEASURE_READ_MODEL fiveYears:
              full snapshot+build: \(String(format: "%.1f", fullMs)) ms
              incremental apply: \(String(format: "%.1f", incMs)) ms
              resident memory: \(peakMB) MB
              equal: \(incremental.matchesScreenFields(full))
            """)
        #expect(incremental.matchesScreenFields(full))
        #expect(incMs * 5 < fullMs)
    }

    /// Per-field rows and payload bytes of the five-year read model, and how long a rederive
    /// takes: the baseline later slices measure against as fields move to Core queries.
    @Test(
        .enabled(if: ProcessInfo.processInfo.environment["MEASURE_READ_MODEL"] == "1")
    )
    func fiveYearFieldSizesAndRederiveCost() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(
            "read-model-fields-" + UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }

        _ = try SyntheticVault.generate(at: root, configuration: .fiveYears)
        let index = try VaultIndex()
        try index.rebuild(vaultRoot: root)
        let today = CalendarDate("2026-10-05")!

        var snapshotMs: [Double] = []
        var rederiveMs: [Double] = []
        var model = VaultReadModel.empty
        for _ in 0..<5 {
            let snapshotStart = DispatchTime.now()
            let snapshot = try index.snapshot()
            snapshotMs.append(milliseconds(since: snapshotStart))
            let rederiveStart = DispatchTime.now()
            model = VaultReadModel(snapshot: snapshot, today: today)
            rederiveMs.append(milliseconds(since: rederiveStart))
        }

        var lines = ["MEASURE_READ_MODEL fields fiveYears (field | rows | nested rows | bytes):"]
        var total = PayloadSize()
        for child in Mirror(reflecting: model).children {
            guard let label = child.label else { continue }
            let size = PayloadSize(of: child.value)
            total.rows += size.rows
            total.nestedRows += size.nestedRows
            total.bytes += size.bytes
            lines.append("  \(label) | \(size.rows) | \(size.nestedRows) | \(size.bytes)")
        }
        lines.append("  total | \(total.rows) | \(total.nestedRows) | \(total.bytes)")
        lines.append("  snapshot median: \(String(format: "%.1f", median(snapshotMs))) ms")
        lines.append("  rederive median: \(String(format: "%.1f", median(rederiveMs))) ms")
        // The graph's share moved out of the rederive: what the screen now queries on demand.
        var graphMs: [Double] = []
        for _ in 0..<5 {
            let start = DispatchTime.now()
            _ = GraphInput(entities: model.entities, mentions: try index.graphMentions(kinds: GraphInput.kinds))
            graphMs.append(milliseconds(since: start))
        }
        lines.append("  graph query median: \(String(format: "%.1f", median(graphMs))) ms")
        print(lines.joined(separator: "\n"))
        #expect(model.isBuilt && !model.days.isEmpty)
    }
}

/// Approximate payload of a value: UTF-8 bytes of its strings plus the width of its scalars.
/// `rows` are a collection's direct elements; `nestedRows` counts every collection element at
/// any depth, so a dictionary of arrays reports its keys and all their entries.
private struct PayloadSize {
    var rows = 0
    var nestedRows = 0
    var bytes = 0

    init() {}

    init(of value: Any) {
        self = Self.measure(value)
        if Self.isCollection(Mirror(reflecting: value)) { rows = Mirror(reflecting: value).children.count }
    }

    private static func isCollection(_ mirror: Mirror) -> Bool {
        mirror.displayStyle.map { [.collection, .dictionary, .set].contains($0) } ?? false
    }

    private static func measure(_ value: Any) -> PayloadSize {
        var size = PayloadSize()
        switch value {
        case let text as String:
            size.bytes = text.utf8.count
            return size
        case is Bool:
            size.bytes = 1
            return size
        case is Int, is Double, is Float, is Int64, is UInt64:
            size.bytes = 8
            return size
        default:
            break
        }
        let mirror = Mirror(reflecting: value)
        let collection = isCollection(mirror)
        if mirror.children.isEmpty && mirror.displayStyle == .enum { size.bytes = 1 }
        for child in mirror.children {
            let inner = measure(child.value)
            size.nestedRows += inner.nestedRows + (collection ? 1 : 0)
            size.bytes += inner.bytes
        }
        return size
    }
}

private func milliseconds(since start: DispatchTime) -> Double {
    Double(DispatchTime.now().uptimeNanoseconds - start.uptimeNanoseconds) / 1_000_000
}

private func median(_ values: [Double]) -> Double {
    values.sorted()[values.count / 2]
}

private func residentMemoryBytes() -> UInt64 {
    var info = mach_task_basic_info()
    var count = mach_msg_type_number_t(MemoryLayout<mach_task_basic_info>.size) / 4
    let result = withUnsafeMutablePointer(to: &info) {
        $0.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
            task_info(mach_task_self_, task_flavor_t(MACH_TASK_BASIC_INFO), $0, &count)
        }
    }
    return result == KERN_SUCCESS ? info.resident_size : 0
}
