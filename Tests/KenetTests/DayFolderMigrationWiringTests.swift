import Foundation
import Testing
import VaultFormat
import VaultStore

@testable import Kenet

/// Opening a vault written before 2026-11-13 (`Fixtures/migration/legacy-vault`) moves its days to
/// `diary/` once, through the write queue, and tells the main screen's band.
@MainActor @Suite(.timeLimit(.minutes(1)))
struct DayFolderMigrationWiringTests {
    private static let fixture = CloudSyncTestContext.fixtures.deletingLastPathComponent()
        .appendingPathComponent("migration/legacy-vault")

    private func open() async throws -> CloudSyncTestContext {
        let context = try CloudSyncTestContext(
            .local, fixture: "../migration/legacy-vault/source", policy: SyncPolicy(mergesDayCopies: false))
        await context.start()
        // The first refresh schedules the run when it ends; the run refreshes once more itself.
        await context.store.waitWhileRefreshInFlight()
        await context.store.waitForDayFolderMigration()
        await context.store.waitWhileRefreshInFlight()
        return context
    }

    @Test func openingALegacyVaultMovesItsDays() async throws {
        let context = try await open()
        defer { context.clean() }
        let expected = try DayCopyVaultContext.tree(Self.fixture.appendingPathComponent("expected"))
        // Opening a local vault also adds the standard templates; only the days are compared.
        #expect(try DayCopyVaultContext.tree(context.root).filter { !$0.key.hasPrefix("templates/") } == expected)
        let report = try #require(context.store.sync.mergeReport)
        #expect(report.movedDays == 5 && report.copiedDays == 2 && report.unmovedDays == 0)
        #expect(!report.hasFailures)
        // The refresh after the run found the new day copies; the moved days answer from `diary/`.
        #expect(context.store.sync.dayCopies == ["diary/2026-10-05 2.md", "diary/2026-10-06 2.md"])
        let day = try await context.store.computeDay(on: CalendarDate("2026-10-01")!)
        #expect(day.id == "diary/2026-10-01.md")
        #expect(day.diary.map(\.text.plainText) == ["Sakin bir gündü."])
    }

    /// The legacy folder keeps a note, so it stays; the same listing starts no second run.
    @Test func theSameListingStartsNoSecondRun() async throws {
        let context = try await open()
        defer { context.clean() }
        let first = context.store.sync.mergeReport
        let tree = try DayCopyVaultContext.tree(context.root)
        await context.refresh()
        await context.store.waitForDayFolderMigration()
        #expect(context.store.sync.mergeReport == first)
        #expect(try DayCopyVaultContext.tree(context.root) == tree)
        // A day file another device writes into the legacy folder changes the listing: it moves.
        let late = context.url(LegacyVaultNames.dayFolder + "/2026-10-09.md")
        try Data("## \(LegacyVaultNames.diaryHeading)\nGeç gelen.\n".utf8).write(to: late)
        await context.refresh()
        await context.store.waitWhileRefreshInFlight()
        await context.store.waitForDayFolderMigration()
        await context.store.waitWhileRefreshInFlight()
        #expect(!FileManager.default.fileExists(atPath: late.path))
        #expect(
            try Data(contentsOf: context.url("diary/2026-10-09.md")) == Data("## Diary\nGeç gelen.\n".utf8))
        #expect(context.store.sync.mergeReport?.movedDays == 6)
    }
}
