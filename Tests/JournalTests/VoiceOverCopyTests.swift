import Foundation
import Testing
import VaultFormat

@testable import Journal

struct VoiceOverCopyTests {
    private let locale = Locale(identifier: "tr_TR")

    @Test func taskCompletionValueSpeaksDoneAndOpen() {
        #expect(VoiceOverCopy.taskCompletionValue(isCompleted: true, locale: locale) == "Tamamlandı")
        #expect(VoiceOverCopy.taskCompletionValue(isCompleted: false, locale: locale) == "Açık")
        #expect(VoiceOverCopy.taskCompletionValue(isCompleted: true) == String(localized: "Tamamlandı"))
        #expect(VoiceOverCopy.taskCompletionValue(isCompleted: false) == String(localized: "Açık"))
    }

    @Test func priorityValueSpeaksNamedLevels() {
        #expect(VoiceOverCopy.priorityValue(.high, locale: locale) == "Yüksek öncelik")
        #expect(VoiceOverCopy.priorityValue(.medium, locale: locale) == "Orta öncelik")
        #expect(VoiceOverCopy.priorityValue(.low, locale: locale) == "Düşük öncelik")
        #expect(VoiceOverCopy.priorityValue(.other("⚡"), locale: locale) == "Öncelik ⚡")
        #expect(VoiceOverCopy.priorityValue(.high) == String(localized: "Yüksek öncelik"))
    }

    @Test func dayRowLabelIncludesDateEventsAndPreview() throws {
        let date = try #require(CalendarDate("2026-09-20"))
        let withPreview = VoiceOverCopy.dayRowLabel(
            date: date, eventCount: 2, preview: "Pazar gününü evde toparlanarak geçirdim.", locale: locale)
        #expect(withPreview.contains("2026") || withPreview.contains("20"))
        #expect(withPreview.contains("Olaylar: 2"))
        #expect(withPreview.contains("Pazar gününü evde toparlanarak geçirdim."))
        let empty = VoiceOverCopy.dayRowLabel(date: date, eventCount: 0, preview: nil, locale: locale)
        #expect(empty.contains("Olaylar: 0"))
        #expect(!empty.hasSuffix(", "))
    }

    @Test func kanbanAndTimelineActionNames() {
        #expect(VoiceOverCopy.moveActionName(columnTitle: "Devam", locale: locale) == "Taşı: Devam")
        #expect(VoiceOverCopy.changeDateActionName(locale: locale) == "Tarihi değiştir")
        #expect(
            VoiceOverCopy.moveActionName(columnTitle: "Devam")
                == String(localized: "Taşı: \("Devam")"))
        #expect(VoiceOverCopy.changeDateActionName() == String(localized: "Tarihi değiştir"))
    }

    @Test func disclosureValueSpeaksExpandedState() {
        #expect(VoiceOverCopy.disclosureValue(isExpanded: true, locale: locale) == "Genişletilmiş")
        #expect(VoiceOverCopy.disclosureValue(isExpanded: false, locale: locale) == "Daraltılmış")
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
        #expect(label.contains("Devreden"))
        let openEnded = VoiceOverCopy.timelineBarLabel(
            text: "Araştırma", start: start, due: nil, isOverdue: false, locale: locale)
        #expect(openEnded.contains("Açık uçlu"))
        #expect(!openEnded.contains("Devreden"))
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
        #expect(list[0].accessibilityLabel(locale: locale) == "Deniz Arıkan, Kişi, 2 komşu")
        #expect(list[1].accessibilityLabel(locale: locale) == "Liman Ofis, Konum, 1 komşu")
        #expect(list[2].accessibilityLabel(locale: locale) == "2026-09-20, Gün, 1 komşu")
    }
}
