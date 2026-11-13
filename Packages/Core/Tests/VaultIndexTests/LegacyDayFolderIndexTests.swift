import Foundation
import Testing
import VaultFormat

@testable import VaultIndex

/// The legacy day folder these vaults still use (`LegacyVaultNames`).
private let legacy = LegacyVaultNames.dayFolder

/// Until a vault is migrated the index reads its days in both folders and both diary headings
/// (`vault-format.md`, "Eski adlar ve geçiş"); `Fixtures/migration/legacy-vault/source` holds both.
struct LegacyDayFolderIndexTests {
    private func indexedSource() throws -> VaultIndex {
        let index = try VaultIndex()
        try index.rebuild(vaultRoot: Fixtures.root().appendingPathComponent("migration/legacy-vault/source"))
        return index
    }

    @Test func daysUnderBothFoldersAreDays() throws {
        let index = try indexedSource()
        let days = try index.snapshot().files.filter { $0.kind == "day" }.map(\.path)
        #expect(
            days == [
                "diary/2026-10-05.md", "\(legacy)/2026-10-01.md", "\(legacy)/2026-10-02.md", "\(legacy)/2026-10-04.md",
                "\(legacy)/2026-10-05.md", "\(legacy)/2026-10-06.md",
            ])
        // A legacy day copy is neither indexed nor offered for a merge; the migration moves it.
        let result = try index.rebuild(
            vaultRoot: Fixtures.root().appendingPathComponent("migration/legacy-vault/source"))
        #expect(result.dayCopies.isEmpty)
        #expect(try !index.files().map(\.path).contains("\(legacy)/2026-10-06 2.md"))
        // A nested look-alike is a plain note, as under `diary/`.
        #expect(try index.snapshot().files.first { $0.path == "\(legacy)/eski/2026-10-07.md" }?.kind == "note")
    }

    @Test func theLegacyHeadingIsTheDiarySection() throws {
        let index = try indexedSource()
        let blocks = try index.blocks(on: CalendarDate("2026-10-02")!)
        // The first legacy heading opens the diary section; a fenced one is no heading; a second
        // one is a duplicate and opens an unknown section, as a second `## Diary` would.
        #expect(blocks.contains { $0.section == "Diary" && $0.text == "İlk paragraf." })
        #expect(blocks.contains { $0.section == "other" && $0.text == "İkinci başlık düz yazıdır." })
        #expect(
            try index.daySummaries(from: CalendarDate("2026-10-01")!, to: CalendarDate("2026-10-01")!).first?.diaryCount
                == 1)
    }

    @Test func aDayAnswersFromDiaryFirstThenTheLegacyFolder() throws {
        let index = try indexedSource()
        #expect(try index.day(on: CalendarDate("2026-10-05")!)?.file.path == "diary/2026-10-05.md")
        #expect(try index.day(on: CalendarDate("2026-10-01")!)?.file.path == "\(legacy)/2026-10-01.md")
        #expect(try index.day(on: CalendarDate("2026-10-09")!) == nil)
    }

    @Test func dayPathsOfBothFolders() {
        #expect(VaultLayout.dayPath(CalendarDate("2026-10-02")!) == "diary/2026-10-02.md")
        #expect(VaultLayout.day(ofDayPath: "diary/2026-10-02.md") == CalendarDate("2026-10-02"))
        #expect(VaultLayout.day(ofDayPath: "\(legacy)/2026-10-02.md") == CalendarDate("2026-10-02"))
        #expect(VaultLayout.isLegacyDayPath("\(legacy)/2026-10-02.md"))
        for path in [
            "\(LegacyVaultNames.diaryHeading)/2026-10-02.md", "diary/eski/2026-10-02.md", "diary/2026-10-02 2.md",
            "notes/2026-10-02.md",
        ] {
            #expect(VaultLayout.day(ofDayPath: path) == nil, "\(path)")
        }
    }

    /// A date held by both folders counts once, from `diary/`: day lists, summaries, on this day,
    /// an entity's timeline and usage, and a day's blocks never add the legacy file's lines.
    @Test func aDateInBothFoldersCountsOnceFromDiary() throws {
        let scratch = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: scratch) }
        try FileManager.default.copyItem(
            at: Fixtures.root().appendingPathComponent("migration/legacy-vault/source"), to: scratch)
        // The legacy file of this date holds an event with the same link and a diary paragraph.
        try Data("## Events\n- 08:00 [[Ada Kurt]] ile yürüyüş ^x1y2z3\n\n## Diary\nYeni.\n".utf8)
            .write(to: scratch.appendingPathComponent("diary/2026-10-01.md"))
        let index = try VaultIndex()
        try index.rebuild(vaultRoot: scratch)
        let day = CalendarDate("2026-10-01")!
        #expect(try index.daySummaries(from: day, to: day).map(\.file) == ["diary/2026-10-01.md"])
        #expect(try index.summaryDays(from: day, to: day).map(\.events) == [1])
        #expect(try index.blocks(on: day).allSatisfy { $0.file == "diary/2026-10-01.md" })
        #expect(try index.onThisDayInput(for: day).mentions.filter { $0.day == day }.count == 1)
        #expect(try index.entityTimeline(for: "people/Ada Kurt.md").map(\.block.file) == ["diary/2026-10-01.md"])
        #expect(try index.entityUsage().first { $0.file == "people/Ada Kurt.md" }?.totalCount == 1)
        // Both files stay in the index; only date-based views leave the legacy one out.
        #expect(try index.files().map(\.path).contains("\(legacy)/2026-10-01.md"))
    }
}
