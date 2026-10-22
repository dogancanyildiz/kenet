import Foundation
import Testing
import VaultFormat
import VaultIndex

@testable import VaultStore

/// One day's graph query (`dayGraphMentions(on:kinds:)`): hand-counted fixture days, and on larger
/// vaults the same answer as the whole-vault query's day.
struct DayGraphMentionsTests {
    @Test func graphFixtureDaysMatchHandCountedMentionsAndGroups() throws {
        let root = try Fixtures.root().appendingPathComponent("vaults/graph")
        let expected = try JSONDecoder().decode(
            Expectation.self, from: Data(contentsOf: root.appendingPathComponent("day-graph.json")))
        let index = try VaultIndex()
        try index.rebuild(vaultRoot: root)
        for day in expected.days {
            let date = try #require(CalendarDate(day.date))
            #expect(
                try index.dayGraphMentions(on: date, kinds: expected.kinds)
                    == GraphMentions.Day(date: date, mentions: day.mentions, groups: day.groups), "\(day.date)")
        }
        // Only the requested kinds count; no kind, no mention.
        let first = try #require(CalendarDate("2026-10-01"))
        #expect(
            try index.dayGraphMentions(on: first, kinds: ["book"])
                == GraphMentions.Day(date: first, mentions: ["books/Örnek Kitap.md": 1]))
        #expect(try index.dayGraphMentions(on: first, kinds: []) == GraphMentions.Day(date: first, mentions: [:]))
        // With the whole-vault query's kinds, each day is that query's day.
        let kinds: Set<String> = ["person", "place"]
        for day in try index.graphMentions(kinds: kinds).days {
            #expect(try index.dayGraphMentions(on: day.date, kinds: kinds) == day)
        }
    }

    /// A custom type shares a block with a person like any other entity; links from other files of
    /// the vault and from other dates stay out of the day.
    @Test func customTypesGroupWithPeopleAndOtherFilesStayOut() throws {
        let vault = try StoreVault()
        defer { vault.remove() }
        try vault.write(
            ".app/types.json",
            """
            {"formatVersion":1,"types":[{"id":"book","folder":"books","name":{"tr":"Kitap","en":"Book"},\
            "plural":{"tr":"Kitaplar","en":"Books"},"icon":"book","fields":[]}]}
            """)
        try vault.write("people/Ada Test.md", "---\ntype: person\nname: Ada Test\n---\n[[Uzun Yol]]\n")
        try vault.write("books/Uzun Yol.md", "---\ntype: book\nname: Uzun Yol\n---\n")
        try vault.write("notes/Plan.md", "[[Ada Test]] ve [[Uzun Yol]]\n")
        try vault.write(
            "journal/2026-03-01.md",
            "## Events\n- 09:00 [[Ada Test]] ile [[Uzun Yol]] okundu.\n\n## Journal\n[[Uzun Yol]] bitti. [[Yok]]\n")
        try vault.write("journal/2026-03-02.md", "## Events\n- 09:00 [[Ada Test]] ile [[Uzun Yol]]\n")
        try vault.index.rebuild(vaultRoot: vault.root)

        let date = try #require(CalendarDate("2026-03-01"))
        let ada = "people/Ada Test.md"
        let book = "books/Uzun Yol.md"
        #expect(
            try vault.index.dayGraphMentions(on: date, kinds: ["person", "place", "book"])
                == GraphMentions.Day(date: date, mentions: [ada: 1, book: 2], groups: [[book, ada]]))
        #expect(
            try vault.index.dayGraphMentions(on: date, kinds: ["person"])
                == GraphMentions.Day(date: date, mentions: [ada: 1]))
    }

    /// A five-year vault: every day answered alone is that day of the whole-vault query, and a date
    /// outside the vault has nothing.
    @Test func syntheticVaultDaysMatchTheWholeVaultQuery() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let configuration = Self.syntheticConfiguration
        try SyntheticVault.generate(at: root, configuration: configuration)
        let index = try VaultIndex()
        try index.rebuild(vaultRoot: root)
        let kinds: Set<String> = ["person", "place"]
        let days = try index.graphMentions(kinds: kinds).days
        #expect(days.count == configuration.days)
        for day in days {
            #expect(try index.dayGraphMentions(on: day.date, kinds: kinds) == day)
        }
        let after = try #require(configuration.endDate.addingDays(1))
        #expect(try index.dayGraphMentions(on: after, kinds: kinds) == GraphMentions.Day(date: after, mentions: [:]))
    }

    /// Five years when `SCALE_BUDGET_SECONDS` is set (the opt-in scale runs), three weeks otherwise.
    static var syntheticConfiguration: SyntheticVault.Configuration {
        ProcessInfo.processInfo.environment["SCALE_BUDGET_SECONDS"] != nil ? .fiveYears : .compact
    }

    private struct Expectation: Decodable {
        struct Day: Decodable {
            let date: String
            let mentions: [String: Int]
            let groups: [[String]]
        }
        let kinds: Set<String>
        let days: [Day]
    }
}
