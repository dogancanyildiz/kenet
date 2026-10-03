import Foundation
import GRDB
import Testing
import VaultFormat

@testable import VaultIndex

@Test func sampleSnapshotAndQueries() throws {
    let index = try VaultIndex()
    let fixtures = try Fixtures.root()
    let root = fixtures.appendingPathComponent("vaults/sample")
    try index.rebuild(vaultRoot: root)
    let snapshot = try index.snapshot()
    let expectedURL = fixtures.appendingPathComponent("index/sample/expected.json")
    let expected = try JSONDecoder().decode(IndexSnapshot.self, from: Data(contentsOf: expectedURL))
    #expect(snapshot == expected)
    #expect(snapshot.files.count == 30)
    #expect(snapshot.files.filter { $0.kind == "day" }.count == 14)
    #expect(snapshot.entities.filter { $0.kind == "person" }.count == 6)
    #expect(snapshot.entities.filter { $0.kind == "place" }.count == 4)
    #expect(snapshot.entities.filter { $0.kind == "goal" }.count == 3)
    #expect(snapshot.files.filter { $0.kind == "note" }.count == 3)
    #expect(snapshot.blocks.filter { $0.kind == "event" }.count == 40)
    #expect(snapshot.blocks.filter { $0.kind == "task" && $0.identifier != nil }.count == 22)
    #expect(snapshot.blocks.filter { $0.kind == "task" && $0.identifier == nil }.count == 2)
    #expect(snapshot.links.count == 61)
    #expect(Set(snapshot.links.map(\.target)).count == 14)
    #expect(snapshot.goalLogs.count == 31)
    #expect(try index.goalLogs(key: "spor").count == 6)
    #expect(try index.unresolvedLinks().map(\.target) == ["Henüz Yazılmamış Not"])
    #expect(
        snapshot.links.filter { $0.target == "Mert Aksu (iş)" }.allSatisfy {
            $0.resolvedFile == "people/Mert Aksu (iş).md"
        })
    #expect(try index.entities(named: "Deniz abi").map(\.file) == ["people/Deniz Arıkan.md"])
    #expect(try index.entities(named: "Mert Aksu").count == 2)
    #expect(try index.blocks(on: CalendarDate("2026-09-14")!).filter { $0.kind == "event" }.count == 3)
    #expect(try index.links(to: "places/Liman Ofis.md").count > 0)
    #expect(try index.search("Deniz").count > 0)
    #expect(snapshot.links.filter { $0.file == "notes/Toplantı Notları.md" && $0.target == "Deniz Arıkan" }.isEmpty)
    try index.rebuild(vaultRoot: root)
    #expect(try index.snapshot() == snapshot)
}

@Test func normalizationResolutionOwnershipAndTraversal() throws {
    try withVault { root in
        let sources = [
            ("z/Deniz Arıkan.md", "---\ntype: person\n---\n- [ ] Su ^same\n"),
            ("a/Deniz Arıkan.md", "---\ntype: person\naliases: [Deniz]\n---\n- [ ] Kitap ^same\n- [ ] Su ^same\n"),
            ("people/Işık.md", "---\ntype: person\nname: Işık\n---\n"),
            ("places/Çınaraltı Kafe.md".decomposedStringWithCanonicalMapping, "---\ntype: place\n---\n"),
            (
                "notes/Proje Fikirleri.md",
                "[[Deniz Arıkan]] [[z/Deniz Arıkan.md]] [[işık]] [[ışık]] [[Çınaraltı Kafe]] [[#Başlık]]\n"
            ),
            ("journal/2026-01-01.md", "## Events\n- 9:05 Su ^event\n"),
            ("journal/2026-01-01 2.md", "---\ntype: journal\n---\nKitap\n"),
            ("notes/Okuma Listesi.md", "---\ntype: person\ntype: place\n---\nSu\n"),
            (".hidden/Su.md", "Su"), ("templates/Kitap.md", "Kitap"),
            ("conflicts/Spor.md", "Spor"), ("notes/.hidden/Su.md", "Su"),
        ]
        for source in sources.reversed() { try write(root, source.0, source.1) }
        try Data([0xff]).write(to: root.appendingPathComponent("notes/Su.md"))
        let index = try VaultIndex()
        try index.rebuild(vaultRoot: root)
        let snapshot = try index.snapshot()
        #expect(snapshot.files.count == 9)
        #expect(snapshot.files.first { $0.path == "notes/Su.md" }?.readable == false)
        #expect(snapshot.blocks.filter { $0.file == "notes/Su.md" }.isEmpty)
        #expect(snapshot.files.first { $0.path == "notes/Okuma Listesi.md" }?.kind == "note")
        #expect(snapshot.blocks.contains { $0.file == "notes/Okuma Listesi.md" && $0.text == "Su" })
        #expect(snapshot.files.first { $0.path == "journal/2026-01-01 2.md" }?.kind == "note")
        #expect(snapshot.files.first { $0.path == "journal/2026-01-01.md" }?.kind == "day")
        #expect(
            snapshot.blocks.filter { $0.identifier == "same" && $0.ownsIdentifier }.map(\.file) == ["a/Deniz Arıkan.md"]
        )
        #expect(snapshot.blocks.first { $0.identifier == "same" && $0.ownsIdentifier }?.firstLine == 5)
        #expect(snapshot.links.first { $0.target == "Deniz Arıkan" }?.resolvedFile == "a/Deniz Arıkan.md")
        #expect(snapshot.links.first { $0.target == "z/Deniz Arıkan" }?.resolvedFile == "z/Deniz Arıkan.md")
        #expect(snapshot.links.first { $0.target == "işık" }?.resolvedFile == "people/Işık.md")
        #expect(snapshot.links.first { $0.target == "ışık" }?.resolvedFile == nil)
        #expect(snapshot.links.first { $0.target == "Çınaraltı Kafe" }?.resolvedFile == "places/Çınaraltı Kafe.md")
        #expect(snapshot.files.contains { Array($0.path.utf8) == Array("places/Çınaraltı Kafe.md".utf8) })
        #expect(snapshot.links.first { $0.target.isEmpty }?.resolvedFile == "notes/Proje Fikirleri.md")
        #expect(try index.entities(named: "işık").count == 1)
        #expect(try index.entities(named: "ışık").isEmpty)
        try withVault { other in
            for source in sources { try write(other, source.0, source.1) }
            try Data([0xff]).write(to: other.appendingPathComponent("notes/Su.md"))
            try index.rebuild(vaultRoot: other)
            #expect(try index.snapshot() == snapshot)
        }
    }
}
