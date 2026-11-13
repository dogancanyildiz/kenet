import Foundation
import Testing
import VaultFormat

@testable import VaultIndex
@testable import VaultStore

/// The legacy day folder these vaults still use (`LegacyVaultNames`).
private let legacy = LegacyVaultNames.dayFolder

/// A vault not migrated yet keeps its days under the legacy folder. Reads and writes of such a day
/// go to that file and never start a second file under `diary/` (`vault-format.md`, "Eski adlar
/// ve geçiş").
struct LegacyDayWriteTests {
    private static let day = CalendarDate("2026-10-01")!
    private static let legacyDay =
        "---\ntype: journal\ndate: 2026-10-01\n---\n\n## Events\n- 09:00 Kahvaltı ^a1b2c3\n\n"
        + "## \(LegacyVaultNames.diaryHeading)\nEski yazı.\n"

    private struct Vault {
        let root: URL
        let store: VaultStore

        init(files: [String: String]) throws {
            root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
            for (path, text) in files {
                let url = root.appendingPathComponent(path)
                try FileManager.default.createDirectory(
                    at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
                try Data(text.utf8).write(to: url)
            }
            let index = try VaultIndex()
            try index.rebuild(vaultRoot: root)
            store = VaultStore(vaultRoot: root, index: index)
        }

        func text(_ path: String) throws -> String { try String(decoding: Data(contentsOf: url(path)), as: UTF8.self) }
        func exists(_ path: String) -> Bool { FileManager.default.fileExists(atPath: url(path).path) }
        func url(_ path: String) -> URL { root.appendingPathComponent(path) }
        func remove() { try? FileManager.default.removeItem(at: root) }
    }

    @Test func aDayOnlyInTheLegacyFolderIsReadAndWrittenThere() async throws {
        let vault = try Vault(files: ["\(legacy)/2026-10-01.md": Self.legacyDay])
        defer { vault.remove() }
        let path = "\(legacy)/2026-10-01.md"
        #expect(vault.store.dayFilePath(for: Self.day) == path)
        #expect(try await vault.store.dayDocument(for: Self.day).diaryText() == "Eski yazı.\n")

        try await vault.store.appendingDiary(on: Self.day, lines: ["Yeni satır."])
        try await vault.store.addingEvent(on: Self.day, text: "Yürüyüş")
        // The old heading stays; the text goes under it.
        #expect(try vault.text(path).hasSuffix("## \(LegacyVaultNames.diaryHeading)\nEski yazı.\n\nYeni satır.\n"))
        #expect(try vault.text(path).contains("- Yürüyüş"))

        let body = try await vault.store.dayDocument(for: Self.day).diaryText()
        try await vault.store.changingDiary(on: Self.day, to: "Değişti.", expectedBody: body)
        #expect(try await vault.store.dayDocument(for: Self.day).diaryText() == "Değişti.\n")

        // An event of the legacy file is changed and deleted by its own path, without staleTarget.
        let event = try #require(try await vault.store.dayDocument(for: Self.day).bodyLines.events.first)
        try await vault.store.deletingBlock(event.block, at: path)
        #expect(try !vault.text(path).contains("Kahvaltı"))

        #expect(!vault.exists("diary/2026-10-01.md"))
        #expect(!vault.exists("diary"))
    }

    @Test func diaryWinsAndANewDayGoesToDiary() async throws {
        let vault = try Vault(files: [
            "\(legacy)/2026-10-01.md": Self.legacyDay, "diary/2026-10-01.md": "## Diary\nYeni cihaz.\n",
        ])
        defer { vault.remove() }
        #expect(vault.store.dayFilePath(for: Self.day) == "diary/2026-10-01.md")
        let other = CalendarDate("2026-10-02")!
        #expect(vault.store.dayFilePath(for: other) == "diary/2026-10-02.md")
        try await vault.store.appendingDiary(on: other, lines: ["İlk."])
        #expect(vault.exists("diary/2026-10-02.md"))
        #expect(!vault.exists("\(legacy)/2026-10-02.md"))
    }

    /// A legacy day that waits for its download is still the day's file: writing waits too, and no
    /// file starts under `diary/`.
    @Test func aLegacyDayWaitingForDownloadBlocksANewDiaryFile() async throws {
        let vault = try Vault(files: ["\(legacy)/.2026-10-01.md.icloud": "yer tutucu"])
        defer { vault.remove() }
        #expect(vault.store.dayFilePath(for: Self.day) == "\(legacy)/2026-10-01.md")
        await #expect(throws: VaultStoreError.awaitingDownload(path: "\(legacy)/2026-10-01.md")) {
            try await vault.store.appendingDiary(on: Self.day, lines: ["Yeni."])
        }
        #expect(!vault.exists("diary/2026-10-01.md"))
    }

    /// Only the exact spelling of the legacy folder counts; a case variant is a plain folder.
    @Test func aCaseVariantOfTheLegacyFolderIsNotADayFolder() throws {
        let vault = try Vault(files: ["\(LegacyVaultNames.diaryHeading)/2026-10-01.md": Self.legacyDay])
        defer { vault.remove() }
        #expect(vault.store.dayFilePath(for: Self.day) == "diary/2026-10-01.md")
    }
}
