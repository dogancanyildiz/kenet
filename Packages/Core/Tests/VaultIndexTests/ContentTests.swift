import Foundation
import GRDB
import Testing
import VaultFormat

@testable import VaultIndex

@Test func continuationsNestedLinksSectionsAndGoalValues() throws {
    try withVault { root in
        try write(
            root, "journal/2026-01-01.md",
            """
            ---
            goals:
              spor: TRUE
              kitap: 20.50
              su: "Su"
            place: "[[Çınaraltı Kafe]]"
            ---
            ## Tasks
            - [?] Kitap ^parent
              - [/] [[Su]] ^child
              devam
            ## Journal
            Su
            Kitap

            ```
            [[Su]]
            ```
            ## Other
            Spor
            """)
        let index = try VaultIndex()
        try index.rebuild(vaultRoot: root)
        let snapshot = try index.snapshot()
        #expect(snapshot.blocks.map(\.kind) == ["task", "task", "paragraph", "paragraph", "heading", "paragraph"])
        #expect(snapshot.blocks[0].lastLine == 11)
        #expect(snapshot.blocks[0].status == "unknown")
        #expect(snapshot.blocks[0].rawStatus == "?")
        #expect(snapshot.blocks[1].status == "inProgress")
        #expect(snapshot.blocks[2].text == "Su\nKitap")
        #expect(snapshot.blocks[2].section == "Journal")
        #expect(snapshot.blocks[5].section == "other")
        #expect(snapshot.links.count == 2)
        #expect(snapshot.links[0].key == "place" && snapshot.links[0].block == nil)
        #expect(snapshot.links[1].block == 1)
        #expect(snapshot.goalLogs.map(\.kind) == ["number", "boolean", "raw"])
        #expect(snapshot.goalLogs.map(\.value) == ["20.50", "true", "\"Su\""])
        #expect(try index.search("Su").count == 3)
    }
}

@Test func digestUsesExactBytesAndFTSPreservesDiacritics() throws {
    #expect(ByteDigest.hex(Data()) == "e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855")
    #expect(ByteDigest.hex(Data("abc".utf8)) == "ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad")
    try withVault { root in
        try write(root, "Su.md", "Çınaraltı")
        let index = try VaultIndex()
        try index.rebuild(vaultRoot: root)
        #expect(try index.search("Çınaraltı").count == 1)
        #expect(try index.search("Cınaraltı").isEmpty)
        let before = try index.files()[0]
        try write(root, "Su.md", "Çınaraltı\r\n")
        try index.rebuild(vaultRoot: root)
        let after = try index.files()[0]
        #expect(before.digest != after.digest)
        #expect(after.size == Data("Çınaraltı\r\n".utf8).count)
    }
}

@Test func pathOrderingUsesUnicodeScalarsAndSnapshotKeepsSourceBytes() throws {
    try withVault { root in
        let first = "\u{E000}/Su.md"
        let second = "\u{10000}/Su.md"
        try write(root, second, "- [ ] Su ^same")
        try write(root, first, "- [ ] Kitap ^same")
        try write(root, "notes/Kitap.md", "[[Su]]")
        let index = try VaultIndex()
        try index.rebuild(vaultRoot: root)
        #expect(try index.files().map(\.path) == ["notes/Kitap.md", first, second])
        let snapshot = try index.snapshot()
        #expect(snapshot.links[0].resolvedFile == first)
        #expect(snapshot.blocks.filter { $0.ownsIdentifier }.map(\.file) == [first])
        #expect(snapshot.blocks[0].firstLine == 1 && snapshot.blocks[0].lastLine == 1)
    }
}
