import Foundation
import Testing
import VaultFormat
import VaultIndex

@testable import VaultStore

/// The graph query against an independent construction from the index snapshot (`GraphInput`).
struct GraphMentionsTests {
    static let kinds: Set<String> = ["person", "place"]

    @Test func sampleVaultMatchesSnapshotConstruction() throws {
        let index = try VaultIndex()
        try index.rebuild(vaultRoot: Fixtures.root().appendingPathComponent("vaults/sample"))
        let mentions = try index.graphMentions(kinds: Self.kinds)
        #expect(mentions == snapshotConstruction(try index.snapshot(), kinds: Self.kinds))
        #expect(mentions.days.count == 14)
        #expect(mentions.totals.count == 10)
    }

    /// The graph fixture's hand-counted totals and day mentions (`expected.json`): heading and
    /// frontmatter links count, a duplicate day file stays out of the index, and only the requested
    /// kinds count.
    @Test func graphFixtureMatchesHandCountedMentions() throws {
        let root = try Fixtures.root().appendingPathComponent("vaults/graph")
        let expected = try JSONDecoder().decode(
            Expectation.self, from: Data(contentsOf: root.appendingPathComponent("expected.json")))
        let index = try VaultIndex()
        try index.rebuild(vaultRoot: root)
        let mentions = try index.graphMentions(kinds: Self.kinds)
        #expect(mentions == snapshotConstruction(try index.snapshot(), kinds: Self.kinds))
        #expect(mentions.totals == expected.totals)
        #expect(
            mentions.days
                == expected.days.map { GraphMentions.Day(date: CalendarDate($0.date)!, mentions: $0.mentions) })
        let books = try index.graphMentions(kinds: ["book"])
        #expect(books.totals == ["books/Örnek Kitap.md": 1])
        #expect(books.days.map(\.mentions) == [["books/Örnek Kitap.md": 1]])
        #expect(try index.graphMentions(kinds: []).days.isEmpty)
        #expect(try index.snapshot().files.allSatisfy { $0.path != "journal/2026-10-03 2.md" })
    }

    @Test func syntheticVaultMatchesSnapshotConstruction() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let manifest = try SyntheticVault.generate(at: root, configuration: .compact)
        let index = try VaultIndex()
        try index.rebuild(vaultRoot: root)
        let snapshot = try index.snapshot()
        for kinds in [Self.kinds, ["person"], ["place", "goal"], ["note"], []] as [Set<String>] {
            #expect(try index.graphMentions(kinds: kinds) == snapshotConstruction(snapshot, kinds: kinds))
        }
        let mentions = try index.graphMentions(kinds: Self.kinds)
        #expect(mentions.days.count == SyntheticVault.Configuration.compact.days)
        let linked = try #require(manifest.linkedPersonPath)
        #expect(mentions.days.allSatisfy { $0.mentions[linked] != nil })
    }

    /// Every rule of the construction in one small vault, with the counts written out by hand.
    @Test func edgeCaseVaultCountsOnlyResolvedEntityLinksAndDaysFromDayFiles() throws {
        let vault = try StoreVault()
        defer { vault.remove() }
        try vault.write("people/Ada Test.md", "---\ntype: person\nname: Ada Test\n---\n[[Koru]] ve [[#Notlar]]\n")
        try vault.write("places/Koru.md", "---\ntype: place\nname: Koru\n---\n")
        try vault.write(
            "goals/Okuma.md",
            "---\ntype: goal\nname: Okuma\nkey: okuma\nperiod: day\nkind: boolean\ntarget: 1\nplace: \"[[Koru]]\"\n---\n"
        )
        try vault.write("notes/Plan.md", "[[Ada Test]] ile [[Ada Test|Ada]], [[Okuma]], [[Yok]]\n")
        try vault.write(
            "journal/2026-03-01.md",
            "## Events\n- 09:00 [[Ada Test]] [[Koru]] [[Plan]] [[Okuma]] [[Yok]]\n- 10:00 [[Ada Test]]\n")
        try vault.write("journal/2026-03-02.md", "## Events\n- 09:00 [[Plan]] [[Yok]]\n")
        try vault.write("journal/2026-03-03.md", "---\nplace: \"[[Koru]]\"\n---\n")
        try vault.write("journal/2026-02-30.md", "[[Ada Test]]\n")
        try vault.write("journal/arsiv/2026-03-01.md", "[[Koru]]\n")
        try vault.write("arsiv/2026-03-01.md", "[[Koru]]\n")
        try vault.index.rebuild(vaultRoot: vault.root)

        let mentions = try vault.index.graphMentions(kinds: Self.kinds)
        #expect(mentions == snapshotConstruction(try vault.index.snapshot(), kinds: Self.kinds))
        let ada = "people/Ada Test.md"
        let koru = "places/Koru.md"
        // Ada: her own heading link, two in the note, two on 03-01, one in the misdated file.
        // Koru: Ada, the goal's place, 03-01, the frontmatter of 03-03, two files outside `journal/<date>.md`.
        // Goal, note and unresolved targets never count; only real day files have a date.
        #expect(mentions.totals == [ada: 6, koru: 6])
        #expect(
            mentions.days == [
                .init(date: CalendarDate("2026-03-01")!, mentions: [ada: 2, koru: 1]),
                .init(date: CalendarDate("2026-03-03")!, mentions: [koru: 1]),
            ])
    }

    /// Edits through the store keep the incrementally maintained index answering like a rebuild.
    @Test func storeEditsMatchSnapshotConstructionAndRebuild() async throws {
        let vault = try StoreVault(sample: true)
        defer { vault.remove() }
        func check() throws {
            let rebuilt = try VaultIndex()
            try rebuilt.rebuild(vaultRoot: vault.root)
            let mentions = try vault.index.graphMentions(kinds: Self.kinds)
            #expect(mentions == snapshotConstruction(try vault.index.snapshot(), kinds: Self.kinds))
            #expect(mentions == (try rebuilt.graphMentions(kinds: Self.kinds)))
        }
        let before = try vault.index.graphMentions(kinds: Self.kinds)
        let day = CalendarDate("2026-12-01")!
        _ = try await vault.store.addingEvent(on: day, text: "[[Deniz Arıkan]] ile [[Liman Ofis]]")
        try check()
        let added = try vault.index.graphMentions(kinds: Self.kinds)
        #expect(
            added.days.last == .init(date: day, mentions: ["people/Deniz Arıkan.md": 1, "places/Liman Ofis.md": 1]))
        #expect(added.totals["people/Deniz Arıkan.md"] == (before.totals["people/Deniz Arıkan.md"] ?? 0) + 1)
        let renamed = try await vault.store.renamingEntity(at: "people/Deniz Arıkan.md", to: "Deniz Yeni")
        #expect(renamed.failures.isEmpty)
        try check()
        try FileManager.default.removeItem(at: vault.root.appendingPathComponent("journal/\(day).md"))
        try vault.index.refresh(vaultRoot: vault.root)
        try check()
    }

    private struct Expectation: Decodable {
        struct Day: Decodable {
            let date: String
            let mentions: [String: Int]
        }
        let totals: [String: Int]
        let days: [Day]
    }
}

/// The graph rule rebuilt from the index snapshot instead of SQL, with the entity list (the read
/// model's non-goal entities) narrowed to `kinds`: the app's construction from before the query
/// existed. Every resolved link counts, whatever its block; day mentions only from day files.
private func snapshotConstruction(_ snapshot: IndexSnapshot, kinds: Set<String>) -> GraphMentions {
    let known = Set(snapshot.entities.filter { kinds.contains($0.kind) }.map(\.file))
    let dates = Dictionary(
        uniqueKeysWithValues: snapshot.files.compactMap { file -> (String, CalendarDate)? in
            guard file.kind == "day", let date = file.date.flatMap(CalendarDate.init) else { return nil }
            return (file.path, date)
        })
    var totals: [String: Int] = [:]
    var days: [CalendarDate: [String: Int]] = [:]
    for link in snapshot.links {
        guard let target = link.resolvedFile, known.contains(target) else { continue }
        totals[target, default: 0] += 1
        if let date = dates[link.file] { days[date, default: [:]][target, default: 0] += 1 }
    }
    return GraphMentions(
        totals: totals,
        days: days.map { GraphMentions.Day(date: $0.key, mentions: $0.value) }.sorted { $0.date < $1.date })
}
