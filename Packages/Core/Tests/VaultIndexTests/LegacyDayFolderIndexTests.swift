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
}
