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
        let peakMB = Int(mach_task_basic_info_resident() / 1_024 / 1_024)

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
}

private func mach_task_basic_info_resident() -> UInt64 {
    var info = mach_task_basic_info()
    var count = mach_msg_type_number_t(MemoryLayout<mach_task_basic_info>.size) / 4
    let result = withUnsafeMutablePointer(to: &info) {
        $0.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
            task_info(mach_task_self_, task_flavor_t(MACH_TASK_BASIC_INFO), $0, &count)
        }
    }
    return result == KERN_SUCCESS ? info.resident_size : 0
}
