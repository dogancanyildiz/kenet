import Foundation
import Summaries
import Testing
import VaultFormat

struct WeeklyReviewTextTests {
    @Test func fixturesAndParserRoundTrip() throws {
        let url = fixtureDirectory().appendingPathComponent("summaries/weekly-review-text.json")
        let cases = try #require(JSONSerialization.jsonObject(with: Data(contentsOf: url)) as? [[String: Any]])
        for fixture in cases {
            let title = try #require(fixture["title"] as? String)
            let expected = try #require(fixture["expected"] as? [String])
            let result = WeeklyReviewText.lines(
                title: title, summaryLines: fixture["summaryLines"] as? [String] ?? [],
                selectedLines: fixture["selectedLines"] as? [String] ?? [], note: fixture["note"] as? String)
            #expect(result == expected, Comment(rawValue: fixture["id"] as? String ?? ""))
            let generated = RawDocument(bytes: Array(("## Journal\n" + result.joined(separator: "\n") + "\n").utf8))
            #expect(generated.bodyLines.tasks.isEmpty)
            #expect(generated.bodyLines.events.isEmpty)
            #expect(generated.frontmatter == .absent)
            #expect(generated.daySections.sections.count == 1)
            #expect(
                result
                    == WeeklyReviewText.lines(
                        title: title, summaryLines: fixture["summaryLines"] as? [String] ?? [],
                        selectedLines: fixture["selectedLines"] as? [String] ?? [], note: fixture["note"] as? String))
            // The writer takes the generated lines as they are: nothing left for it to split, trim or mark.
            let before = RawDocument(bytes: Array("## Journal\n- [ ] Kitap\n".utf8))
            let after = try before.appendingJournalLines(result)
            let block = result.isEmpty ? "" : "\n" + result.joined(separator: "\n") + "\n"
            #expect(after.serialized() == before.serialized() + Array(block.utf8))
            #expect(after.bodyLines == before.bodyLines)
            let reread = RawDocument(bytes: after.serialized())
            #expect(reread.bodyLines.tasks.count == 1)
            #expect(reread.bodyLines.events.isEmpty)
            #expect(reread.frontmatter == .absent)
            #expect(reread.daySections.sections.count == 1)
            #expect(reread.daySections.section(.journal)?.lineRange.upperBound == reread.lines.count)
            #expect(reread.serialized() == after.serialized())
            for line in result {
                #expect(reread.lines.contains { $0.text == line })
            }
        }
    }
}
