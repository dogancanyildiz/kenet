import EntityRecognition
import Foundation
import GRDB
import Testing
import VaultFormat

@testable import VaultIndex

private final class RecognitionQueryLog: @unchecked Sendable {
    private let lock = NSLock()
    private var statements: [String] = []
    func append(_ text: String) { lock.withLock { statements.append(text) } }
    var selects: [String] { lock.withLock { statements.filter { $0.uppercased().contains("SELECT") } } }
}

@Test func sampleRecognitionEntitiesUsageAndUnlinkedText() throws {
    let index = try VaultIndex()
    let root = try Fixtures.root().appendingPathComponent("vaults/sample")
    try index.rebuild(vaultRoot: root)
    let log = RecognitionQueryLog()
    try index.database.read { db in db.trace { log.append($0.description) } }
    let entities = try index.knownEntities()
    try index.database.read { $0.trace(nil) }
    #expect(log.selects.count == 2)
    #expect(entities.count == 10)
    #expect(entities.filter { $0.kind == .person }.count == 6)
    #expect(entities.filter { $0.kind == .place }.count == 4)
    let deniz = try #require(entities.first { $0.name == "Deniz Arıkan" })
    #expect(deniz.aliases == ["Deniz", "Deniz abi"])
    #expect(deniz.comparisonKeys == ["deniz arıkan", "deniz", "deniz abi"])
    #expect(entities.filter { $0.name == "Mert Aksu" }.map(\.qualifier) == ["iş", nil])
    let usage = try index.entityUsage()
    #expect(usage.map(\.totalCount) == [6, 7, 5, 4, 2, 3, 3, 9, 10, 7])
    let denizUsage = try #require(usage.first { $0.file == deniz.file })
    #expect(denizUsage.lastDate == CalendarDate("2026-09-25"))
    // Deniz appears on September 14, 18, 21, 22 and 25; duplicate links on a day count once here.
    #expect(
        denizUsage.cooccurrences == [
            "places/Liman Ofis.md": 2, "places/Tepe Spor Salonu.md": 4, "people/Mert Aksu (iş).md": 2,
        ])
    let expectedCounts = [0, 0, 0, 0, 0, 0, 1, 0, 0, 0, 0, 0, 0, 0]
    for (offset, count) in expectedCounts.enumerated() {
        let date = CalendarDate(year: 2026, month: 9, day: 14 + offset)!
        let document = RawDocument(
            bytes: try Data(contentsOf: root.appendingPathComponent("journal/" + date.description + ".md")))
        let mentions = EntityRecognizer.recognize(
            String(decoding: document.serialized(), as: UTF8.self), entities: entities, usage: usage)
        #expect(mentions.count == count)
        if count == 1 {
            #expect(mentions[0].spelling == "Ev")
            #expect(mentions[0].isCertain)
            #expect(!mentions[0].isCaseMismatch)
            let lower = EntityRecognizer.recognize("ev temizli\u{011f}i", entities: entities)
            #expect(lower.count == 1)
            #expect(lower[0].isCaseMismatch)
            #expect(!lower[0].isCertain)
            #expect(mentions[0].position.line == 10)
            #expect(mentions[0].candidates.map(\.file) == ["places/Ev.md"])
        }
    }
}

@Test func usageCountsSourceDaysAndDistinctPairsAndRefresh() throws {
    try withVault { root in
        try write(
            root, "people/Deniz Arıkan.md", "---\ntype: person\naliases: [Deniz, Deniz abi]\n---\n[[Selin Korkmaz]]\n")
        try write(root, "people/Selin Korkmaz.md", "---\ntype: person\n---\n")
        try write(root, "places/Liman Ofis.md", "---\ntype: place\n---\n")
        try write(
            root, "journal/2026-09-14.md",
            "[[Deniz Arıkan]] [[Deniz Arıkan]] [[Liman Ofis]] [[Liman Ofis]] [[Selin Korkmaz]] [[Henüz Yazılmamış Not]]"
        )
        try write(root, "journal/2026-09-15.md", "[[Deniz Arıkan]] [[Liman Ofis]]")
        try write(root, "notes/Proje Fikirleri.md", "[[Deniz Arıkan]] [[Selin Korkmaz]]")
        let index = try VaultIndex()
        try index.rebuild(vaultRoot: root)
        let usage = try index.entityUsage()
        let deniz = try #require(usage.first { $0.file == "people/Deniz Arıkan.md" })
        #expect(deniz.totalCount == 4)
        #expect(deniz.lastDate == CalendarDate("2026-09-15"))
        #expect(deniz.cooccurrences == ["places/Liman Ofis.md": 2, "people/Selin Korkmaz.md": 1])
        let selin = try #require(usage.first { $0.file == "people/Selin Korkmaz.md" })
        #expect(selin.totalCount == 3)
        #expect(selin.lastDate == CalendarDate("2026-09-14"))
        #expect(selin.cooccurrences == ["people/Deniz Arıkan.md": 1, "places/Liman Ofis.md": 1])
        try write(root, "journal/2026-09-15.md", "Su")
        try index.update(paths: ["journal/2026-09-15.md"], vaultRoot: root)
        let refreshed = try index.entityUsage()
        let full = try VaultIndex()
        try full.rebuild(vaultRoot: root)
        #expect(refreshed == (try full.entityUsage()))
        #expect(try index.knownEntities() == full.knownEntities())
        #expect(refreshed.first { $0.file == deniz.file }?.lastDate == CalendarDate("2026-09-14"))
        #expect(refreshed.first { $0.file == deniz.file }?.cooccurrences["places/Liman Ofis.md"] == 1)
    }
}

@Test func unusedEntitiesHaveZeroUsage() throws {
    try withVault { root in
        try write(root, "people/Ece Yalın.md", "---\ntype: person\n---\n")
        let index = try VaultIndex()
        try index.rebuild(vaultRoot: root)
        #expect(try index.entityUsage() == [.init(file: "people/Ece Yalın.md")])
    }
}

@Test func duplicateBasenameLinkTargetResolvesToSelectedPerson() throws {
    try withVault { root in
        try write(root, "Archive/Baran.md", "eski not\n")
        try write(root, "people/Baran.md", "---\ntype: person\nname: Baran\n---\n")
        try write(root, "people/Ece Yalın.md", "---\ntype: person\nname: Ece Yalın\n---\n")
        let index = try VaultIndex()
        try index.rebuild(vaultRoot: root)
        let entities = try index.knownEntities()
        let baran = try #require(entities.first { $0.file == "people/Baran.md" })
        let ece = try #require(entities.first { $0.file == "people/Ece Yalın.md" })
        #expect(baran.linkTarget == "people/Baran")
        #expect(ece.linkTarget == "Ece Yalın")
        let text = "Baran ile kahve"
        let mentions = EntityRecognizer.recognize(text, entities: entities)
        #expect(mentions.count == 1 && mentions[0].isCertain)
        let linked = try EntityRecognizer.linking(text, mentions: mentions)
        #expect(linked == "[[people/Baran|Baran]] ile kahve")
        try write(root, "journal/2026-09-14.md", linked + "\n")
        try index.rebuild(vaultRoot: root)
        #expect(try index.links(to: "people/Baran.md").count == 1)
        #expect(try index.links(to: "Archive/Baran.md").isEmpty)
        #expect(try index.entityUsage().first { $0.file == "people/Baran.md" }?.totalCount == 1)
        let short = try EntityRecognizer.linking(
            "Ece Yalın", mentions: EntityRecognizer.recognize("Ece Yalın", entities: entities))
        #expect(short == "[[Ece Yalın]]")
    }
}
