import Foundation
import Testing
import VaultFormat
import VaultIndex

@testable import VaultStore

/// The entity timeline and last-encounter queries against the snapshot construction they replaced
/// in the app (`EntityTimeline.build(snapshot:)`).
struct EntityTimelineQueryTests {
    @Test func sampleVaultMatchesSnapshotConstruction() throws {
        let index = try VaultIndex()
        try index.rebuild(vaultRoot: Fixtures.root().appendingPathComponent("vaults/sample"))
        try expectConstruction(index, asOf: ["2026-09-01", "2026-09-21", "2026-10-04", "2027-01-01"])
        let deniz = try index.entityTimeline(for: "people/Deniz Arıkan.md")
        #expect(Set(deniz.map(\.date)).count == 5 && deniz.count == 6)
        #expect(try index.lastEncounters(asOf: CalendarDate("2026-10-04")!)["people/Deniz Arıkan.md"] == deniz[0].date)
    }

    @Test func syntheticVaultMatchesSnapshotConstruction() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let manifest = try SyntheticVault.generate(at: root, configuration: .compact)
        let index = try VaultIndex()
        try index.rebuild(vaultRoot: root)
        try expectConstruction(index, asOf: ["2026-09-14", "2026-09-30", "2026-10-05"])
        // The linked person is in an event and a Journal paragraph every day: two rows a day.
        let linked = try index.entityTimeline(for: try #require(manifest.linkedPersonPath))
        #expect(linked.count == 2 * SyntheticVault.Configuration.compact.days)
        #expect(linked.first?.date == manifest.endDate)
    }

    /// Every rule of the construction in one small vault, with the rows written out by hand.
    @Test func edgeCaseVaultCountsOnlyDayEventsAndJournalParagraphs() throws {
        let vault = try StoreVault()
        defer { vault.remove() }
        try vault.write("people/Ada Test.md", "---\ntype: person\nname: Ada Test\naliases: [Ada]\n---\n[[Koru]]\n")
        try vault.write("places/Koru.md", "---\ntype: place\nname: Koru\n---\n")
        try vault.write("notes/Plan.md", "## Events\n- 09:00 [[Ada Test]]\n\n## Journal\n[[Ada Test]] planı.\n")
        try vault.write(
            "journal/2026-03-01.md",
            """
            ---
            type: journal
            date: 2026-03-01
            with: "[[Ada Test]]"
            ---

            ## Tasks
            - [ ] [[Ada Test]] ara

            ## Events
            - 09:00 [[Ada Test]] ve [[Ada Test|Ada]] [[Koru]]'da, [[Yok]] yoktu
            - 10:00 [[Ada]] ile yürüyüş, Ada Test de vardı

            ## Journal
            ### [[Ada Test]] başlığı
            [[Ada Test|görünen]] ile uzun bir gün.

            ## Notlar
            [[Ada Test]] başka bölümde.
            """)
        try vault.write("journal/2026-03-02.md", "## Events\n- 08:00 [[Koru]]\n\n## Journal\n[[Ada Test]] yine.\n")
        try vault.write("journal/2026-03-05.md", "## Events\n- 08:00 [[Ada Test]] sonra\n")
        try vault.write("journal/2026-02-30.md", "## Events\n- 08:00 [[Ada Test]]\n")
        try vault.write("journal/arsiv/2026-03-03.md", "## Events\n- 08:00 [[Ada Test]]\n")
        try vault.write("arsiv/2026-03-04.md", "## Events\n- 08:00 [[Ada Test]]\n")
        try vault.index.rebuild(vaultRoot: vault.root)
        try expectConstruction(vault.index, asOf: ["2026-02-28", "2026-03-01", "2026-03-03", "2026-03-05"])

        let ada = "people/Ada Test.md"
        let koru = "places/Koru.md"
        // Ada: the 03-05 event, the 03-02 paragraph, and on 03-01 the paragraph and the 09:00 event
        // once despite two links. Not the task, the heading, the frontmatter, the `Notlar` paragraph,
        // the alias link or plain name, the note, the misdated file or the files outside `journal/`.
        let rows = try vault.index.entityTimeline(for: ada)
        #expect(rows.map(\.date.description) == ["2026-03-05", "2026-03-02", "2026-03-01", "2026-03-01"])
        #expect(rows.map(\.block.kind) == ["event", "paragraph", "paragraph", "event"])
        #expect(rows[2].block.text == "[[Ada Test|görünen]] ile uzun bir gün.")
        // The row keeps every link of its block, the unresolved one too, so its text draws whole.
        #expect(rows[3].links.map(\.target) == ["Ada Test", "Ada Test", "Koru", "Yok"])
        #expect(rows[3].links.map(\.displayText) == [nil, "Ada", nil, nil])
        #expect(rows[3].links.map(\.resolvedFile) == [ada, ada, koru, nil])
        #expect(try vault.index.entityTimeline(for: koru).map(\.date.description) == ["2026-03-02", "2026-03-01"])
        #expect(try vault.index.entityTimeline(for: "notes/Plan.md").isEmpty)
        #expect(try vault.index.lastEncounters(asOf: CalendarDate("2026-02-28")!).isEmpty)
        #expect(
            try vault.index.lastEncounters(asOf: CalendarDate("2026-03-01")!)
                == [ada: CalendarDate("2026-03-01")!, koru: CalendarDate("2026-03-01")!])
        #expect(
            try vault.index.lastEncounters(asOf: CalendarDate("2026-03-04")!)
                == [ada: CalendarDate("2026-03-02")!, koru: CalendarDate("2026-03-02")!])
        #expect(try vault.index.lastEncounters(asOf: CalendarDate("2026-03-05")!)[ada] == CalendarDate("2026-03-05"))
    }

    /// Edits through the store keep the incrementally maintained index answering like a rebuild.
    @Test func storeEditsMatchSnapshotConstructionAndRebuild() async throws {
        let vault = try StoreVault(sample: true)
        defer { vault.remove() }
        let day = CalendarDate("2026-12-01")!
        let asOf = ["2026-09-21", "2026-11-30", "2026-12-01"]
        func check() throws {
            try expectConstruction(vault.index, asOf: asOf)
            let rebuilt = try VaultIndex()
            try rebuilt.rebuild(vaultRoot: vault.root)
            for file in try vault.index.files().map(\.path) {
                #expect(try vault.index.entityTimeline(for: file) == rebuilt.entityTimeline(for: file), "\(file)")
            }
            for date in asOf.compactMap(CalendarDate.init) {
                #expect(try vault.index.lastEncounters(asOf: date) == rebuilt.lastEncounters(asOf: date))
            }
        }
        let deniz = "people/Deniz Arıkan.md"
        let before = try vault.index.entityTimeline(for: deniz)
        _ = try await vault.store.addingEvent(on: day, text: "[[Deniz Arıkan]] ile [[Liman Ofis]]")
        try check()
        let added = try vault.index.entityTimeline(for: deniz)
        #expect(added.count == before.count + 1 && added.first?.date == day)
        #expect(try vault.index.lastEncounters(asOf: day)[deniz] == day)

        let renamed = try await vault.store.renamingEntity(at: deniz, to: "Deniz Yeni")
        #expect(renamed.failures.isEmpty)
        try check()
        #expect(try vault.index.entityTimeline(for: deniz).isEmpty)
        #expect(try vault.index.entityTimeline(for: renamed.path).map(\.block.ordinal) == added.map(\.block.ordinal))

        try FileManager.default.removeItem(at: vault.root.appendingPathComponent("journal/\(day).md"))
        try vault.index.refresh(vaultRoot: vault.root)
        try check()
        #expect(try vault.index.entityTimeline(for: renamed.path).count == before.count)
    }

    /// Both queries equal the construction for every file of the vault and every `asOf` date.
    private func expectConstruction(_ index: VaultIndex, asOf dates: [String]) throws {
        let construction = snapshotConstruction(try index.snapshot())
        #expect(!construction.isEmpty)
        let files = Set(try index.files().map(\.path)).union(construction.keys)
        for file in files.sorted() {
            #expect(try index.entityTimeline(for: file) == construction[file] ?? [], "\(file)")
        }
        for date in dates.compactMap(CalendarDate.init) {
            let expected = construction.compactMapValues { $0.map(\.date).filter { $0 <= date }.max() }
            #expect(try index.lastEncounters(asOf: date) == expected, "\(date)")
        }
    }
}

/// `EntityTimeline.build(snapshot:)` as the app built it before the query existed, in Core terms:
/// for each linked file, its rows newest day first and, within a day, by descending file and block.
/// A row carries its block's links in source order.
private func snapshotConstruction(_ snapshot: IndexSnapshot) -> [String: [EntityTimelineEntry]] {
    let dates = Dictionary(
        uniqueKeysWithValues: snapshot.files.compactMap { file -> (String, CalendarDate)? in
            guard file.kind == "day", let value = file.date, let date = CalendarDate(value) else { return nil }
            return (file.path, date)
        })
    let links = Dictionary(grouping: snapshot.links, by: \.file)
    var result: [String: [CalendarDate: [EntityTimelineEntry]]] = [:]
    for block in snapshot.blocks
    where block.kind == "event" || (block.kind == "paragraph" && block.section == "Journal") {
        guard let date = dates[block.file] else { continue }
        let own = (links[block.file] ?? []).filter { $0.block == block.ordinal }.sorted { $0.ordinal < $1.ordinal }
        for target in Set(own.compactMap(\.resolvedFile)) {
            result[target, default: [:]][date, default: []].append(
                EntityTimelineEntry(date: date, block: block, links: own))
        }
    }
    return result.mapValues { days in
        days.sorted { $0.key > $1.key }.flatMap { day in
            day.value.sorted { ($0.block.file, $0.block.ordinal) > ($1.block.file, $1.block.ordinal) }
        }
    }
}
