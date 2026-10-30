import Foundation
import Testing
import VaultFormat
import VaultIndex

@testable import Journal

/// The day copy fixture (`Fixtures/vaults/day-copies`) opened as the iCloud vault: its times, copies
/// and the vault Core's merge leaves behind.
@MainActor
struct DayCopyVaultContext {
    struct Cases: Decodable {
        let times: [String: Int]
        let dayCopies: [String]
    }

    static let fixture = CloudSyncTestContext.fixtures.appendingPathComponent("day-copies")

    let cloud: CloudSyncTestContext
    let cases: Cases
    var store: IndexStore { cloud.store }

    init(policy: SyncPolicy) throws {
        cloud = try CloudSyncTestContext(.icloud, fixture: "day-copies/source", policy: policy)
        cases = try JSONDecoder().decode(
            Cases.self, from: Data(contentsOf: Self.fixture.appendingPathComponent("cases.json")))
        for (path, time) in cases.times {
            try FileManager.default.setAttributes(
                [.modificationDate: Date(timeIntervalSince1970: TimeInterval(time))],
                ofItemAtPath: cloud.url(path).path)
        }
    }

    /// Opens the vault and waits for the merges its first refresh started.
    func start() async {
        await cloud.start()
        await store.waitForDayCopyMerges()
        await store.waitWhileRefreshInFlight()
    }

    /// Every visible file under `root` with its bytes; hidden folders (`.app`) are left out.
    static func tree(_ root: URL) throws -> [String: Data] {
        var files: [String: Data] = [:]
        for path in try FileManager.default.subpathsOfDirectory(atPath: root.path)
        where !path.split(separator: "/").contains(where: { $0.hasPrefix(".") }) {
            let url = root.appendingPathComponent(path)
            var isDirectory: ObjCBool = false
            guard FileManager.default.fileExists(atPath: url.path, isDirectory: &isDirectory), !isDirectory.boolValue
            else { continue }
            files[path] = try Data(contentsOf: url)
        }
        return files
    }

    func clean() { cloud.clean() }
}

@MainActor @Suite(.timeLimit(.minutes(1)))
struct DayCopyMergeWiringTests {
    @Test func mergeIsOffByDefault() async throws {
        #expect(SyncPolicy.standard.mergesDayCopies == false)
        let context = try DayCopyVaultContext(policy: .standard)
        defer { context.clean() }
        let before = try DayCopyVaultContext.tree(context.cloud.root)
        await context.start()

        #expect(context.store.sync.dayCopies == context.cases.dayCopies)
        #expect(try DayCopyVaultContext.tree(context.cloud.root) == before)
        #expect(context.store.sync.mergeReport == nil)
        #expect(context.store.syncStatus == .idle)
        // Diagnostics lists the copies as before.
        let listed = try await context.store.computeCopyFiles().filter { $0.folder == "journal" }.map(\.copy)
        #expect(listed == context.cases.dayCopies)
    }

    @Test func mergesEveryCopyInOrderAsCoreDoes() async throws {
        let context = try DayCopyVaultContext(policy: SyncPolicy(mergesDayCopies: true))
        defer { context.clean() }
        await context.start()

        // Byte for byte the vault Core's merge of every copy in order leaves (`DayCopyTests`).
        let expected = try DayCopyVaultContext.tree(DayCopyVaultContext.fixture.appendingPathComponent("expected"))
        #expect(try DayCopyVaultContext.tree(context.cloud.root) == expected)
        let merged = context.cases.dayCopies.count
        #expect(context.store.sync.mergeReport == DayCopyMergeReport(merged: merged, failed: 0))
        #expect(context.store.sync.mergeReport?.message == String(localized: "\(merged) gün kopyası birleştirildi."))
        #expect(context.store.sync.mergingCopies == 0)

        // Each merge published its day file: the copy that took a missing day's name is on screen.
        #expect(context.store.content.fragments["journal/2026-10-03.md"] != nil)
        // The index follows the merged files: as an index built from them alone.
        let fresh = try VaultIndex(databaseURL: context.cloud.directory.appendingPathComponent("fresh.sqlite"))
        try fresh.rebuild(vaultRoot: context.cloud.root)
        let rebuilt = try fresh.daySummaries(from: nil, to: nil).map(DayOverview.init(entry:))
        #expect(try await context.store.computeDaySummaries() == rebuilt)
        let renamed = try #require(CalendarDate("2026-10-03"))
        #expect(rebuilt.contains { $0.date == renamed })
        await context.cloud.refresh()
        #expect(context.store.sync.dayCopies.isEmpty)
    }

    /// Three versions of one day: the conflict copies' names depend on the merge order, so only the
    /// scan's order (`2026-10-02 2.md`, then `3`) gives the first order's names (`three-versions/case.json`).
    @Test func mergesInTheScanOrder() async throws {
        struct VersionCases: Decodable {
            let times: [String: Int]
            let dayPath: String
            let orders: [[String]]
            let conflicts: [[String]]
        }
        let fixture = DayCopyVaultContext.fixture.appendingPathComponent("three-versions")
        let cases = try JSONDecoder().decode(
            VersionCases.self, from: Data(contentsOf: fixture.appendingPathComponent("case.json")))
        let cloud = try CloudSyncTestContext(
            .icloud, fixture: "day-copies/three-versions/source", policy: SyncPolicy(mergesDayCopies: true))
        defer { cloud.clean() }
        for (path, time) in cases.times {
            try FileManager.default.setAttributes(
                [.modificationDate: Date(timeIntervalSince1970: TimeInterval(time))], ofItemAtPath: cloud.url(path).path
            )
        }
        await cloud.start()
        await cloud.store.waitForDayCopyMerges()

        #expect(cloud.store.sync.mergeReport == DayCopyMergeReport(merged: 2, failed: 0))
        let conflicts = try FileManager.default.contentsOfDirectory(atPath: cloud.url("conflicts").path)
            .map { "conflicts/" + $0 }.sorted()
        #expect(conflicts == cases.conflicts[0].sorted())
        #expect(
            try Data(contentsOf: cloud.url(cases.dayPath))
                == Data(contentsOf: fixture.appendingPathComponent("expected.md")))
    }

    @Test func aFailedCopyDoesNotStopTheOthers() async throws {
        let context = try DayCopyVaultContext(policy: SyncPolicy(mergesDayCopies: true))
        defer { context.clean() }
        // The first copy in merge order cannot be read.
        let blocked = try #require(context.cases.dayCopies.first)
        let blockedURL = context.cloud.url(blocked)
        try FileManager.default.setAttributes([.posixPermissions: 0o000], ofItemAtPath: blockedURL.path)
        defer { try? FileManager.default.setAttributes([.posixPermissions: 0o644], ofItemAtPath: blockedURL.path) }
        let blockedDay = try #require(DayCopyName.dayPath(ofCopy: blocked))
        let dayBefore = try Data(contentsOf: context.cloud.url(blockedDay))
        await context.start()

        let report = try #require(context.store.sync.mergeReport)
        #expect(report == DayCopyMergeReport(merged: context.cases.dayCopies.count - 1, failed: 1))
        #expect(report.message.contains(String(localized: "\(1) gün kopyası birleştirilemedi; Tanılama’da duruyor.")))
        #expect(FileManager.default.fileExists(atPath: blockedURL.path))
        #expect(try Data(contentsOf: context.cloud.url(blockedDay)) == dayBefore)
        for copy in context.cases.dayCopies.dropFirst() {
            #expect(!FileManager.default.fileExists(atPath: context.cloud.url(copy).path), "\(copy)")
        }
        // A failed copy is not tried again on the next refresh; it stays for Diagnostics.
        await context.cloud.refresh()
        await context.store.waitForDayCopyMerges()
        #expect(context.store.sync.dayCopies == [blocked])
        #expect(context.store.sync.mergeReport == report)
    }
}
