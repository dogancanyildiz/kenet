import Foundation
import Testing
import VaultIndex

struct RelationsIndexTests {
    struct Expected: Decodable {
        let outgoing: [Relation]
        let incoming: [Relation]
    }

    @Test func graphFixture() throws {
        let root = try Fixtures.root().appendingPathComponent("vaults/graph")
        let expected = try JSONDecoder().decode(
            [String: Expected].self,
            from: Data(contentsOf: root.appendingPathComponent("relations.json")))
        let index = try VaultIndex()
        try index.rebuild(vaultRoot: root)
        for (path, value) in expected {
            let actual = try index.relations(of: path)
            #expect(actual.outgoing == value.outgoing)
            #expect(actual.incoming == value.incoming)
        }
        #expect(try index.explicitRelations(kinds: ["person", "book"]).count == 2)
        #expect(try index.explicitRelations(kinds: ["person"]).count == 1)
        #expect(try index.explicitRelations(kinds: []).isEmpty)
    }

    @Test func metadataRawUnresolvedAndBodyAreExcluded() throws {
        try withVault { root in
            try write(root, "people/Selin.md", "---\ntype: person\nname: Selin\n---\n")
            try write(
                root, "people/Deniz.md",
                """
                ---
                type: person
                name: "[[Selin]]"
                aliases: ["[[Selin]]"]
                qualifier: "[[Selin]]"
                related: ["[[Selin]]", "[[Yok]]", "[[Selin#^missing]]", "[[Deniz]]", "[[Not]]", "[[Spor]]"]
                raw: |
                  [[Selin]]
                mapping:
                  nested: "[[Selin]]"
                ---
                [[Selin]]
                """)
            try write(root, "notes/Not.md", "---\ntype: '[[Selin]]'\n---\n")
            try write(root, "goals/Spor.md", "---\ntype: goal\nname: Spor\n---\n")
            let index = try VaultIndex()
            try index.rebuild(vaultRoot: root)
            let rows = try index.relations(of: "people/Deniz.md")
            #expect(rows.outgoing.count == 1)
            #expect(rows.outgoing.first?.label == nil)
            #expect(rows.incoming.isEmpty)
            #expect(try index.relations(of: "people/Selin.md").incoming == rows.outgoing)
        }
    }
}
