import Foundation
import Testing
import VaultFormat

@testable import VaultIndex

@Test func dayIdentityRequiresRootJournalAndOverridesType() throws {
    try withVault { root in
        try write(root, "notes/2026-01-01.md", "---\ndate: 2026-01-01\ngoals:\n  su: 8\n---\nSu")
        try write(root, "journal/2026-01-01.md", "---\ntype: person\ngoals:\n  kitap: 20\n---\n## Events\n- Su")
        let index = try VaultIndex()
        try index.rebuild(vaultRoot: root)
        let snapshot = try index.snapshot()
        #expect(snapshot.files.map(\.kind) == ["day", "note"])
        #expect(snapshot.entities.isEmpty)
        #expect(snapshot.goalLogs.map(\.key) == ["kitap"])
        #expect(try index.blocks(on: CalendarDate("2026-01-01")!).map(\.kind) == ["event"])
    }
}

@Test func invalidUTF8WithValidSyntaxProducesNoContent() throws {
    try withVault { root in
        let bytes = Data("---\ntype: person\nname: Deniz Arıkan\n---\n- [ ] Kitap ^task\n[[Su]]\n".utf8) + Data([0xff])
        try bytes.write(to: root.appendingPathComponent("Su.md"))
        let index = try VaultIndex()
        try index.rebuild(vaultRoot: root)
        let snapshot = try index.snapshot()
        #expect(snapshot.files.count == 1)
        #expect(snapshot.files[0].kind == "note" && !snapshot.files[0].readable)
        #expect(snapshot.blocks.isEmpty && snapshot.entities.isEmpty && snapshot.links.isEmpty)
        #expect(try index.search("Kitap").isEmpty)
    }
}

@Test func entityNamesAliasesAndIncomingPathsUseNFCAndFTS() throws {
    try withVault { root in
        let name = "Selin Korkmaz".decomposedStringWithCanonicalMapping
        let alias = "Çınaraltı Kafe".decomposedStringWithCanonicalMapping
        try write(root, "people/Deniz Arıkan.md", "---\ntype: person\nname: \(name)\naliases: [\(alias)]\n---\n")
        try write(root, "notes/Su.md", "[[PEOPLE/Deniz Arıkan]] [[/people/Deniz Arıkan]] [[./people/Deniz Arıkan]]")
        let index = try VaultIndex()
        try index.rebuild(vaultRoot: root)
        let snapshot = try index.snapshot()
        #expect(snapshot.entities[0].name == "Selin Korkmaz")
        #expect(try index.entities(named: "Deniz Arıkan").isEmpty)
        #expect(try index.entities(named: "Selin Korkmaz").count == 1)
        #expect(try index.search("Selin").map(\.file) == ["people/Deniz Arıkan.md"])
        #expect(try index.search("Çınaraltı").map(\.file) == ["people/Deniz Arıkan.md"])
        #expect(Array(snapshot.aliases[0].comparisonKey.utf8) == Array("çınaraltı kafe".utf8))
        #expect(Array(comparisonKey("Çınaraltı".decomposedStringWithCanonicalMapping).utf8) == Array("çınaraltı".utf8))
        #expect(snapshot.links.allSatisfy { $0.resolvedFile == "people/Deniz Arıkan.md" })
        #expect(try index.links(to: "people/Deniz Arıkan.md".decomposedStringWithCanonicalMapping).count == 3)
        #expect(snapshot.links.allSatisfy { $0.targetKey == "people/deniz arıkan" })
    }
}

@Test func traversalOnlyExcludesRootSpecialFoldersAndMarkdownExtension() throws {
    try withVault { root in
        for path in [
            "templates/Su.md", "conflicts/Su.md", ".hidden/Su.md", "notes/.hidden/Su.md", "Su.txt", "Su.json", "Su.MD",
        ] {
            try write(root, path, "Kitap")
        }
        for path in ["notes/templates/Su.md", "notes/conflicts/Kitap.md", "notes/Proje Fikirleri.md"] {
            try write(root, path, "Su")
        }
        let index = try VaultIndex()
        try index.rebuild(vaultRoot: root)
        #expect(
            try index.files().map(\.path) == [
                "notes/Proje Fikirleri.md", "notes/conflicts/Kitap.md", "notes/templates/Su.md",
            ])
    }
}

@Test func emptyNamesFallBackToBasenameAndSearchEscapesUserText() throws {
    try withVault { root in
        try write(root, "people/Deniz Arıkan.md", "---\ntype: person\nname: \"\"\n---\n")
        try write(root, "people/Selin Korkmaz.md", "---\ntype: person\nname: \"   \"\n---\n")
        try write(root, "notes/Kitap.md", "Kitap Su")
        let index = try VaultIndex()
        try index.rebuild(vaultRoot: root)
        #expect(try index.entities(named: "Deniz Arıkan").count == 1)
        #expect(try index.entities(named: "Selin Korkmaz").count == 1)
        for query in ["Ahmet'in", "C++", "\"kitap", "AND"] { _ = try index.search(query) }
        #expect(try index.search("   ").isEmpty)
        #expect(try index.search("kit").count == 1)
        #expect(try index.search("Kitap S").count == 1)
        #expect(searchExpression("Su \"kitap") == "\"Su\" \"\"\"kitap\"*")
    }
}

@Test func headingBlocksExcludeSectionLabelsAndKeepNestedHeadingsOutsideFences() throws {
    try withVault { root in
        try write(
            root, "journal/2026-01-01.md",
            """
            ## Tasks
            - [ ] Su
            ## Events
            - Kitap
            ## Journal
            Su
            ### Kitap
            Kitap
            ```
            ### Su
            ```
            ## Spor
            Spor
            """)
        let index = try VaultIndex()
        try index.rebuild(vaultRoot: root)
        let blocks = try index.snapshot().blocks
        #expect(blocks.filter { $0.kind == "heading" }.map(\.text) == ["Kitap", "Spor"])
        #expect(blocks.filter { $0.kind == "heading" }.map(\.headingLevel) == [3, 2])
        #expect(blocks.filter { $0.kind == "paragraph" }.map(\.text) == ["Su", "Kitap\n```\n### Su\n```", "Spor"])
        #expect(try index.search("Events").isEmpty)
        #expect(blocks.first { $0.kind == "heading" }?.section == "Journal")
    }
}

@Test func incomingLinkQueryNormalizesDecomposedPaths() throws {
    try withVault { root in
        try write(root, "places/Çınaraltı Kafe.md", "Su")
        try write(root, "notes/Su.md", "[[places/Çınaraltı Kafe]]")
        let index = try VaultIndex()
        try index.rebuild(vaultRoot: root)
        let query = "places/Çınaraltı Kafe.md".decomposedStringWithCanonicalMapping
        #expect(Array(query.utf8) != Array("places/Çınaraltı Kafe.md".utf8))
        #expect(try index.links(to: query).map(\.file) == ["notes/Su.md"])
    }
}
