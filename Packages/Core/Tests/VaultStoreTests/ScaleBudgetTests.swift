import Foundation
import GRDB
import Testing
import VaultFormat

@testable import VaultIndex
@testable import VaultStore

/// Deterministic scale budgets (always on) and opt-in wall-clock budgets for a 5-year vault.
@Suite(.serialized)
struct ScaleBudgetTests {
    // MARK: - Deterministic counters (fast, always on)

    @Test func initialBuildReadsEveryMarkdownFileOnce() throws {
        try withSyntheticVault(.compact) { root, manifest in
            let reader = CountingReader()
            let index = try VaultIndex(readFile: reader.read)
            let result = try index.rebuild(vaultRoot: root)
            #expect(result.addedPaths.count == manifest.markdownFileCount)
            #expect(reader.markdownCount(under: root) == manifest.markdownFileCount)
            #expect(try index.files().count == manifest.markdownFileCount)
        }
    }

    @Test func idleRefreshParsesNothingAndWritesNoContentRows() throws {
        try withSyntheticVault(.compact) { root, manifest in
            let reader = CountingReader()
            let index = try VaultIndex(readFile: reader.read)
            try index.rebuild(vaultRoot: root)
            #expect(reader.markdownCount(under: root) == manifest.markdownFileCount)

            let log = StatementLog()
            try index.database.write { db in db.trace { log.append($0.description) } }
            reader.reset()
            let idle = try index.refresh(vaultRoot: root)
            try index.database.write { $0.trace(nil) }

            #expect(idle.addedPaths.isEmpty)
            #expect(idle.updatedPaths.isEmpty)
            #expect(idle.deletedPaths.isEmpty)
            #expect(reader.markdownCount(under: root) == 0)
            #expect(log.contentMutations.isEmpty)

            // Same counters on a larger vault: idle cost must not grow with file count.
            var large = SyntheticVault.Configuration.compact
            large.days = 90
            large.notesCount = 30
            try withSyntheticVault(large) { largeRoot, _ in
                let largeReader = CountingReader()
                let largeIndex = try VaultIndex(readFile: largeReader.read)
                try largeIndex.rebuild(vaultRoot: largeRoot)
                largeReader.reset()
                let largeLog = StatementLog()
                try largeIndex.database.write { db in db.trace { largeLog.append($0.description) } }
                let largeIdle = try largeIndex.refresh(vaultRoot: largeRoot)
                try largeIndex.database.write { $0.trace(nil) }
                #expect(largeIdle.addedPaths.isEmpty)
                #expect(largeIdle.updatedPaths.isEmpty)
                #expect(largeIdle.deletedPaths.isEmpty)
                #expect(largeReader.markdownCount(under: largeRoot) == 0)
                #expect(largeLog.contentMutations.count == log.contentMutations.count)
            }
        }
    }

    @Test func singleEventWriteStaysBoundedIndependentOfVaultSize() async throws {
        let small = try await measureEventWrite(configuration: .compact)
        var large = SyntheticVault.Configuration.compact
        large.days = 90
        large.peopleCount = 80
        large.notesCount = 40
        let big = try await measureEventWrite(configuration: large)
        #expect(small.markdownReads <= 3)
        #expect(big.markdownReads == small.markdownReads)
        // One-file index update: mutations stay in a fixed band. A full reindex would be thousands.
        #expect(small.sqlMutations > 0)
        #expect(small.sqlMutations <= 120)
        #expect(big.sqlMutations <= 120)
        #expect(big.sqlMutations <= small.sqlMutations + 30)
    }

    @Test func renameReadCountStaysLinearWithVaultSizeNotLinkDensity() async throws {
        // Same day count, denser events → more links; reads must not grow with link density.
        var sparse = SyntheticVault.Configuration.compact
        sparse.eventsPerDay = 2
        sparse.days = 30
        var dense = sparse
        dense.eventsPerDay = 8

        let sparseReads = try await renameMarkdownReads(configuration: sparse)
        let denseReads = try await renameMarkdownReads(configuration: dense)
        #expect(sparseReads > 0)
        #expect(denseReads == sparseReads)

        // Doubling journal days roughly doubles files; reads must stay within a linear band.
        var wider = sparse
        wider.days = sparse.days * 2
        let widerReads = try await renameMarkdownReads(configuration: wider)
        #expect(widerReads <= sparseReads * 2 + 8)
        #expect(widerReads >= sparseReads)
    }

    // MARK: - Opt-in wall-clock budgets (5-year vault)

    @Test func fiveYearVaultStaysWithinOptInBudgets() async throws {
        guard ProcessInfo.processInfo.environment["SCALE_BUDGET_SECONDS"] != nil else { return }

        // Generous ceilings (~5× local measurements on this machine).
        let initialBudget = Duration.seconds(40)
        let refreshBudget = Duration.seconds(5)
        let writeBudget = Duration.seconds(5)
        let renameBudget = Duration.seconds(30)

        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }

        let manifest = try SyntheticVault.generate(at: root, configuration: .fiveYears)
        let reader = CountingReader()
        let index = try VaultIndex(readFile: reader.read)
        let clock = ContinuousClock()

        let initialStart = clock.now
        let built = try index.rebuild(vaultRoot: root)
        let initialElapsed = initialStart.duration(to: clock.now)
        let initialReads = reader.markdownCount(under: root)
        #expect(built.addedPaths.count == manifest.markdownFileCount)
        #expect(initialReads == manifest.markdownFileCount)

        reader.reset()
        let refreshStart = clock.now
        let idle = try index.refresh(vaultRoot: root)
        let refreshElapsed = refreshStart.duration(to: clock.now)
        let refreshReads = reader.markdownCount(under: root)
        #expect(idle.addedPaths.isEmpty && idle.updatedPaths.isEmpty && idle.deletedPaths.isEmpty)
        #expect(refreshReads == 0)

        let storeReader = CountingReader()
        let store = VaultStore(
            vaultRoot: root, index: index, randomValue: { 0 },
            linkFile: { try FileManager.default.linkItem(at: $0, to: $1) },
            readFile: storeReader.read)
        storeReader.reset()
        let writeStart = clock.now
        _ = try await store.addingEvent(on: manifest.endDate, text: "Kurgusal ölçek olayı")
        let writeElapsed = writeStart.duration(to: clock.now)
        let writeReads = storeReader.markdownCount(under: root)

        guard let linkedPath = manifest.linkedPersonPath else {
            Issue.record("five-year vault must include a linked person")
            return
        }
        storeReader.reset()
        let renameStart = clock.now
        let renamed = try await store.renamingEntity(at: linkedPath, to: "Zora Renamed")
        let renameElapsed = renameStart.duration(to: clock.now)
        let renameReads = storeReader.markdownCount(under: root)

        print(
            """
            SCALE_BUDGET files=\(manifest.markdownFileCount) \
            initial=\(initialElapsed) reads=\(initialReads) \
            refresh=\(refreshElapsed) reads=\(refreshReads) \
            write=\(writeElapsed) reads=\(writeReads) \
            rename=\(renameElapsed) reads=\(renameReads) updated=\(renamed.updatedFiles.count)
            """)

        #expect(initialElapsed < initialBudget, "Initial open exceeded \(initialBudget): \(initialElapsed)")
        #expect(refreshElapsed < refreshBudget, "Idle refresh exceeded \(refreshBudget): \(refreshElapsed)")
        #expect(writeElapsed < writeBudget, "Event write exceeded \(writeBudget): \(writeElapsed)")
        #expect(renameElapsed < renameBudget, "Rename exceeded \(renameBudget): \(renameElapsed)")
        #expect(renamed.failures.isEmpty)
    }

    // MARK: - Helpers

    private func withSyntheticVault(
        _ configuration: SyntheticVault.Configuration,
        _ body: (URL, SyntheticVault.Manifest) throws -> Void
    ) throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let manifest = try SyntheticVault.generate(at: root, configuration: configuration)
        try body(root, manifest)
    }

    private struct EventWriteStats: Sendable {
        var markdownReads: Int
        var sqlMutations: Int
    }

    private func measureEventWrite(configuration: SyntheticVault.Configuration) async throws -> EventWriteStats {
        try await withSyntheticVaultAsync(configuration) { root, manifest in
            let index = try VaultIndex()
            try index.rebuild(vaultRoot: root)
            let reader = CountingReader()
            let store = VaultStore(
                vaultRoot: root, index: index, randomValue: { 0 },
                linkFile: { try FileManager.default.linkItem(at: $0, to: $1) },
                readFile: reader.read)
            let log = StatementLog()
            try await index.database.write { db in db.trace { log.append($0.description) } }
            reader.reset()
            log.reset()
            _ = try await store.addingEvent(on: manifest.endDate, text: "Kurgusal olay ekleme")
            try await index.database.write { $0.trace(nil) }
            return EventWriteStats(
                markdownReads: reader.markdownCount(under: root),
                sqlMutations: log.contentMutations.count)
        }
    }

    private func renameMarkdownReads(configuration: SyntheticVault.Configuration) async throws -> Int {
        try await withSyntheticVaultAsync(configuration) { root, manifest in
            let index = try VaultIndex()
            try index.rebuild(vaultRoot: root)
            let reader = CountingReader()
            let store = VaultStore(
                vaultRoot: root, index: index, randomValue: { 0 },
                linkFile: { try FileManager.default.linkItem(at: $0, to: $1) },
                readFile: reader.read)
            let path = try #require(manifest.linkedPersonPath)
            reader.reset()
            let result = try await store.renamingEntity(at: path, to: "Zora Renamed")
            #expect(result.failures.isEmpty)
            return reader.markdownCount(under: root)
        }
    }

    private func withSyntheticVaultAsync<T: Sendable>(
        _ configuration: SyntheticVault.Configuration,
        _ body: @Sendable (URL, SyntheticVault.Manifest) async throws -> T
    ) async throws -> T {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let manifest = try SyntheticVault.generate(at: root, configuration: configuration)
        return try await body(root, manifest)
    }
}
