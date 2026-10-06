import Foundation
import Testing
import VaultFormat

@testable import Journal

struct VaultDisplayTextTests {
    @Test func wikilinkUsesDisplayText() {
        #expect(VaultDisplayText.line("Merhaba [[Hedef|görünen]] dünya") == "Merhaba görünen dünya")
    }

    @Test func pathWikilinkUsesLastComponent() {
        #expect(VaultDisplayText.line("[[/places/Ev]]'de") == "Ev'de")
        #expect(VaultDisplayText.line("[[places/Liman Ofis.md]]") == "Liman Ofis")
    }

    @Test func blockIdentifierIsStripped() {
        #expect(VaultDisplayText.line("Olay satırı ^a1b2c3") == "Olay satırı")
        #expect(VaultDisplayText.line("[[Deniz]] ile yemek ^d4e5f6") == "Deniz ile yemek")
    }

    @Test func caretInsideWordsIsKept() {
        #expect(VaultDisplayText.line("C^2 formülü") == "C^2 formülü")
    }

    @Test func multilinePreservesStructure() {
        let input = "[[Ada|A]] bir\n\nikinci ^x9y8z7\n"
        #expect(VaultDisplayText.multiline(input) == "A bir\n\nikinci\n")
    }

    @Test func frontmatterKeyLabelsAreLocalized() {
        #expect(FrontmatterKeyLabel.localized("aliases") == String(localized: "Takma adlar"))
        #expect(FrontmatterKeyLabel.localized("lat") == String(localized: "Enlem"))
        #expect(FrontmatterKeyLabel.localized("tanışma") == nil)
        #expect(FrontmatterKeyLabel.display("tanışma") == "tanışma")
    }

    @Test func entityFieldRowsSplitKnownAndOther() {
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
    }

    @Test func linkFieldValueHidesWikilinkMarkup() {
        let document = RawDocument(bytes: Array("---\nplace: \"[[Ev|Evim]]\"\n---\n".utf8))
        guard case .parsed(let frontmatter) = document.frontmatter,
            let value = frontmatter.field(named: "place")?.value
        else {
            Issue.record("frontmatter parse failed")
            return
        }
        #expect(FrontmatterValueDisplay.text(value) == "Evim")
    }
}
