import Foundation
import Testing
import VaultFormat
import VaultIndex
import VaultStore

@testable import Journal

/// The day list, the calendar and the day page query Core on demand, not the read model.
@MainActor struct DaysStoreQueryTests {
    @Test func sampleAndSyntheticVaultsMatchTheSnapshotConstruction() async throws {
        let sample = try TaskTestContext(sample: true)
        defer { sample.clean() }
        await sample.start()
        let days = try await expectSnapshotConstruction(sample, months: ["2026-09-01", "2026-10-01", "2026-08-01"])
        #expect(days.count == 14 && days.reduce(0) { $0 + $1.eventCount } == 40)
        #expect(days.first?.date.description == "2026-09-27" && days.last?.date.description == "2026-09-14")

        let synthetic = try TaskTestContext()
        defer { synthetic.clean() }
        let manifest = try SyntheticVault.generate(at: synthetic.root, configuration: .compact)
        await synthetic.start()
        let generated = try await expectSnapshotConstruction(synthetic, months: ["2026-09-01", "2026-10-01"])
        #expect(generated.count == SyntheticVault.Configuration.compact.days)
        #expect(generated.first?.date == manifest.endDate)
    }

    /// Previews, counts and marks written out by hand for days the sample has none of.
    @Test func edgeCaseDaysMatchHandCountedRows() async throws {
        let context = try TaskTestContext()
        defer { context.clean() }
        try IncrementalReadModelVault.write(
            context.root, "people/Ada Test.md", "---\ntype: person\nname: Ada Test\n---\n")
        try IncrementalReadModelVault.write(
            context.root, "journal/2026-03-01.md",
            "## Journal\n### Sabah\nİlk [[Ada Test|Ada]] ve [[Yok]].\nikinci satır\n\n## Events\n- 09:00 Bir\n- 10:00 İki\n"
        )
        try IncrementalReadModelVault.write(
            context.root, "journal/2026-03-02.md", "## Journal\nYalnız günlük.\nikinci satır\n\nİkinci paragraf.\n")
        try IncrementalReadModelVault.write(context.root, "journal/2026-03-03.md", "## Tasks\n- [ ] yalnız görev\n")
        try IncrementalReadModelVault.write(
            context.root, "journal/2026-03-04.md",
            "\u{FEFF}---\r\ntype: journal\r\ngoals:\r\n  kitap: 5\r\n---\r\n\r\n## Events\r\n- 08:00 Sabah\r\n\r\n## Journal\r\nCRLF paragrafı.\r\n"
        )
        try IncrementalReadModelVault.write(context.root, "journal/2026-03-09.md", "## Journal\n### Yalnız başlık\n")
        try IncrementalReadModelVault.write(context.root, "notes/Plan.md", "## Events\n- 09:00 [[2026-03-01]] planı\n")
        await context.start()
        try await expectSnapshotConstruction(context, months: ["2026-03-01", "2026-02-01"])

        let days = try await context.store.computeDaySummaries()
        #expect(days.map(\.date.description) == ["2026-03-09", "2026-03-04", "2026-03-03", "2026-03-02", "2026-03-01"])
        #expect(days.map(\.preview) == [nil, "CRLF paragrafı.", nil, "Yalnız günlük.", "İlk Ada ve Yok."])
        #expect(days.map(\.eventCount) == [0, 1, 0, 0, 2])
        #expect(days.map(\.journalCount) == [1, 1, 0, 2, 2])
        #expect(days.map(\.hasGoalRecords) == [false, true, false, false, false])
        // One mark for any Journal, however many paragraphs: 03-02 has two and no event.
        let march = JournalCalendar(month: CalendarDate("2026-03-01")!, days: days)
        #expect(
            march.levels == [
                CalendarDate("2026-03-01")!: 2, CalendarDate("2026-03-02")!: 1, CalendarDate("2026-03-04")!: 2,
                CalendarDate("2026-03-09")!: 1,
            ])

        let first = try await context.store.computeDay(on: CalendarDate("2026-03-01")!)
        #expect(first.events.map(\.text.plainText) == ["Bir", "İki"])
        #expect(first.events.map { $0.time?.raw } == ["09:00", "10:00"])
        #expect(first.journal.map(\.headingLevel) == [3, nil])
        #expect(first.preview == "İlk Ada ve Yok.")
        #expect(first.journal.last?.text.spans.compactMap(\.destination) == ["people/Ada Test.md"])
        #expect(!CloseDayEntry.hasJournal(try await context.store.computeDay(on: CalendarDate("2026-03-09")!)))
    }

    /// The list skips the Markdown parse for a preview paragraph without links and takes its first
    /// line straight from the block text. Paragraphs that look like Markdown, odd line endings and
    /// odd characters give the same preview as the parse would (the old construction).
    @Test func previewsWithoutLinksMatchTheParsedText() async throws {
        let context = try TaskTestContext()
        defer { context.clean() }
        try IncrementalReadModelVault.write(
            context.root, "people/Ada Test.md", "---\ntype: person\nname: Ada Test\n---\n")
        let paragraphs = [
            "*vurgu* ve **kalın** ve _alt çizgi_ ve ~~üstü çizili~~",
            "`kod` ve ``çift `ters` tırnak``",
            "[dış](https://example.com) bağlantı ve <https://example.com> ve ![resim](a.png)",
            "#etiket ve #iç/etiket ve # değil",
            "%%gizli yorum%% sonrası ve %% açık kalan",
            "<!-- html yorumu --> sonrası ve <b>etiket</b>",
            "çok satırlı ilk satır\nikinci satır\nüçüncü satır",
            "   girintili ve sonda boşluklu   \nikinci",
            "\tsekmeyle başlayan",
            "\\[[kaçışlı]] ve [[yarım kalan",
            "![[resim.png]] gömülü",
            "> alıntı gibi\n> devamı",
            "Aile 👩‍👩‍👧 ve 👍🏽 ve 🇹🇷",
            "C\u{0327}ay ve s\u{0327}eker (NFD)",
            "Satır içi\u{2028}ayırıcı ve\u{0085}NEL ve\u{000B}VT",
            "Sonda ters bölü \\",
            "1. numaralı gibi",
            "שלום ve العربية karışık",
            "\u{200B}sıfır genişlik\u{FEFF} ve iç BOM",
            "[[Ada Test]] bağlantılı ilk satır\nikinci",
        ]
        var dates: [CalendarDate] = []
        for (offset, paragraph) in paragraphs.enumerated() {
            let date = try #require(CalendarDate("2026-04-01")?.addingDays(offset))
            dates.append(date)
            try IncrementalReadModelVault.write(context.root, "journal/\(date).md", "## Journal\n\(paragraph)\n")
        }
        // Line endings and a byte order mark around the paragraph.
        let endings = [
            "## Journal\r\nCRLF ilk\r\nikinci\r\n", "## Journal\rCR ilk\rikinci\r", "\u{FEFF}## Journal\nBOM ile\n",
            "\u{FEFF}---\r\ntype: journal\r\n---\r\n## Journal\r\n  CRLF girintili  \r\n\r\nikinci paragraf\r\n",
        ]
        for (offset, text) in endings.enumerated() {
            let date = try #require(CalendarDate("2026-05-01")?.addingDays(offset))
            dates.append(date)
            try IncrementalReadModelVault.write(context.root, "journal/\(date).md", text)
        }
        await context.start()
        let days = try await expectSnapshotConstruction(context, months: ["2026-04-01", "2026-05-01"])
        #expect(Set(days.map(\.date)) == Set(dates))
        #expect(days.allSatisfy { $0.preview != nil })

        // The same rows through the parse, link or not: the fast path is taken and agrees.
        let index = try VaultIndex()
        try index.rebuild(vaultRoot: context.root)
        let entries = try index.daySummaries()
        #expect(entries.filter(\.firstParagraphLinks.isEmpty).count >= paragraphs.count + endings.count - 2)
        for entry in entries {
            let paragraph = try #require(entry.firstParagraph)
            let parsed = LinkedText(row: paragraph, links: entry.firstParagraphLinks).plainText
                .components(separatedBy: "\n").first
            #expect(DayOverview(entry: entry).preview == parsed, "\(entry.date)")
        }
    }

    /// A screen's request replaced while its query runs (`.task(id:)` cancels it) gets no answer:
    /// the detached query runs on, and its older result must not land over the newer one.
    @Test func aCancelledRequestGetsNoAnswer() async throws {
        let context = try TaskTestContext(sample: true)
        defer { context.clean() }
        await context.start()
        let store = context.store
        let gate = DayQueryGate(store: store)
        gate.hold()
        let list = Task { try await store.computeDaySummaries() }
        let day = Task { try await store.computeDay(on: CalendarDate("2026-09-20")!) }
        await gate.waitUntilHolding(2)
        list.cancel()
        day.cancel()
        let newer = Task { try await store.computeDaySummaries() }
        await gate.waitUntilHolding(3)
        gate.release()
        await #expect(throws: CancellationError.self) { try await list.value }
        await #expect(throws: CancellationError.self) { try await day.value }
        #expect(try await newer.value.count == 14)
    }

    @Test func aQueryThatOutlivesItsVaultIsNotAppliedToTheNext() async throws {
        let context = try TaskTestContext(sample: true)
        defer { context.clean() }
        await context.start()
        let store = context.store
        let other = context.directory.appendingPathComponent("Other")
        try FileManager.default.createDirectory(at: other, withIntermediateDirectories: true)
        let day = CalendarDate("2026-09-20")!
        func switchVaultWhenTheQueryReturns() {
            store.testingDayQueryDidFinish = {
                store.testingDayQueryDidFinish = nil
                await store.select(other)
            }
        }

        switchVaultWhenTheQueryReturns()
        await #expect(throws: VaultStoreError.staleTarget) {
            try await store.computeDaySummaries()
        }
        #expect(store.vaultURL?.lastPathComponent == "Other")

        await store.select(context.root)
        #expect(try await store.computeDaySummaries().count == 14)
        switchVaultWhenTheQueryReturns()
        await #expect(throws: VaultStoreError.staleTarget) {
            try await store.computeDay(on: day)
        }
        #expect(store.vaultURL?.lastPathComponent == "Other")

        await store.select(context.root)
        #expect(try await !store.computeDay(on: day).events.isEmpty)
    }

    /// The store's answers equal the old read-model construction from a fresh rebuild of the vault:
    /// the whole list, each month's range, and every listed day plus a date without a file. The
    /// published day the notification planner reads equals it too.
    @discardableResult
    private func expectSnapshotConstruction(_ context: TaskTestContext, months: [String]) async throws
        -> [DayOverview]
    {
        let index = try VaultIndex()
        try index.rebuild(vaultRoot: context.root)
        let expected = DaySummary.build(snapshot: try index.snapshot())
        #expect(!expected.isEmpty)
        let days = try await context.store.computeDaySummaries()
        #expect(days == expected.map(\.overview))
        for month in months.compactMap(CalendarDate.init) {
            let range = JournalCalendar.range(of: month)
            let listed = try await context.store.computeDaySummaries(from: range.lowerBound, to: range.upperBound)
            #expect(listed == expected.filter { range.contains($0.date) }.map(\.overview), "\(month)")
            #expect(
                JournalCalendar(month: month, days: listed).levels
                    == JournalCalendar(month: month, days: expected.map(\.overview)).levels, "\(month)")
        }
        let absent = try #require(expected.first?.date.addingDays(1))
        for date in expected.map(\.date) + [absent] {
            let old = DaySummary.day(on: date, in: expected).key
            #expect(try await context.store.computeDay(on: date).key == old, "\(date)")
            #expect(context.store.content.day(on: date).key == old, "published \(date)")
        }
        return days
    }
}

/// Holds the store's day queries after they return, so a test can look at a screen, or cancel a
/// request, while the answer is on its way.
@MainActor final class DayQueryGate {
    private var isHolding = false
    private var held: [CheckedContinuation<Void, Never>] = []
    private var watchers: [(count: Int, continuation: CheckedContinuation<Void, Never>)] = []

    init(store: IndexStore) {
        store.testingDayQueryDidFinish = { [weak self] in await self?.pass() }
    }

    /// Answers waiting at the gate.
    var heldCount: Int { held.count }

    func hold() { isHolding = true }

    /// Lets every held answer through; later ones pass straight on.
    func release() {
        isHolding = false
        let waiting = held
        held = []
        for continuation in waiting { continuation.resume() }
    }

    func waitUntilHolding(_ count: Int) async {
        guard held.count < count else { return }
        await withCheckedContinuation { watchers.append((count, $0)) }
    }

    private func pass() async {
        guard isHolding else { return }
        await withCheckedContinuation { continuation in
            held.append(continuation)
            let ready = watchers.filter { $0.count <= held.count }
            watchers.removeAll { $0.count <= held.count }
            for watcher in ready { watcher.continuation.resume() }
        }
    }
}
