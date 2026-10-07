import Foundation
import Testing
import VaultFormat
import VaultIndex

@testable import Journal

struct VaultDisplayTextTests {
    @Test func wikilinkUsesDisplayText() {
        #expect(VaultDisplayText.line("Merhaba [[Hedef|görünen]] dünya") == "Merhaba görünen dünya")
        #expect(VaultDisplayText.line("[[A|B|C]]") == "B|C")
    }

    @Test func pathWikilinkUsesLastComponent() {
        #expect(VaultDisplayText.line("[[Ev]]'de") == "Ev'de")
        #expect(VaultDisplayText.line("[[/people/Deniz Arıkan]]") == "Deniz Arıkan")
        #expect(VaultDisplayText.line("[[places/Liman Ofis.md]]") == "Liman Ofis")
    }

    @Test func headingOnlyAndEmbedLabels() {
        #expect(VaultDisplayText.line("[[#başlık]]") == "başlık")
        #expect(VaultDisplayText.line("![[resim.png]]") == "resim.png")
        #expect(VaultDisplayText.line("[[Ad#^blok]]") == "Ad")
        #expect(VaultDisplayText.line("[[Ad^blok]]") == "Ad")
        #expect(VaultDisplayText.line("[[Ad^blok|gör]]") == "gör")
        #expect(VaultDisplayText.line("önce [[#^a1b2c3]] sonra") == "önce sonra")
        #expect(VaultDisplayText.line("[[#^a1b2c3]] başta") == "başta")
        #expect(VaultDisplayText.line("sonda [[#^a1b2c3]]") == "sonda")
        #expect(VaultDisplayText.line("[[|]]") == "[[|]]")
        #expect(VaultDisplayText.line("[[]]") == "[[]]")
        #expect(VaultDisplayText.line("metin [[") == "metin [[")
    }

    @Test func blockIdentifierIsStrippedOnlyAtLineEnd() {
        #expect(VaultDisplayText.line("Olay satırı ^a1b2c3") == "Olay satırı")
        #expect(VaultDisplayText.line("[[Deniz]] ile yemek ^d4e5f6") == "Deniz ile yemek")
        // Mid-line caret tokens must stay (mutation guard).
        #expect(VaultDisplayText.line("önce ^a1b2c3 sonra") == "önce ^a1b2c3 sonra")
        #expect(VaultDisplayText.line("C^2 formülü") == "C^2 formülü")
        #expect(VaultDisplayText.line("E = mc ^2") == "E = mc ^2")
        #expect(VaultDisplayText.line("2^10") == "2^10")
    }

    @Test func codeFenceAndInlineCodeKeepWikilinks() {
        let fenced = """
            ```
            [[Kod İçi|K]] ^a1b2c3
            ```
            """
        #expect(VaultDisplayText.multiline(fenced) == fenced)
        #expect(VaultDisplayText.line("x `[[A|B]]` y") == "x `[[A|B]]` y")
    }

    @Test func crlfAndMultilineStripBlockIdsPerLine() {
        let crlf = "a\r\n[[B|b]] ^a1b2c3\r\nc"
        #expect(VaultDisplayText.multiline(crlf) == "a\nb\nc")
        let multi = "bir ^a1b2c3\niki ^d4e5f6\nüç"
        #expect(VaultDisplayText.line(multi) == "bir\niki\nüç")
    }

    @Test func multilinePreservesStructure() {
        let input = "[[Ada|A]] bir\n\nikinci ^x9y8z7\n"
        #expect(VaultDisplayText.multiline(input) == "A bir\n\nikinci\n")
    }

    @Test func frontmatterKeepsBlockLikeCaretsAndFormatsDates() {
        #expect(VaultDisplayText.wikilinksOnly("x ^2") == "x ^2")
        #expect(VaultDisplayText.wikilinksOnly("y ^a1b2c3") == "y ^a1b2c3")
        #expect(VaultDisplayText.wikilinksOnly("[[Ev|Evim]] ^a1b2c3") == "Evim ^a1b2c3")

        let document = RawDocument(
            bytes: Array("---\nplace: \"[[Ev|Evim]]\"\npow: \"x ^2\"\nblk: \"y ^a1b2c3\"\n---\n".utf8))
        guard case .parsed(let frontmatter) = document.frontmatter,
            let place = frontmatter.field(named: "place")?.value,
            let pow = frontmatter.field(named: "pow")?.value,
            let blk = frontmatter.field(named: "blk")?.value
        else {
            Issue.record("frontmatter parse failed")
            return
        }
        #expect(FrontmatterValueDisplay.text(place) == "Evim")
        #expect(FrontmatterValueDisplay.text(pow) == "x ^2")
        #expect(FrontmatterValueDisplay.text(blk) == "y ^a1b2c3")

        let dateDoc = RawDocument(bytes: Array("---\nday: 1990-05-14\n---\n".utf8))
        guard case .parsed(let dateFM) = dateDoc.frontmatter,
            let dayValue = dateFM.field(named: "day")?.value
        else {
            Issue.record("date frontmatter parse failed")
            return
        }
        let locale = Locale(identifier: "tr_TR")
        let formatted = FrontmatterValueDisplay.text(dayValue, locale: locale)
        #expect(!formatted.contains("1990-05-14"))
        #expect(formatted.contains("1990"))
    }

    @Test func listAndMappingValuesAreShown() {
        let document = RawDocument(
            bytes: Array(
                """
                ---
                tags: ["[[Ada|A]]", "B"]
                details:
                  language: tr
                  note: "[[Ev]]"
                emptyList: []
                ---
                """.utf8))
        guard case .parsed(let frontmatter) = document.frontmatter,
            let tags = frontmatter.field(named: "tags")?.value,
            let details = frontmatter.field(named: "details")?.value,
            let emptyList = frontmatter.field(named: "emptyList")?.value
        else {
            Issue.record("frontmatter parse failed")
            return
        }
        #expect(FrontmatterValueDisplay.text(tags) == "A, B")
        #expect(!FrontmatterValueDisplay.text(details).isEmpty)
        #expect(FrontmatterValueDisplay.text(details).contains("Ev"))
        #expect(FrontmatterValueDisplay.text(emptyList).isEmpty)
    }

    @Test func frontmatterKeyLabelsAreLocalized() {
        #expect(FrontmatterKeyLabel.localized("aliases") == String(localized: "Takma adlar"))
        #expect(FrontmatterKeyLabel.localized("lat") == String(localized: "Enlem"))
        #expect(FrontmatterKeyLabel.localized("tanışma") == nil)
        #expect(FrontmatterKeyLabel.display("tanışma") == "tanışma")
    }

    @Test func entityFieldRowsSplitKnownAndOtherAndKeepByteIds() {
        let document = RawDocument(bytes: Array("---\nlat: 41.0\nözel: x\n---\n".utf8))
        guard case .parsed(let frontmatter) = document.frontmatter else {
            Issue.record("frontmatter parse failed")
            return
        }
        let fields = frontmatter.fields.map { EntityField(key: $0.key, value: $0.value) }
        let grouped = EntityReadPresentation.fieldRows(fields: fields, schemaKeys: ["lat"])
        #expect(grouped.known.map(\.key) == ["lat"])
        #expect(grouped.known.first?.label == String(localized: "Enlem"))
        #expect(grouped.other.map(\.key) == ["özel"])
        #expect(grouped.other.first?.isOther == true)

        let nfc = "é"
        let nfd = "e\u{0301}"
        #expect(nfc == nfd)
        let rowNFC = EntityReadPresentation.FieldRow(key: nfc, label: nfc, value: "1", isOther: false)
        let rowNFD = EntityReadPresentation.FieldRow(key: nfd, label: nfd, value: "2", isOther: false)
        #expect(rowNFC.id != rowNFD.id)
    }

    @Test func bylineJoinsTypeAliasesAndLastSeen() {
        let locale = Locale(identifier: "en_US_POSIX")
        let text = EntityReadPresentation.byline(
            kindLabel: "Person",
            aliases: ["Ada", "A."],
            lastSeen: CalendarDate("2026-09-25")!,
            locale: locale)
        #expect(text.contains("Person"))
        #expect(text.contains("Ada"))
        #expect(text.contains("A."))
        #expect(text.contains("2026"))
        #expect(!text.contains("2026-09-25"))
    }

    @Test func searchPreviewDropsFenceOpenersAndHeadingMarks() {
        let raw = """
            ## Events
            ```markdown
            [[Ada|A]] ^a1b2c3
            ```
            outside [[Ada|A]] ^a1b2c3
            """
        let preview = SearchPreviewText.display(raw)
        #expect(!preview.contains("```"))
        #expect(!preview.contains("##"))
        #expect(preview.contains("Events"))
        // Search preview humanizes fence interior too (unlike VaultDisplayText.multiline).
        #expect(!preview.contains("[["))
        #expect(preview.contains("A"))
        #expect(preview.contains("outside A"))
        #expect(!preview.contains("^a1b2c3"))
        #expect(SearchPreviewText.display("```\n```").isEmpty)
        #expect(SearchPreviewText.title("```\n```", file: "notes/Proje Fikirleri.md") == "Proje Fikirleri")
    }

    @Test func searchResultsHideMarkupAndPaths() throws {
        let locale = Locale(identifier: "en_US_POSIX")
        let entities = [
            EntitySummary(
                id: "people/Ada.md", kind: "person", name: "Ada", qualifier: "Arkadaş", aliases: ["A."],
                incomingLinks: 0)
        ]
        let payload = """
            [
              {
                "file": "journal/2026-09-14.md",
                "block": 0,
                "text": "[[Ada|Ada]] ile yemek ^a1b2c3",
                "fileKind": "day",
                "blockKind": "event",
                "date": "2026-09-14"
              },
              {
                "file": "notes/Memo.md",
                "block": null,
                "text": "## Events\\n```markdown\\nbody\\n```",
                "fileKind": "note",
                "blockKind": null,
                "date": null
              },
              {
                "file": "notes/Proje Fikirleri.md",
                "block": 2,
                "text": "- [ ] Ada ile konuş ^b2c3d4",
                "fileKind": "note",
                "blockKind": "task",
                "date": null
              },
              {
                "file": "notes/EmptyFence.md",
                "block": null,
                "text": "```\\n```",
                "fileKind": "note",
                "blockKind": null,
                "date": null
              }
            ]
            """
        let matches = try JSONDecoder().decode([SearchResult].self, from: Data(payload.utf8))
        let items = SearchResults.build(
            query: "Ada", entities: entities, matches: matches, locale: locale)
        let person = try #require(items.first { $0.group == SearchGroup.people })
        #expect(person.id == "entity:people/Ada.md")
        #expect(!person.detail.contains("people/"))
        #expect(!person.detail.contains(".md"))
        let event = items.first { $0.group == SearchGroup.events }
        #expect(event?.title == "Ada ile yemek")
        #expect(event?.detail.contains("2026") == true)
        #expect(event?.detail.contains("2026-09-14") != true)
        let note = items.first { $0.group == SearchGroup.notes && $0.id.hasPrefix("notes/Memo.md") }
        #expect(note?.detail == "Memo")
        #expect(note?.detail.contains("notes/") != true)
        #expect(note?.title.contains("```") != true)
        #expect(note?.title.contains("##") != true)
        let task = items.first { $0.group == SearchGroup.tasks }
        #expect(task?.detail == "Proje Fikirleri")
        #expect(task?.detail.contains(".md") != true)
        #expect(task?.detail.contains("notes/") != true)
        let emptyFence = items.first { $0.id.hasPrefix("notes/EmptyFence.md") }
        #expect(emptyFence?.title == "EmptyFence")
    }

    @Test func dayPreviewAndEntityNotesUseDisplayTransform() {
        #expect(VaultDisplayText.line("[[Liman|Liman]] ^a1b2c3") == "Liman")
        #expect(
            VaultDisplayText.multiline("Not [[Ev|Evim]]\n^satır ^a1b2c3")
                == "Not Evim\n^satır")
    }
}
