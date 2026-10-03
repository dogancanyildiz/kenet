import Foundation
import Testing
import VaultStore

struct EntityTests {
    @Test func templateFieldsAndBodyArePreserved() async throws {
        let vault = try StoreVault(sample: true)
        defer { vault.remove() }
        try vault.write(
            "templates/person.md", "---\ntype: person # Su\ncustom: 20.0290\naliases: [Deniz]\n---\n\nKitap\n")
        let path = try await vault.store.creatingEntity(
            kind: .person, name: "Mert Aksu", qualifier: "üniversite", aliases: ["Mert"])
        #expect(path == "people/Mert Aksu (üniversite).md")
        #expect(
            try vault.bytes(path)
                == Data(
                    "---\ntype: person # Su\ncustom: 20.0290\naliases: [Mert]\nname: Mert Aksu\nqualifier: üniversite\n---\n\nKitap\n"
                        .utf8))
        #expect(try vault.index.entities(named: "Mert Aksu").count == 3)
        #expect(try vault.index.entities(named: "Mert").map(\.file) == ["people/Mert Aksu (iş).md", path])
        try vault.check()
    }

    @Test func missingAndWrongTypeTemplatesUseMinimalFrontmatter() async throws {
        let vault = try StoreVault()
        defer { vault.remove() }
        let person = try await vault.store.creatingEntity(kind: .person, name: "Deniz Arıkan")
        #expect(try vault.bytes(person) == Data("---\ntype: person\nname: Deniz Arıkan\n---\n".utf8))
        try vault.write("templates/place.md", "---\ntype: person\ncustom: Kitap\n---\nSu\n")
        let place = try await vault.store.creatingEntity(kind: .place, name: "Liman Ofis")
        #expect(try vault.bytes(place) == Data("---\ntype: place\nname: Liman Ofis\n---\n".utf8))
        try vault.check()
    }

    @Test func qualifiedSecondEntityAndLinksAppearInIndex() async throws {
        let random = CountingRandom()
        let vault = try StoreVault(random: { random.next() })
        defer { vault.remove() }
        try await vault.store.addingEvent(on: storeDate, text: "[[Mert Aksu]] [[Mert Aksu (iş)|Mert]]")
        #expect(try vault.index.unresolvedLinks().count == 2)
        let first = try await vault.store.creatingEntity(kind: .person, name: "Mert Aksu")
        await #expect(throws: VaultStoreError.nameTaken) {
            try await vault.store.creatingEntity(kind: .person, name: "MERT AKSU")
        }
        let second = try await vault.store.creatingEntity(
            kind: .person, name: "Mert Aksu", qualifier: "iş", aliases: [])
        #expect(try vault.index.entities(named: "Mert Aksu").map(\.file) == [second, first])
        #expect(try vault.index.links(to: first).count == 1)
        #expect(try vault.index.links(to: second).count == 1)
        #expect(try vault.index.unresolvedLinks().isEmpty)
        try vault.check()
    }

    @Test func sanitizingPreservesDisplayNameAndChecksDiskAcrossDirectories() async throws {
        let vault = try StoreVault()
        defer { vault.remove() }
        let name = "  Deniz /\\:*?\"<>|#^[]  Arıkan  "
        let path = try await vault.store.creatingEntity(kind: .person, name: name)
        #expect(path == "people/Deniz Arıkan.md")
        #expect(
            try vault.index.entities(named: name.trimmingCharacters(in: .whitespacesAndNewlines)).first?.name
                == name.trimmingCharacters(in: .whitespacesAndNewlines))
        // An external file has not reached the index yet.
        try vault.write("notes/SELIN KORKMAZ.md", "Su")
        await #expect(throws: VaultStoreError.nameTaken) {
            try await vault.store.creatingEntity(kind: .person, name: "Selin Korkmaz")
        }
        let before = try vault.bytes("notes/SELIN KORKMAZ.md")
        #expect(before == Data("Su".utf8))
        // NFC equivalence is independent of filesystem spelling.
        let decomposed = "Baran Tunç".decomposedStringWithCanonicalMapping + ".md"
        try vault.write("notes/" + decomposed, "Kitap")
        let diskNames = try FileManager.default.contentsOfDirectory(
            atPath: vault.root.appendingPathComponent("notes").path)
        #expect(diskNames.contains { $0.utf8.elementsEqual(decomposed.utf8) })
        await #expect(throws: VaultStoreError.nameTaken) {
            try await vault.store.creatingEntity(kind: .person, name: "Baran Tunç")
        }
    }

    @Test func invalidNamesAndEmptyQualifierAreRejected() async throws {
        let vault = try StoreVault()
        defer { vault.remove() }
        for name in [" ", "/\\:*?\"<>|#^[]", ".", ".."] {
            await #expect(throws: VaultStoreError.invalidName) {
                try await vault.store.creatingEntity(kind: .person, name: name)
            }
        }
        await #expect(throws: VaultStoreError.invalidName) {
            try await vault.store.creatingEntity(kind: .person, name: "Deniz Arıkan", qualifier: " ")
        }
    }
}
