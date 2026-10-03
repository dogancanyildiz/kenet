import Foundation
import Testing
import VaultFormat
import VaultStore

struct StoreRegressionTests {
    @Test(arguments: ["", " \n\t"])
    func emptyJournalDoesNotCreateOrRewriteFiles(text: String) async throws {
        let vault = try StoreVault()
        defer { vault.remove() }
        let missing = try await vault.store.changingJournal(on: storeDate, to: text)
        #expect(missing.serialized().isEmpty)
        #expect(!FileManager.default.fileExists(atPath: vault.root.appendingPathComponent(storePath).path))
        #expect(try vault.index.files().isEmpty)
        try vault.write(storePath, "## Events\n- Su ^keepme\n")
        let attributes = try FileManager.default.attributesOfItem(
            atPath: vault.root.appendingPathComponent(storePath).path)
        let original = try vault.bytes()
        try await vault.store.changingJournal(on: storeDate, to: text)
        #expect(try vault.bytes() == original)
        let after = try FileManager.default.attributesOfItem(atPath: vault.root.appendingPathComponent(storePath).path)
        #expect(attributes[.modificationDate] as? Date == after[.modificationDate] as? Date)
        #expect(try vault.index.files().isEmpty)
    }

    @Test func horizontalRuleAndTrailingBlanksArePreserved() async throws {
        let vault = try StoreVault()
        defer { vault.remove() }
        try vault.write(storePath, "## Journal\nKitap\n\n\t\n## Notes\nSu\n")
        try await vault.store.changingJournal(on: storeDate, to: "Deniz\n---")
        #expect(try vault.bytes() == Data("## Journal\nDeniz\n---\n\n\t\n## Notes\nSu\n".utf8))
        try vault.check()
        try await vault.store.changingJournal(on: storeDate, to: "")
        #expect(try vault.bytes() == Data("## Journal\n\n\t\n## Notes\nSu\n".utf8))
        try vault.check()
    }

    @Test func reservedDirectoriesAreReadableButNotWritable() async throws {
        let vault = try StoreVault()
        defer { vault.remove() }
        for path in ["templates/person.md", "conflicts/Kitap.md"] {
            try vault.write(path, "- [ ] Su\n")
            let document = try await vault.store.document(at: path)
            await #expect(throws: VaultStoreError.invalidPath) {
                try await vault.store.changingText(of: document.bodyLines.tasks[0].block, at: path, to: "Kitap")
            }
            #expect(try vault.bytes(path) == Data("- [ ] Su\n".utf8))
        }
    }

    @Test func namesAreTrimmedAndBlankAliasesRemoved() async throws {
        let vault = try StoreVault()
        defer { vault.remove() }
        let path = try await vault.store.creatingEntity(
            kind: .person, name: " \nMert Aksu\t ", qualifier: " \n iş \n", aliases: ["", " ", "\t\n", "Mert"])
        #expect(path == "people/Mert Aksu (iş).md")
        #expect(
            try vault.bytes(path)
                == Data("---\ntype: person\nname: Mert Aksu\nqualifier: iş\naliases: [Mert]\n---\n".utf8))
        try vault.check()
    }

    @Test func filenameByteLimitIncludesExtensionAndQualifier() async throws {
        let vault = try StoreVault()
        defer { vault.remove() }
        let name = String(repeating: "Deniz", count: 50) + "Su"
        let path = try await vault.store.creatingEntity(kind: .person, name: name)
        #expect(URL(fileURLWithPath: path).lastPathComponent.utf8.count == 255)
        await #expect(throws: VaultStoreError.invalidName) {
            try await vault.store.creatingEntity(kind: .person, name: name + "x")
        }
        await #expect(throws: VaultStoreError.invalidName) {
            try await vault.store.creatingEntity(kind: .person, name: name, qualifier: "iş")
        }
        try vault.check()
    }

    @Test(arguments: [
        "Deniz\nArıkan", "Deniz\rArıkan", "Deniz\u{2028}Arıkan", "Deniz\0Arıkan", "Deniz\tArıkan",
        String(repeating: "ç", count: 127),
    ])
    func invalidNamesReturnStoreError(name: String) async throws {
        let vault = try StoreVault()
        defer { vault.remove() }
        await #expect(throws: VaultStoreError.invalidName) {
            try await vault.store.creatingEntity(kind: .person, name: name)
        }
        await #expect(throws: VaultStoreError.invalidName) {
            try await vault.store.creatingEntity(kind: .person, name: "Mert Aksu", qualifier: name)
        }
        #expect(try vault.index.files().isEmpty)
    }
}
