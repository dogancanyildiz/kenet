import Foundation
import Testing
import VaultFormat

@testable import VaultIndex

struct FileQueryTests {
    @Test func blocksAndLinksInFileMatchSnapshotSlice() throws {
        try withVault { root in
            try write(root, "people/Deniz Example.md", "---\ntype: person\nname: Deniz Example\n---\n")
            try write(
                root, "journal/2026-10-01.md",
                """
                ---
                type: journal
                date: 2026-10-01
                goals:
                  kitap: 3
                place: "[[Deniz Example]]"
                ---
                ## Tasks
                - [ ] Buy flour ^task1
                ## Events
                - 09:00 Coffee with [[Deniz Example]] ^evt1
                ## Journal
                Morning note mentioning [[Deniz Example]].
                """)
            try write(root, "notes/Other.md", "- [ ] Unrelated ^other\n")
            let index = try VaultIndex()
            try index.rebuild(vaultRoot: root)
            let snapshot = try index.snapshot()
            let day = "journal/2026-10-01.md"
            let dayBlocks = try index.blocks(inFile: day)
            let dayLinks = try index.links(inFile: day)
            #expect(dayBlocks == snapshot.blocks.filter { $0.file == day })
            #expect(dayLinks == snapshot.links.filter { $0.file == day })
            #expect(dayBlocks.map(\.kind) == ["task", "event", "paragraph"])
            #expect(dayLinks.count == 3)
            #expect(try index.blocks(inFile: "notes/Other.md").map(\.identifier) == ["other"])
            #expect(try index.links(inFile: "notes/Other.md").isEmpty)
            #expect(try index.blocks(inFile: "missing.md").isEmpty)
            #expect(try index.links(inFile: "missing.md").isEmpty)
        }
    }

    @Test func contentsOfFileMatchesSnapshotGrouping() throws {
        try withVault { root in
            try write(
                root, "people/Deniz Example.md",
                """
                ---
                type: person
                name: Deniz Example
                aliases: [Deniz]
                ---
                """)
            try write(
                root, "journal/2026-10-02.md",
                """
                ---
                type: journal
                date: 2026-10-02
                goals:
                  su: 2
                ---
                ## Events
                - 10:00 Walk ^w1
                """)
            let index = try VaultIndex()
            try index.rebuild(vaultRoot: root)
            let snapshot = try index.snapshot()
            let person = try #require(try index.contents(ofFile: "people/Deniz Example.md"))
            #expect(person.file == snapshot.files.first { $0.path == person.file.path })
            #expect(person.entity == snapshot.entities.first { $0.file == person.file.path })
            #expect(person.aliases.map(\.name) == ["Deniz"])
            #expect(person.blocks.isEmpty)
            #expect(person.links.isEmpty)
            #expect(person.goalLogs.isEmpty)

            let day = try #require(try index.contents(ofFile: "journal/2026-10-02.md"))
            #expect(day.entity == nil)
            #expect(day.blocks.map(\.kind) == ["event"])
            #expect(day.goalLogs.map(\.key) == ["su"])
            #expect(try index.contents(ofFile: "missing.md") == nil)
        }
    }
}
