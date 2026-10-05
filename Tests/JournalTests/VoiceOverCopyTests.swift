import Foundation
import Testing
import VaultFormat

@testable import Journal

struct VoiceOverCopyTests {
    // String lookups follow the test host's language, so expectations resolve the same keys
    // instead of comparing against Turkish literals.
    private let locale = Locale(identifier: "tr_TR")
    private func localized(_ key: String.LocalizationValue) -> String { String(localized: key) }

    @Test func taskCompletionValueSpeaksDoneAndOpen() {
        #expect(VoiceOverCopy.taskCompletionValue(isCompleted: true, locale: locale) == localized("Tamamlandı"))
        #expect(VoiceOverCopy.taskCompletionValue(isCompleted: false, locale: locale) == localized("Açık"))
        #expect(
            VoiceOverCopy.taskCompletionValue(isCompleted: true)
                != VoiceOverCopy.taskCompletionValue(isCompleted: false))
        #expect(VoiceOverCopy.taskCompletionValue(isCompleted: true) == String(localized: "Tamamlandı"))
        #expect(VoiceOverCopy.taskCompletionValue(isCompleted: false) == String(localized: "Açık"))
    }

    @Test func priorityValueSpeaksNamedLevels() {
        #expect(VoiceOverCopy.priorityValue(.high, locale: locale) == localized("Yüksek öncelik"))
        #expect(VoiceOverCopy.priorityValue(.medium, locale: locale) == localized("Orta öncelik"))
        #expect(VoiceOverCopy.priorityValue(.low, locale: locale) == localized("Düşük öncelik"))
        #expect(VoiceOverCopy.priorityValue(.other("⚡"), locale: locale) == localized("Öncelik \("⚡")"))
        #expect(VoiceOverCopy.priorityValue(.high) == String(localized: "Yüksek öncelik"))
    }

    @Test func dayRowLabelIncludesDateEventsAndPreview() throws {
        let date = try #require(CalendarDate("2026-09-20"))
        let withPreview = VoiceOverCopy.dayRowLabel(
            date: date, eventCount: 2, preview: "Pazar gününü evde toparlanarak geçirdim.", locale: locale)
        #expect(withPreview.contains("2026") || withPreview.contains("20"))
        #expect(withPreview.contains(localized("Olaylar: \(2)")))
        #expect(withPreview.contains("Pazar gününü evde toparlanarak geçirdim."))
        let empty = VoiceOverCopy.dayRowLabel(date: date, eventCount: 0, preview: nil, locale: locale)
        #expect(empty.contains(localized("Olaylar: \(0)")))
        #expect(!empty.hasSuffix(", "))
    }

    @Test func kanbanAndTimelineActionNames() {
        #expect(VoiceOverCopy.moveActionName(columnTitle: "Devam", locale: locale).contains("Devam"))
        #expect(VoiceOverCopy.changeDateActionName(locale: locale) == localized("Tarihi değiştir"))
        #expect(
            VoiceOverCopy.moveActionName(columnTitle: "Devam")
                == String(localized: "Taşı: \("Devam")"))
        #expect(VoiceOverCopy.changeDateActionName() == String(localized: "Tarihi değiştir"))
    }

    @Test func disclosureValueSpeaksExpandedState() {
        #expect(VoiceOverCopy.disclosureValue(isExpanded: true, locale: locale) == localized("Genişletilmiş"))
        #expect(VoiceOverCopy.disclosureValue(isExpanded: false, locale: locale) == localized("Daraltılmış"))
        #expect(VoiceOverCopy.disclosureValue(isExpanded: true) == String(localized: "Genişletilmiş"))
        #expect(VoiceOverCopy.disclosureValue(isExpanded: false) == String(localized: "Daraltılmış"))
    }

    @Test func timelineBarLabelIncludesRangeAndOverdue() throws {
        let start = try #require(CalendarDate("2026-09-18"))
        let due = try #require(CalendarDate("2026-09-20"))
        let label = VoiceOverCopy.timelineBarLabel(
            text: "Raporu bitir", start: start, due: due, isOverdue: true, locale: locale)
        #expect(label.hasPrefix("Raporu bitir,"))
        #expect(label.contains("–"))
        #expect(label.contains(localized("Devreden")))
        let openEnded = VoiceOverCopy.timelineBarLabel(
            text: "Araştırma", start: start, due: nil, isOverdue: false, locale: locale)
        #expect(openEnded.contains(localized("Açık uçlu")))
        #expect(!openEnded.contains(localized("Devreden")))
    }

    @Test func graphAccessibleListExposesNameKindAndNeighbors() {
        let nodes = [
            GraphNode(id: "people/a.md", name: "Deniz Arıkan", kind: .person, count: 3),
            GraphNode(id: "places/b.md", name: "Liman Ofis", kind: .place, count: 2),
            GraphNode(id: "day:2026-09-20", name: "2026-09-20", kind: .day, count: 1),
        ]
        let edges = [
            GraphEdge(first: "people/a.md", second: "places/b.md", weight: 2),
            GraphEdge(first: "people/a.md", second: "day:2026-09-20", weight: 1),
        ]
        let list = GraphAccessibleNode.list(from: GraphModel(nodes: nodes, edges: edges))
        #expect(list.map(\.id) == nodes.map(\.id))
        #expect(list[0].neighborCount == 2)
        #expect(list[1].neighborCount == 1)
        #expect(list[2].neighborCount == 1)
        let first = list[0].accessibilityLabel(locale: locale)
        #expect(first.hasPrefix("Deniz Arıkan, "))
        #expect(first.contains(localized("Kişi")) && first.hasSuffix(localized("\(2) komşu")))
        let second = list[1].accessibilityLabel(locale: locale)
        #expect(second.contains(localized("Konum")) && second.hasSuffix(localized("\(1) komşu")))
        let third = list[2].accessibilityLabel(locale: locale)
        #expect(third.hasPrefix("2026-09-20, ") && third.contains(localized("Gün")))
    }
}
