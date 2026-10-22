import Foundation
import Testing
import VaultFormat
import VaultIndex

struct GraphCooccurrenceTests {
    @Test func graphFixtureMatchesHandCountedBlocksAndWeights() throws {
        let root = try Fixtures.root().appendingPathComponent("vaults/graph")
        let expected = try JSONDecoder().decode(
            Expectation.self, from: Data(contentsOf: root.appendingPathComponent("expected.json")))
        let index = try VaultIndex()
        try index.rebuild(vaultRoot: root)
        let result = try index.graphMentions(kinds: ["person", "place"])
        #expect(result.totals == expected.totals)
        #expect(
            result.days
                == expected.days.map {
                    GraphMentions.Day(date: CalendarDate($0.date)!, mentions: $0.mentions, groups: $0.groups)
                })
        let weights = GraphMentions.cooccurrenceWeights(days: result.days, including: Set(result.totals.keys))
        #expect(
            weights
                == Dictionary(
                    uniqueKeysWithValues: expected.edges.map {
                        (GraphMentions.Pair(first: $0.first, second: $0.second), $0.weight)
                    }))
        let books = try index.graphMentions(kinds: ["book"])
        #expect(books.totals == ["books/Örnek Kitap.md": 1])
        #expect(books.days.count == 1 && books.days.allSatisfy { $0.groups.isEmpty })
        #expect(try index.graphMentions(kinds: []).days.isEmpty)
        #expect(try index.snapshot().files.allSatisfy { $0.path != "journal/2026-10-03 2.md" })
    }

    @Test func weightsCountDatesNotBlocksOrDuplicateDayInputs() {
        let date = CalendarDate("2026-10-01")!
        let days: [GraphMentions.Day] = [
            .init(date: date, mentions: [:], groups: [["b", "a", "a"], ["a", "b", "c"], ["a"], []]),
            .init(date: date, mentions: [:], groups: [["a", "b"], ["c", "d"]]),
            .init(date: date.addingDays(1)!, mentions: [:], groups: [["b", "a"]]),
        ]
        let pair = GraphMentions.Pair(first: "b", second: "a")
        #expect(pair.first == "a" && pair.second == "b")
        #expect(GraphMentions.cooccurrenceWeights(days: days, including: ["a", "b"]) == [pair: 2])
        #expect(GraphMentions.cooccurrenceWeights(days: days, including: ["a"]).isEmpty)
        #expect(GraphMentions.cooccurrenceWeights(days: [], including: ["a", "b"]).isEmpty)
        #expect(
            GraphMentions.cooccurrenceWeights(days: days, including: ["c", "d"]) == [
                .init(first: "c", second: "d"): 1
            ])
    }

    private struct Expectation: Decodable {
        struct Day: Decodable {
            let date: String
            let mentions: [String: Int]
            let groups: [[String]]
        }
        struct Edge: Decodable {
            let first: String
            let second: String
            let weight: Int
        }
        let totals: [String: Int]
        let days: [Day]
        let edges: [Edge]
    }
}
