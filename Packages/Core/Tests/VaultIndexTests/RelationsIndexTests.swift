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
        let labels = Set(expected.values.flatMap { $0.outgoing + $0.incoming }.compactMap(\.label))
        #expect(try index.relationLabels() == ["eşi", "yazar"])
        #expect(Set(try index.relationLabels()) == labels)
    }

    /// The Graph query keeps a pair only when both ends are among the asked kinds; goals never count.
    @Test func explicitRelationsFilterTargetKinds() throws {
        try withVault { root in
            try write(
                root, ".app/types.json",
                """
                {"formatVersion":1,"types":[{"id":"book","folder":"books","name":{"tr":"Kitap","en":"Book"},\
                "plural":{"tr":"Kitaplar","en":"Books"},"icon":"book","fields":[]}]}
                """)
            try write(root, "people/Selin.md", "---\ntype: person\nname: Selin\n---\n")
            try write(
                root, "people/Deniz.md",
                """
                ---
                type: person
                name: Deniz
                related: ["[[Selin]]"]
                okuduğu: "[[Kitap]]"
                iş yeri: "[[Liman]]"
                hedef: "[[Spor]]"
                ---
                """)
            try write(root, "books/Kitap.md", "---\ntype: book\nname: Kitap\n---\n")
            try write(root, "places/Liman.md", "---\ntype: place\nname: Liman\n---\n")
            try write(root, "goals/Spor.md", "---\ntype: goal\nname: Spor\n---\n")
            let index = try VaultIndex()
            try index.rebuild(vaultRoot: root)
            func pairs(_ kinds: Set<String>) throws -> [[String]] {
                try index.explicitRelations(kinds: kinds).map { [$0.source, $0.target] }
            }
            let selin = ["people/Deniz.md", "people/Selin.md"]
            let book = ["people/Deniz.md", "books/Kitap.md"]
            let place = ["people/Deniz.md", "places/Liman.md"]
            #expect(try pairs(["person"]) == [selin])
            #expect(try pairs(["person", "book"]) == [book, selin])
            #expect(try pairs(["person", "place"]) == [selin, place])
            #expect(try pairs(["person", "goal"]) == [selin])
            #expect(try pairs(["book", "place"]).isEmpty)
            #expect(try pairs(["person", "book", "place", "goal"]).count == 3)
            // The page query is not filtered: every outgoing relation except the goal.
            #expect(
                try index.relations(of: "people/Deniz.md").outgoing.map(\.target).sorted() == [
                    "books/Kitap.md", "people/Selin.md", "places/Liman.md",
                ])
        }
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
            try write(root, "goals/Spor.md", "---\ntype: goal\nname: Spor\nrelated: [\"[[Selin]]\"]\n---\n")
            let index = try VaultIndex()
            try index.rebuild(vaultRoot: root)
            let rows = try index.relations(of: "people/Deniz.md")
            #expect(rows.outgoing.count == 1)
            #expect(rows.outgoing.first?.label == nil)
            #expect(rows.incoming.isEmpty)
            #expect(try index.relations(of: "people/Selin.md").incoming == rows.outgoing)
            #expect(try index.relationLabels().isEmpty)
        }
    }

    @Test func labelsAreUniqueSortedAndKeepEveryPair() throws {
        try withVault { root in
            try write(root, "people/Selin.md", "---\ntype: person\nname: Selin\neşi: \"[[Deniz]]\"\n---\n")
            try write(
                root, "people/Deniz.md",
                """
                ---
                type: person
                name: Deniz
                related: ["[[Selin]]"]
                eşi: "[[Selin]]"
                Komşu: ["[[Selin]]", "[[Selin]]"]
                arkadaş: "[[Yok]]"
                okuduğu: "[[Not]]"
                hedef: "[[Spor]]"
                ---
                """)
            try write(root, "notes/Not.md", "---\ntype: note\n---\n")
            try write(root, "goals/Spor.md", "---\ntype: goal\nname: Spor\nkoç: \"[[Selin]]\"\n---\n")
            let index = try VaultIndex()
            try index.rebuild(vaultRoot: root)
            // Plain `<` order puts `K` before `e`; unresolved, note and goal links give no label.
            #expect(try index.relationLabels() == ["Komşu", "eşi"])
            #expect(try index.explicitRelations(kinds: ["person"]).count == 1)
        }
    }
}
