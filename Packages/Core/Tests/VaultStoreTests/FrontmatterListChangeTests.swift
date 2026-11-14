import Foundation
import Testing
import VaultFormat

@testable import VaultStore

/// `changingFrontmatterList`: the change is made to the list the file holds when the write runs.
struct FrontmatterListChangeTests {
    private struct Refused: Error {}
    private let path = "people/Ece Yalın.md"

    private func adding(_ text: String) -> @Sendable ([FrontmatterScalar]?) throws -> [FrontmatterLiteral] {
        { items in
            guard let items else { throw Refused() }
            return items.map { .text($0.text) } + [.text(text)]
        }
    }

    @Test func theChangeSeesTheListOnDisk() async throws {
        let vault = try StoreVault()
        defer { vault.remove() }
        try vault.write(path, "---\ntype: person\nname: Ece Yalın\naliases: [Ece]\n---\n")
        try vault.index.rebuild(vaultRoot: vault.root)
        // Another writer adds an alias the index has not seen yet.
        try vault.write(path, "---\ntype: person\nname: Ece Yalın\naliases: [Ece, 'E. Yalın']  # kısa\n---\nNot\n")
        try await vault.store.changingFrontmatterList(at: path, key: "aliases", change: adding("Ecoş"))
        let expected = "---\ntype: person\nname: Ece Yalın\naliases: [Ece, 'E. Yalın', Ecoş]  # kısa\n---\nNot\n"
        #expect(try vault.bytes(path) == Data(expected.utf8))
    }

    @Test func aMissingKeyAndAMissingFrontmatterAreEmptyLists() async throws {
        let vault = try StoreVault()
        defer { vault.remove() }
        try vault.write(path, "---\ntype: person\n---\nNot\n")
        try await vault.store.changingFrontmatterList(at: path, key: "aliases", change: adding("Ece"))
        #expect(try vault.bytes(path) == Data("---\ntype: person\naliases: [Ece]\n---\nNot\n".utf8))
        try vault.write("people/Mert Aksu.md", "Not\n")
        try await vault.store.changingFrontmatterList(at: "people/Mert Aksu.md", key: "aliases", change: adding("Mert"))
        #expect(try vault.bytes("people/Mert Aksu.md") == Data("---\naliases: [Mert]\n---\nNot\n".utf8))
    }

    @Test func aRefusedChangeAndAnUnreadableListWriteNothing() async throws {
        let vault = try StoreVault()
        defer { vault.remove() }
        let sources = [
            "---\ntype: person\naliases: [Ece]\n---\n",  // the change itself refuses
            "---\ntype: person\naliases:\n  kısa: Ece\n---\n",  // a mapping: no list to change
            "---\ntype: person\naliases: [Ece\n---\n",  // unreadable frontmatter
        ]
        for (index, source) in sources.enumerated() {
            try vault.write(path, source)
            await #expect(throws: Refused.self) {
                try await vault.store.changingFrontmatterList(at: path, key: "aliases") { items in
                    if index == 0 { throw Refused() }
                    guard let items else { throw Refused() }
                    return items.map { .text($0.text) }
                }
            }
            #expect(try vault.bytes(path) == Data(source.utf8))
        }
    }
}
