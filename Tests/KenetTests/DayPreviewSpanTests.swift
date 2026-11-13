import Foundation
import Testing
import VaultFormat

@testable import Kenet

/// The day list's preview line keeps the first event's links, so the row draws people and places
/// underlined (Günlük, gün listesi).
@MainActor struct DayPreviewSpanTests {
    @Test func firstLineStopsAtTheBreakAndNeedsALink() {
        let linked = LinkedText(spans: [
            .init(text: "Baran Tunç", destination: "people/Baran Tunç.md", target: "Baran Tunç"),
            .init(text: " ile yürüyüş\nikinci satır", destination: nil),
            .init(text: "Ev", destination: "places/Ev.md", target: "Ev"),
        ])
        let spans = DayPreviewSpan.firstLine(of: linked)
        #expect(spans?.map(\.text) == ["Baran Tunç", " ile yürüyüş"])
        #expect(spans?.first?.target == "Baran Tunç")
        #expect(DayPreviewSpan.firstLine(of: LinkedText(spans: [.init(text: "düz", destination: nil)])) == nil)
    }

    @Test func overviewOffersSpansOnlyForTheFirstEventLine() {
        let spans = [DayPreviewSpan(text: "Ev", destination: "places/Ev.md", target: "Ev")]
        let date = CalendarDate("2026-09-27")!
        let withEvent = DayOverview(
            id: "journal/2026-09-27.md", date: date, eventCount: 1, journalCount: 0, preview: nil,
            firstEventPreview: "Ev", firstEventSpans: spans)
        #expect(withEvent.displayPreviewSpans == spans)
        let journalOnly = DayOverview(
            id: "journal/2026-09-27.md", date: date, eventCount: 0, journalCount: 1, preview: "Yazı",
            firstEventSpans: spans)
        #expect(journalOnly.displayPreviewSpans == nil)
    }

    /// The sample vault's 26 September opens with a linked person: the fragment keeps the link.
    @Test func sampleDayFragmentKeepsTheFirstEventLink() async throws {
        let context = try TaskTestContext(sample: true)
        defer { context.clean() }
        await context.start()
        let fragment = try #require(context.store.content.fragments["journal/2026-09-26.md"])
        let spans = try #require(fragment.firstEventSpans)
        #expect(spans.first { $0.target != nil }?.text == "Baran Tunç")
        #expect(spans.map(\.text).joined() == fragment.firstEventPreview)
    }
}
