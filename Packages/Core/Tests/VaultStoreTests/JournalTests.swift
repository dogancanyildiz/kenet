import Foundation
import Testing
import VaultFormat

struct JournalTests {
    @Test func journalNewReplacementAndEmptyHaveExactBytes() async throws {
        let vault = try StoreVault()
        defer { vault.remove() }
        try await vault.store.changingJournal(on: storeDate, to: "Kitap\nSu")
        #expect(try vault.bytes() == Data("---\ntype: journal\ndate: 2026-09-27\n---\n\n## Journal\nKitap\nSu\n".utf8))
        try vault.check()
        try await vault.store.changingJournal(on: storeDate, to: "Deniz")
        #expect(try vault.bytes() == Data("---\ntype: journal\ndate: 2026-09-27\n---\n\n## Journal\nDeniz\n".utf8))
        try vault.check()
        try await vault.store.changingJournal(on: storeDate, to: "")
        #expect(try vault.bytes() == Data("---\ntype: journal\ndate: 2026-09-27\n---\n\n## Journal\n".utf8))
        try vault.check()
    }

    @Test(arguments: ["# Kitap", "## Kitap", "```\nSu"])
    func structuralContentIsRejected(text: String) async throws {
        let vault = try StoreVault()
        defer { vault.remove() }
        try vault.write(storePath, "## Journal\nKitap\n")
        let before = try vault.bytes()
        await #expect(throws: EditError.sectionNotWritable) {
            try await vault.store.changingJournal(on: storeDate, to: text)
        }
        #expect(try vault.bytes() == before)
        #expect(try vault.index.files().isEmpty)
    }

    @Test func outsideBytesIncludingBOMAndMixedEndingsAreUnchanged() async throws {
        let vault = try StoreVault()
        defer { vault.remove() }
        let prefix = "\u{FEFF}---\r\ntype: note\ncustom: 20.0290\r---\r\n\r\n## Events\n- Su ^old\r\n## Journal\r\n"
        let suffix = "## Other\rDeniz"
        try vault.write(storePath, prefix + "Kitap\n\n" + suffix)
        try await vault.store.changingJournal(on: storeDate, to: "Selin")
        #expect(try vault.bytes() == Data((prefix + "Selin\r\n\n" + suffix).utf8))
        try vault.check()
    }
    @Test(arguments: ["Kitap\n\n", "Kitap\n \n\t", " \n\t"])
    func repeatedJournalSaveDoesNotGrowOrRewrite(text: String) async throws {
        let vault = try StoreVault()
        defer { vault.remove() }
        try vault.write(storePath, "## Journal\nSu\n\n## Notes\nDeniz\n")
        let first = try await vault.store.changingJournal(on: storeDate, to: text)
        let url = vault.root.appendingPathComponent(storePath)
        let before = try FileManager.default.attributesOfItem(atPath: url.path)
        let second = try await vault.store.changingJournal(on: storeDate, to: text)
        let after = try FileManager.default.attributesOfItem(atPath: url.path)
        #expect(first.serialized() == second.serialized())
        #expect(before[.modificationDate] as? Date == after[.modificationDate] as? Date)
        #expect(before[.systemFileNumber] as? NSNumber == after[.systemFileNumber] as? NSNumber)
        let content = text.hasPrefix("Kitap") ? "Kitap\n" : ""
        #expect(try vault.bytes() == Data(("## Journal\n" + content + "\n## Notes\nDeniz\n").utf8))
        try vault.check()
    }

}
