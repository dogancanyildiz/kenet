import Testing
import VaultIndex

struct ParagraphSegmentsTests {
    @Test func everyListItemStartsASegmentAndProseRunsStayTogether() {
        #expect(ParagraphSegments.indices(in: "Bugün sakin.\nAkşam yürüdük.") == [0, 0])
        #expect(ParagraphSegments.indices(in: "- bir\n* iki\n+ üç") == [0, 1, 2])
        #expect(ParagraphSegments.indices(in: "Önce:\n- bir\n- iki\nSonra düz cümle.\nVe devamı.") == [0, 1, 2, 3, 3])
        // Not list markers: no space after the marker, emphasis, a signed number, ten digits.
        #expect(ParagraphSegments.indices(in: "-bir\n**kalın**\n+1 oldu\n1234567890. on hane") == [0, 0, 0, 0])
        #expect(ParagraphSegments.indices(in: "") == [0])
    }

    @Test func numberedItemsUseDotOrParenthesis() {
        #expect(ParagraphSegments.indices(in: "1. bir\n2) iki\n10. on\n123456789. dokuz hane") == [0, 1, 2, 3])
        #expect(ParagraphSegments.indices(in: "1.bitişik\n2)bitişik\n1990'da") == [0, 0, 0])
        // Five to nine digits still make an item on their own, right under prose.
        #expect(ParagraphSegments.indices(in: "Düz.\n12345. beş hane\nDüz.\n123456789) dokuz hane") == [0, 1, 2, 3])
    }

    @Test func deeperIndentedLinesContinueTheItem() {
        #expect(
            ParagraphSegments.indices(in: "- bir\n  devamı\n  - alt madde\n    > alıntı\n- iki") == [0, 0, 0, 0, 1])
        // A tab advances to column 4; a line at the item's own column or with no indent is not a continuation.
        #expect(ParagraphSegments.indices(in: "- bir\n\tdevamı\n- iki\nbitişik satır") == [0, 0, 1, 2])
        #expect(ParagraphSegments.indices(in: "  - bir\n\tdevamı") == [0, 0])
        // A tab is 4 columns, not 8: under an item at column 5 it is no continuation, and six spaces
        // continue an item indented by one tab.
        #expect(ParagraphSegments.indices(in: "     - bir\n\tdüz") == [0, 1])
        #expect(ParagraphSegments.indices(in: "\t- bir\n      devamı") == [0, 0])
        #expect(ParagraphSegments.indices(in: "  - bir\n  aynı sütun\n    devamı") == [0, 1, 1])
        #expect(ParagraphSegments.indices(in: "  - bir\n- iki\n  devamı") == [0, 1, 1])
        // Indented prose under prose stays prose; it continues nothing new.
        #expect(ParagraphSegments.indices(in: "düz\n  girintili düz\n- madde") == [0, 0, 1])
    }

    @Test func consecutiveQuoteLinesFormOneSegment() {
        #expect(ParagraphSegments.indices(in: "> bir\n> iki\nDüz cümle.\n> üç") == [0, 0, 1, 2])
        #expect(ParagraphSegments.indices(in: "> - bir\n> - iki\n  > girintili alıntı\n- madde") == [0, 0, 0, 1])
        #expect(ParagraphSegments.indices(in: "Düz.\n>bitişik\n> alıntı") == [0, 1, 1])
    }

    @Test func lineIndexReadsTheSameRule() {
        let text = "- bir\n  devamı\n> alıntı\n> sürer\nDüz."
        #expect((0..<5).map { ParagraphSegments.index(ofLine: $0, in: text) } == [0, 0, 1, 1, 2])
        #expect(ParagraphSegments.index(ofLine: 5, in: text) == 0)
        #expect(ParagraphSegments.index(ofLine: -1, in: text) == 0)
    }
}
