import Foundation
import Testing
import VaultFormat
import VaultStore

@testable import Kenet

/// A vault written before 2026-11-13 (`Fixtures/migration/legacy-vault`): opening it moves
/// nothing; the main screen offers the move and only the user's confirmation starts it. Until
/// then every read and write of a day kept in the legacy folder goes to that file.
@MainActor @Suite(.timeLimit(.minutes(1)))
struct DayFolderMigrationWiringTests {
    private static let fixture = CloudSyncTestContext.fixtures.deletingLastPathComponent()
        .appendingPathComponent("migration/legacy-vault")
    private static let day = CalendarDate("2026-10-01")!
    private static let legacyFile = LegacyVaultNames.dayFolder + "/2026-10-01.md"

    private func open() async throws -> CloudSyncTestContext {
        let context = try CloudSyncTestContext(
            .local, fixture: "../migration/legacy-vault/source", policy: SyncPolicy(mergesDayCopies: false))
        await context.start()
        await context.store.waitWhileRefreshInFlight()
        return context
    }

    /// Opening a local vault also adds the standard templates; only the rest is compared.
    private func days(_ root: URL) throws -> [String: Data] {
        try DayCopyVaultContext.tree(root).filter { !$0.key.hasPrefix("templates/") }
    }

    @Test func openingMovesNothingAndOffersTheMove() async throws {
        let context = try await open()
        defer { context.clean() }
        let source = try DayCopyVaultContext.tree(Self.fixture.appendingPathComponent("source"))
        #expect(try days(context.root) == source)
        // Six day files and one day copy wait in the legacy folder; the note does not count.
        #expect(context.store.sync.legacyDayFiles == 7)
        #expect(context.store.offersLegacyDayFolderMove)
        // "Sonra" puts the offer off for this opening, and a refresh does not bring it back.
        context.store.dismissLegacyDayFolderOffer()
        #expect(!context.store.offersLegacyDayFolderMove)
        await context.refresh()
        #expect(!context.store.offersLegacyDayFolderMove)
        #expect(try days(context.root) == source)
        #expect(context.store.sync.mergeReport == nil)
    }

    @Test func confirmingMovesTheDays() async throws {
        let context = try await open()
        defer { context.clean() }
        context.store.moveLegacyDayFolder()
        await context.store.waitForDayFolderMigration()
        await context.store.waitWhileRefreshInFlight()
        let expected = try DayCopyVaultContext.tree(Self.fixture.appendingPathComponent("expected"))
        #expect(try days(context.root) == expected)
        let report = try #require(context.store.sync.mergeReport)
        #expect(report.movedDays == 5 && report.copiedDays == 2 && report.unmovedDays == 0)
        #expect(!report.hasFailures)
        #expect(context.store.sync.legacyDayFiles == 0)
        #expect(!context.store.offersLegacyDayFolderMove)
        #expect(context.store.sync.dayCopies == ["diary/2026-10-05 2.md", "diary/2026-10-06 2.md"])
        let day = try await context.store.computeDay(on: Self.day)
        #expect(day.id == "diary/2026-10-01.md")
        #expect(day.diary.map(\.text.plainText) == ["Sakin bir gündü."])
    }

    /// A day only in the legacy folder: the editor reads and saves that file, an event is changed,
    /// added and deleted there, and no file starts under `diary/`.
    @Test func aDayOnlyInTheLegacyFolderIsEditedThere() async throws {
        let context = try await open()
        defer { context.clean() }
        let store = context.store
        let file = context.url(Self.legacyFile)
        let model = DiaryEditorModel(store: store, day: Self.day)
        await model.load()
        #expect(model.text == "Sakin bir gündü.\n")
        model.text = "Değişti.\n"
        #expect(await model.save())
        let heading = "## \(LegacyVaultNames.diaryHeading)\n"
        #expect(try String(decoding: Data(contentsOf: file), as: UTF8.self).hasSuffix(heading + "Değişti.\n"))

        let row = try #require(try await store.computeDay(on: Self.day).events.first)
        let target = try await store.eventTarget(on: Self.day, row: row)
        try await store.changeEvent(on: Self.day, target: target, to: "[[Ada Kurt]] ile çay")
        #expect(try String(decoding: Data(contentsOf: file), as: UTF8.self).contains("ile çay"))
        #expect(await store.addEvent(on: Self.day, text: "Akşam yürüyüşü", time: nil))
        let changed = try #require(
            try await store.computeDay(on: Self.day).events.first { $0.sourceText.contains("çay") })
        try await store.deleteEvent(on: Self.day, target: try await store.eventTarget(on: Self.day, row: changed))
        let text = String(decoding: try Data(contentsOf: file), as: UTF8.self)
        #expect(!text.contains("ile çay") && text.contains("Akşam yürüyüşü"))
        #expect(!FileManager.default.fileExists(atPath: context.url("diary/2026-10-01.md").path))
        #expect(try await store.computeDay(on: Self.day).id == Self.legacyFile)
    }
}

/// The share extension writes a shared line into a day kept in the legacy folder.
@Test func shareEntryAppendsToTheLegacyDayFile() async throws {
    let context = try ShareWritingContext()
    defer { context.clean() }
    let legacy = context.root.appendingPathComponent("\(LegacyVaultNames.dayFolder)/\(ShareWritingContext.day).md")
    try FileManager.default.createDirectory(at: legacy.deletingLastPathComponent(), withIntermediateDirectories: true)
    let before = "## Events\n- 09:00 Kahvaltı ^a1b2c3\n\n## \(LegacyVaultNames.diaryHeading)\nEski.\n"
    try Data(before.utf8).write(to: legacy)
    let written = await context.writer().writeToVault(context.entry("Kahve"), root: context.root)
    #expect(written?.lineID == "new123")
    let after = String(decoding: try Data(contentsOf: legacy), as: UTF8.self)
    #expect(after.contains("- 14:00 Kahve ^new123"))
    #expect(after.hasSuffix("## \(LegacyVaultNames.diaryHeading)\nEski.\n"))
    #expect(!FileManager.default.fileExists(atPath: context.dayFile.path))
}
