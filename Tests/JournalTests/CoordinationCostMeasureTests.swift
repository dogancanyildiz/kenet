import Foundation
import Testing
import VaultFormat
import VaultIndex
import VaultStore

@testable import Journal

/// Optional cost of coordinated access on the five-year vault. Enable with MEASURE_COORDINATION=1
/// (skipped in default CI): sequential events through `IndexStore`, repeated document reads, and a
/// linked-person rename, each with the system coordinator and without one.
@MainActor
struct CoordinationCostMeasureTests {
    @Test(.enabled(if: ProcessInfo.processInfo.environment["MEASURE_COORDINATION"] == "1"))
    func fiveYearSequentialEvents() async throws {
        let context = try TaskTestContext()
        defer { context.clean() }
        try SyntheticVault.generate(at: context.root, configuration: .fiveYears)
        await context.start()
        let today = CalendarDate("2026-10-05")!
        let clock = ContinuousClock()
        let start = clock.now
        for number in 0..<100 {
            #expect(await context.store.addEvent(on: today, text: "Ölçüm olayı \(number)", time: nil))
        }
        let elapsed = start.duration(to: clock.now)
        print("MEASURE_COORDINATION events100 coordinated: \(Self.seconds(elapsed)) s")
    }

    @Test(.enabled(if: ProcessInfo.processInfo.environment["MEASURE_COORDINATION"] == "1"))
    func fiveYearDocumentReadsAndRename() async throws {
        for coordinated in [false, true] {
            let root = try testDirectory()
            defer { try? FileManager.default.removeItem(at: root) }
            let manifest = try SyntheticVault.generate(at: root, configuration: .fiveYears)
            let index = try VaultIndex()
            try index.rebuild(vaultRoot: root)
            let coordination: any FileCoordination =
                coordinated ? SystemFileCoordination() : DirectFileCoordination()
            let store = VaultStore(vaultRoot: root, index: index, fileCoordination: coordination)
            let label = coordinated ? "coordinated" : "direct"
            let clock = ContinuousClock()

            let readStart = clock.now
            for _ in 0..<200 { _ = try await store.document(at: "journal/2026-10-05.md") }
            print("MEASURE_COORDINATION reads200 \(label): \(Self.seconds(readStart.duration(to: clock.now))) s")

            let placeStart = clock.now
            for place in manifest.places { _ = try await store.document(at: "places/\(place).md") }
            print(
                "MEASURE_COORDINATION placeReads\(manifest.places.count) \(label): "
                    + "\(Self.seconds(placeStart.duration(to: clock.now))) s")

            let person = try #require(manifest.linkedPersonPath)
            let renameStart = clock.now
            let result = try await store.renamingEntity(at: person, to: "Zora Ölçüm")
            let renameElapsed = renameStart.duration(to: clock.now)
            #expect(result.failures.isEmpty)
            print(
                "MEASURE_COORDINATION rename \(label): \(Self.seconds(renameElapsed)) s, "
                    + "files \(manifest.markdownFileCount), updated \(result.updatedFiles.count)")
        }
    }

    private static func seconds(_ duration: Duration) -> String {
        let components = duration.components
        return String(format: "%.3f", Double(components.seconds) + Double(components.attoseconds) / 1e18)
    }
}
