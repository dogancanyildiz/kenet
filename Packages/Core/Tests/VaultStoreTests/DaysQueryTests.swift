import Foundation
import Testing
import VaultFormat
import VaultIndex

@testable import VaultStore

/// The day-list and single-day queries against the snapshot construction they replaced in the app
/// (the read model's `days` and `day(on:)`).
struct DaysQueryTests {
    @Test func sampleVaultMatchesSnapshotConstruction() throws {
        let index = try VaultIndex()
        try index.rebuild(vaultRoot: Fixtures.root().appendingPathComponent("vaults/sample"))
        let summaries = try expectConstruction(
            index, ranges: [("2026-09-14", "2026-09-27"), ("2026-09-15", "2026-09-20"), ("2026-09-01", "2026-09-30")])
        #expect(summaries.count == 14)
        #expect(summaries.first?.date.description == "2026-09-27" && summaries.last?.date.description == "2026-09-14")
        #expect(summaries.reduce(0) { $0 + $1.eventCount } == 40)
    }

    @Test func syntheticVaultMatchesSnapshotConstruction() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let manifest = try SyntheticVault.generate(at: root, configuration: .compact)
        let index = try VaultIndex()
        try index.rebuild(vaultRoot: root)
        let end = manifest.endDate
        let summaries = try expectConstruction(
            index, ranges: [(end.addingDays(-6)!.description, end.description), ("2026-09-30", "2026-10-01")])
        #expect(summaries.count == SyntheticVault.Configuration.compact.days)
        #expect(summaries.first?.date == end)
    }

    /// Every rule of the construction in one small vault, with the counts written out by hand.
    @Test func edgeCaseVaultCountsByHand() throws {
        let vault = try StoreVault()
        defer { vault.remove() }
        try vault.write("people/Ada Test.md", "---\ntype: person\nname: Ada Test\n---\n")
        // Sections out of order; a heading, a two-line paragraph and a second paragraph in Journal.
        try vault.write(
            "journal/2026-03-01.md",
            """
            ## Journal
            ### Sabah
            İlk paragraf [[Ada Test|Ada]] ve [[Yok]].
            ikinci satır

            İkinci paragraf.

            ## Events
            - 09:00 Birinci [[Ada Test]]
            - 10:00 İkinci

            ## Tasks
            - [ ] görev

            ## Notlar
            Başka bölümde paragraf.
            """)
        try vault.write("journal/2026-03-02.md", "## Journal\nYalnız günlük.\n")
        try vault.write("journal/2026-03-03.md", "## Tasks\n- [ ] yalnız görev\n")
        try vault.write(
            "journal/2026-03-04.md",
            "\u{FEFF}---\r\ntype: journal\r\ngoals:\r\n  kitap: 5\r\n---\r\n\r\n## Events\r\n- 08:00 Sabah\r\n\r\n## Journal\r\nCRLF paragrafı.\r\n"
        )
        try vault.write("journal/2026-03-05.md", "---\ntype: journal\n---\n")
        try vault.write("journal/2026-03-09.md", "## Journal\n### Yalnız başlık\n")
        // Not day files: a note linking to a day, a misdated name, files outside `journal/`, bad UTF-8.
        try vault.write(
            "notes/Plan.md", "## Events\n- 09:00 [[2026-03-01]] planı\n\n## Journal\n[[2026-03-02]] notu.\n")
        try vault.write("journal/2026-02-30.md", "## Events\n- 08:00 Yok\n")
        try vault.write("journal/arsiv/2026-03-06.md", "## Events\n- 08:00 Arşiv\n")
        try vault.write("arsiv/2026-03-07.md", "## Events\n- 08:00 Arşiv\n")
        try Data([0x23, 0x23, 0x20, 0xFF, 0x0A]).write(to: vault.root.appendingPathComponent("journal/2026-03-08.md"))
        try vault.index.rebuild(vaultRoot: vault.root)
        try expectConstruction(
            vault.index,
            ranges: [("2026-03-01", "2026-03-04"), ("2026-03-02", "2026-03-03"), ("2026-03-10", "2026-03-31")])

        let all = try vault.index.daySummaries()
        #expect(
            all.map(\.date.description) == [
                "2026-03-09", "2026-03-05", "2026-03-04", "2026-03-03", "2026-03-02", "2026-03-01",
            ])
        #expect(all.map(\.eventCount) == [0, 0, 1, 0, 0, 2])
        #expect(all.map(\.journalCount) == [1, 0, 1, 0, 1, 3])
        #expect(all.map(\.hasGoalRecords) == [false, false, true, false, false, false])
        #expect(
            all.map { $0.firstParagraph?.text } == [
                nil, nil, "CRLF paragrafı.", nil, "Yalnız günlük.",
                "İlk paragraf [[Ada Test|Ada]] ve [[Yok]].\nikinci satır",
            ])
        let first = try #require(all.last)
        #expect(first.firstParagraphLinks.map(\.target) == ["Ada Test", "Yok"])
        #expect(first.firstParagraphLinks.map(\.resolvedFile) == ["people/Ada Test.md", nil])
        // Both ends of a range are included.
        #expect(
            try vault.index.daySummaries(from: CalendarDate("2026-03-02"), to: CalendarDate("2026-03-04")).map(
                \.date.description) == ["2026-03-04", "2026-03-03", "2026-03-02"])
        #expect(
            try vault.index.daySummaries(from: CalendarDate("2026-03-05")).map(\.date.description) == [
                "2026-03-09", "2026-03-05",
            ])
        #expect(try vault.index.daySummaries(to: CalendarDate("2026-03-01")).map(\.date.description) == ["2026-03-01"])

        let day = try #require(try vault.index.day(on: CalendarDate("2026-03-01")!))
        #expect(day.blocks.filter { $0.kind == "event" }.map(\.text) == ["Birinci [[Ada Test]]", "İkinci"])
        #expect(day.blocks.filter { $0.kind == "event" }.map(\.time) == ["09:00", "10:00"])
        #expect(try vault.index.day(on: CalendarDate("2026-03-08")!) == nil)
        #expect(try vault.index.day(on: CalendarDate("2026-03-06")!) == nil)
        #expect(try vault.index.day(on: CalendarDate("2026-03-05")!)?.blocks.isEmpty == true)
    }

    /// Edits through the store keep the incrementally maintained index answering like a rebuild.
    @Test func storeEditsMatchSnapshotConstructionAndRebuild() async throws {
        let vault = try StoreVault(sample: true)
        defer { vault.remove() }
        let day = CalendarDate("2026-12-01")!
        let ranges = [("2026-09-20", "2026-09-27"), ("2026-11-30", "2026-12-01")]
        func check() throws {
            try expectConstruction(vault.index, ranges: ranges)
            let rebuilt = try VaultIndex()
            try rebuilt.rebuild(vaultRoot: vault.root)
            #expect(try vault.index.daySummaries() == rebuilt.daySummaries())
            for entry in try rebuilt.daySummaries() {
                #expect(try vault.index.day(on: entry.date) == rebuilt.day(on: entry.date), "\(entry.date)")
            }
        }
        let before = try vault.index.daySummaries()
        _ = try await vault.store.addingEvent(on: day, text: "[[Deniz Arıkan]] ile [[Liman Ofis]]")
        try check()
        #expect(try vault.index.daySummaries().count == before.count + 1)
        #expect(try vault.index.daySummaries(from: day).map(\.eventCount) == [1])

        _ = try await vault.store.appendingJournal(on: day, lines: ["[[Deniz Arıkan]] ile ilk satır."])
        try check()
        let written = try #require(try vault.index.daySummaries(from: day).first)
        #expect(written.journalCount == 1 && written.firstParagraph?.text == "[[Deniz Arıkan]] ile ilk satır.")

        let renamed = try await vault.store.renamingEntity(at: "people/Deniz Arıkan.md", to: "Deniz Yeni")
        #expect(renamed.failures.isEmpty)
        try check()
        let after = try #require(try vault.index.daySummaries(from: day).first)
        #expect(after.firstParagraphLinks.map(\.resolvedFile) == [renamed.path])

        try FileManager.default.removeItem(at: vault.root.appendingPathComponent("journal/\(day).md"))
        try vault.index.refresh(vaultRoot: vault.root)
        try check()
        #expect(try vault.index.daySummaries().count == before.count)
        #expect(try vault.index.day(on: day) == nil)
    }

    /// The list query, each range of it, and the single-day query on every listed date and on the
    /// day after the newest one equal the construction.
    @discardableResult
    private func expectConstruction(_ index: VaultIndex, ranges: [(String, String)]) throws -> [DaySummaryEntry] {
        let snapshot = try index.snapshot()
        let construction = snapshotConstruction(snapshot)
        let all = try index.daySummaries()
        #expect(all == construction)
        for (from, to) in ranges {
            let from = try #require(CalendarDate(from))
            let to = try #require(CalendarDate(to))
            let expected = construction.filter { $0.date >= from && $0.date <= to }
            #expect(try index.daySummaries(from: from, to: to) == expected, "\(from)…\(to)")
        }
        let blocks = Dictionary(grouping: snapshot.blocks, by: \.file)
        let links = Dictionary(grouping: snapshot.links, by: \.file)
        for entry in construction {
            let day = try #require(try index.day(on: entry.date))
            #expect(day.file.path == entry.file)
            #expect(day.blocks == (blocks[entry.file] ?? []).sorted { $0.ordinal < $1.ordinal }, "\(entry.date)")
            #expect(day.links == (links[entry.file] ?? []).sorted { $0.ordinal < $1.ordinal }, "\(entry.date)")
            #expect(!day.goalLogs.isEmpty == entry.hasGoalRecords, "\(entry.date)")
        }
        if let newest = construction.first?.date.addingDays(1) {
            #expect(try index.day(on: newest) == nil)
        }
        return all
    }
}

/// The read model's `days` as the app built it before the query existed, in Core terms: day files
/// newest first (path on ties), their event count, Journal paragraphs and headings, the first
/// Journal paragraph with its own links in source order, and whether a goal value is recorded.
private func snapshotConstruction(_ snapshot: IndexSnapshot) -> [DaySummaryEntry] {
    let goalFiles = Set(snapshot.goalLogs.map(\.file))
    let blocks = Dictionary(grouping: snapshot.blocks, by: \.file)
    let links = Dictionary(grouping: snapshot.links, by: \.file)
    return snapshot.files.compactMap { file -> DaySummaryEntry? in
        guard file.kind == "day", let value = file.date, let date = CalendarDate(value) else { return nil }
        let rows = (blocks[file.path] ?? []).sorted { $0.ordinal < $1.ordinal }
        let journal = rows.filter { $0.section == "Journal" && ["paragraph", "heading"].contains($0.kind) }
        let first = journal.first { $0.headingLevel == nil }
        let own =
            first.map { block in
                (links[file.path] ?? []).filter { $0.block == block.ordinal }.sorted { $0.ordinal < $1.ordinal }
            } ?? []
        return DaySummaryEntry(
            file: file.path, date: date, eventCount: rows.filter { $0.kind == "event" }.count,
            journalCount: journal.count, firstParagraph: first, firstParagraphLinks: own,
            hasGoalRecords: goalFiles.contains(file.path))
    }.sorted { $0.date != $1.date ? $0.date > $1.date : $0.file < $1.file }
}
