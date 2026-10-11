import Foundation
import Testing
import VaultFormat

@testable import VaultStore

struct JournalAppendTests {
    @Test func fixturesPersistAndIndexMatchesRebuild() async throws {
        let directory = try Fixtures.root().appendingPathComponent("write")
        let names = try FileManager.default.contentsOfDirectory(atPath: directory.path)
            .filter { $0.hasPrefix("journal-append-") }.sorted()
        for name in names {
            let vault = try StoreVault()
            defer { vault.remove() }
            let fixture = directory.appendingPathComponent(name)
            let input = try Data(contentsOf: fixture.appendingPathComponent("input.md"))
            let operation = try #require(
                JSONSerialization.jsonObject(with: Data(contentsOf: fixture.appendingPathComponent("operation.json")))
                    as? [String: Any])
            let section = try #require(operation["sections"] as? [String: Any])
            let lines = try #require(section["lines"] as? [String])
            if name != "journal-append-created" {
                try FileManager.default.createDirectory(
                    at: vault.root.appendingPathComponent("journal"), withIntermediateDirectories: true)
                try input.write(to: vault.root.appendingPathComponent(storePath))
            }
            if operation["expectedError"] != nil {
                await #expect(throws: EditError.self) {
                    try await vault.store.appendingJournal(on: storeDate, lines: lines)
                }
                #expect(try vault.bytes() == input)
                #expect(try vault.index.files().isEmpty)
            } else {
                let expected = try Data(contentsOf: fixture.appendingPathComponent("expected.md"))
                let after = try await vault.store.appendingJournal(on: storeDate, lines: lines)
                #expect(try vault.bytes() == expected, Comment(rawValue: name))
                #expect(Data(after.serialized()) == expected)
                if lines.contains(where: { !$0.allSatisfy(\.isWhitespace) }) { try vault.check() }
            }
        }
    }

    @Test func emptyMissingDayAndRepeatedBlocks() async throws {
        let vault = try StoreVault()
        defer { vault.remove() }
        for blank in [[], [""], [" ", "\t"], ["\n", "\r\n\u{2028}"]] as [[String]] {
            let untouched = try await vault.store.appendingJournal(on: storeDate, lines: blank)
            #expect(untouched.serialized().isEmpty)
            #expect(!FileManager.default.fileExists(atPath: vault.root.appendingPathComponent("journal").path))
        }
        #expect(try vault.index.files().isEmpty)
        let first = try await vault.store.appendingJournal(on: storeDate, lines: ["### Review", "· Kitap"])
        let second = try await vault.store.appendingJournal(on: storeDate, lines: ["### Review", "· Kitap"])
        #expect(second.serialized().starts(with: first.serialized()))
        #expect(second.lines.filter { $0.text == "### Review" }.count == 2)
        let normal = try StoreVault()
        defer { normal.remove() }
        let created = try await normal.store.changingJournal(on: storeDate, to: "Kitap")
        #expect(first.frontmatter == created.frontmatter)
        try vault.check()
    }

    @Test func externalChangeIsReadFromDisk() async throws {
        let vault = try StoreVault()
        defer { vault.remove() }
        try await vault.store.appendingJournal(on: storeDate, lines: ["Kitap"])
        let external = "## Journal\nDış yazı\n\n## Other\nSakla"
        try vault.write(storePath, external)
        let result = try await vault.store.appendingJournal(on: storeDate, lines: ["Su"])
        #expect(result.serialized().starts(with: Array("## Journal\nDış yazı\n".utf8)))
        let suffix = Array("\n## Other\nSakla".utf8)
        #expect(result.serialized().suffix(suffix.count).elementsEqual(suffix))
        #expect(result.lines.contains { $0.text == "Su" })
        try vault.check()
    }

    @Test func creationCollisionRetriesCurrentBytes() async throws {
        let vault = try StoreVault(linkFile: { source, destination in
            try Data("## Journal\nDış yazı\n".utf8).write(to: destination, options: .withoutOverwriting)
            try FileManager.default.linkItem(at: source, to: destination)
        })
        defer { vault.remove() }
        let result = try await vault.store.appendingJournal(on: storeDate, lines: ["Su"])
        #expect(result.serialized() == Array("## Journal\nDış yazı\n\nSu\n".utf8))
        #expect(try vault.bytes() == Data(result.serialized()))
        try vault.check()
    }

    @Test func userTextNeverBecomesARecord() async throws {
        let vault = try StoreVault()
        defer { vault.remove() }
        let existing = "## Tasks\n- [ ] Kitap ^t1\n\n## Journal\n- [ ] Su ^t2\n"
        try vault.write(storePath, existing)
        try vault.index.rebuild(vaultRoot: vault.root)
        let before = RawDocument(bytes: Array(existing.utf8))
        let sentence = "  - [ ] Yeni görev 📅 2026-09-27\n\tdevam\n## Tasks\n```\n> - [x] Alıntı"
        let after = try await vault.store.appendingJournal(on: storeDate, lines: [sentence])
        #expect(after.serialized().starts(with: Array(existing.utf8)))
        #expect(after.bodyLines.tasks == before.bodyLines.tasks)
        #expect(after.daySections.sections.count == 2)
        #expect(
            after.lines.dropFirst(before.lines.count).compactMap(\.text) == [
                "", "· - [ ] Yeni görev 📅 2026-09-27", "devam", "· ## Tasks", "· ```", "· > - [x] Alıntı",
            ])
        #expect(try vault.bytes() == Data(after.serialized()))
        try vault.check()
    }

    @Test func concurrentAppendsToAMissingDayAllLand() async throws {
        let vault = try StoreVault()
        defer { vault.remove() }
        try await withThrowingTaskGroup(of: Void.self) { group in
            for number in 0..<12 {
                group.addTask { try await vault.store.appendingJournal(on: storeDate, lines: ["Satır \(number)"]) }
            }
            try await group.waitForAll()
        }
        let written = RawDocument(bytes: Array(try vault.bytes()))
        let texts = written.lines.compactMap(\.text)
        #expect(texts.prefix(6) == ["---", "type: journal", "date: 2026-09-27", "---", "", "## Journal"])
        #expect(texts.filter { $0 == "## Journal" || $0 == "---" }.count == 3)
        #expect(Set(texts.filter { $0.hasPrefix("Satır ") }) == Set((0..<12).map { "Satır \($0)" }))
        #expect(texts.count == 6 + 12 * 2)
        try vault.check()
    }

    @Test func repeatedCreationCollisionIsStale() async throws {
        let vault = try StoreVault(linkFile: { _, _ in throw POSIXError(.EEXIST) })
        defer { vault.remove() }
        await #expect(throws: VaultStoreError.staleTarget) {
            try await vault.store.appendingJournal(on: storeDate, lines: ["Su"])
        }
        #expect(try vault.index.files().isEmpty)
    }
}
