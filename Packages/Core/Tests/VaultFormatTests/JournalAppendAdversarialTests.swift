import Testing

@testable import VaultFormat

/// Hostile documents and hostile appended text, checked against invariants that do not reuse the writer's logic.
///
/// The generator is seeded with a constant, so every run checks exactly the same cases.
struct JournalAppendAdversarialTests {
    static let fragments: [[String]] = [
        ["Düz yazı"], ["### Alt", "Metin"], ["- Kitap", "- Su"], ["- [ ] Görev ^j1", "  devam"], ["\t- [x] İç görev"],
        ["> Alıntı"], ["```", "- [ ] kod", "```"], ["| a | b |", "| - | - |"], ["<!-- yorum -->"],
        ["<!--", "açık yorum"], ["---"], ["***"], ["%%", "gizli", "%%"], ["%% açık"], [""], ["", ""],
        ["", "", "", "", ""], [" \t"], ["    girintili"], ["1. Sıra"], ["$$", "x"], ["- [ ] Son görev"],
    ]
    static let journalHeadings = ["## Journal", "## Journal", "## Journal", "## Journal \t", "## journal", "##Journal"]
    static let hostile = [
        "- [ ] Görev", "- [x] Bitti", "* [ ] Yıldız", "+ [/] Artı", "1. [ ] Sıra", "\t- [ ] Sekme", "    - [ ] Dört",
        "> - [ ] Alıntı", "  devam", "\tdevam", "- 09:30 Su", "## Tasks", "## Events", "## Journal", "# Başlık", "##",
        "```", "~~~~", "```swift", "---", "***", "> alıntı", "| a |", "%%", "<!--", "· düz", "Düz", "### Alt", "", " ",
        "\u{200B}- [ ] sıfır", "\u{00A0}- [ ] nbsp", "a\nb", "a\r\n- [ ] b", "a\u{2028}- [ ] b", "a\u{0085}## Tasks",
        "- [ ] g 📅 2026-09-27 ^abc123", " \u{0301}- [ ] birleşen", "a\r- [ ] b", "\n\n",
    ]

    struct Sample {
        var bytes: [UInt8]
        var hasOpenFence = false
        var isUniform = true
        var ending = "\n"
    }

    static func document(using random: inout SeededGenerator) -> Sample {
        var sample = Sample(bytes: [])
        sample.ending = ["\n", "\r\n", "\r"].randomElement(using: &random)!
        sample.isUniform = Int.random(in: 0..<5, using: &random) != 0
        var lines: [String] = []
        switch Int.random(in: 0..<5, using: &random) {
        case 0: lines += ["---", "type: journal", "custom: sakla", "---"]
        case 1: lines += ["---", "anahtar yok", "---"]
        default: break
        }
        if Bool.random(using: &random) { lines += ["Önsöz", "- [ ] Önsöz görevi"] }
        var blocks = ["T", "E", "J", "N"].shuffled(using: &random)
        if Int.random(in: 0..<4, using: &random) == 0 {
            blocks.insert("J", at: Int.random(in: 0...blocks.count, using: &random))
        }
        if Int.random(in: 0..<6, using: &random) == 0 { blocks.removeAll { $0 == "J" } }
        if Int.random(in: 0..<8, using: &random) == 0 { blocks.append("H") }
        for block in blocks {
            switch block {
            case "T": lines += ["## Tasks", "- [ ] Kitap ^t1", "  devam"]
            case "E": lines += ["## Events", "- 09:30 Su ^e1", "- Yürüyüş"]
            case "N": lines += ["## Notlar", "Sakla", "%%", "gizli", "%%"]
            case "H": lines += ["# Üst", "Metin"]
            default:
                lines.append(journalHeadings.randomElement(using: &random)!)
                for _ in 0..<Int.random(in: 0...4, using: &random) {
                    lines += fragments.randomElement(using: &random)!
                }
                if Int.random(in: 0..<12, using: &random) == 0 {
                    lines += [["```", "açık"], ["~~~"]].randomElement(using: &random)!
                    sample.hasOpenFence = true
                }
            }
            lines += Array(repeating: "", count: [0, 0, 1, 1, 2, 5].randomElement(using: &random)!)
        }
        var text = Int.random(in: 0..<4, using: &random) == 0 ? "\u{FEFF}" : ""
        let terminated = Bool.random(using: &random)
        for (offset, line) in lines.enumerated() {
            text += line
            if offset < lines.count - 1 || terminated {
                text += sample.isUniform ? sample.ending : ["\n", "\r\n", "\r"].randomElement(using: &random)!
            }
        }
        sample.bytes = Array(text.utf8)
        return sample
    }

    /// The visible characters of text, which neutralizing may neither drop nor reorder.
    static func visible(_ text: String) -> [Unicode.Scalar] {
        text.unicodeScalars.filter { !$0.properties.isWhitespace && $0 != "·" }
    }

    static func records(_ document: RawDocument) -> (tasks: [[[UInt8]]], events: [[[UInt8]]]) {
        let body = document.bodyLines
        return (
            body.tasks.map { document.lines[$0.block.lineRange].map(\.content) },
            body.events.map { document.lines[$0.block.lineRange].map(\.content) }
        )
    }

    @Test func hostileAppendsKeepBytesRecordsAndStructure() throws {
        var random = SeededGenerator(seed: 0xA10_BAD)
        var written = 0
        var refused = 0
        var sawEndings: Set<String> = []
        var sawMarked = false
        for iteration in 0..<2000 {
            let sample = Self.document(using: &random)
            let before = RawDocument(bytes: sample.bytes)
            let marker = "İNCELEME\(iteration)"
            let contents =
                [marker]
                + (0..<Int.random(in: 0...4, using: &random)).map { _ in Self.hostile.randomElement(using: &random)! }
            let after: RawDocument
            do {
                after = try before.appendingJournalLines(contents)
            } catch {
                // Only a fence that swallows the insertion point may refuse these documents.
                #expect(sample.hasOpenFence, "refused \(error) at \(iteration)")
                #expect(error == .sectionNotWritable)
                refused += 1
                continue
            }
            written += 1
            let old = sample.bytes
            let new = after.serialized()
            let prefix = zip(old, new).prefix { $0 == $1 }.count
            let suffix = zip(old.dropFirst(prefix).reversed(), new.reversed()).prefix { $0 == $1 }.count
            // A pure insertion: every old byte survives, in order, on one side of the new bytes.
            guard prefix + suffix == old.count, new.count > old.count else {
                Issue.record("old bytes changed at \(iteration)")
                continue
            }
            let insertedBytes = Array(new[prefix..<(new.count - suffix)])
            let inserted = String(decoding: insertedBytes, as: UTF8.self)
            let hadJournal = before.daySections.section(.journal) != nil
            #expect(
                Self.visible(inserted) == Self.visible((hadJournal ? "" : "## Journal") + contents.joined()),
                "content lost at \(iteration)")
            if inserted.contains("·") { sawMarked = true }
            if sample.isUniform, before.lines.contains(where: { $0.ending != nil }) {
                sawEndings.insert(sample.ending)
                let feeds = insertedBytes.indices.filter { insertedBytes[$0] == 10 }
                let returns = insertedBytes.indices.filter { insertedBytes[$0] == 13 }
                switch sample.ending {
                case "\n": #expect(returns.isEmpty, "foreign line ending at \(iteration)")
                case "\r": #expect(feeds.isEmpty, "foreign line ending at \(iteration)")
                default: #expect(feeds == returns.map { $0 + 1 }, "foreign line ending at \(iteration)")
                }
            }
            #expect(after.hasByteOrderMark == before.hasByteOrderMark)
            #expect(after == RawDocument(bytes: new))
            #expect(after.frontmatter == before.frontmatter)
            #expect(Self.records(after) == Self.records(before), "records changed at \(iteration)")
            #expect(after.daySections.sections.count == before.daySections.sections.count + (hadJournal ? 0 : 1))
            #expect(
                after.bodyHeadings.filter { $0.level <= 2 }.count
                    == before.bodyHeadings.filter { $0.level <= 2 }.count + (hadJournal ? 0 : 1))
            // The block is Journal content, one empty line below what was there.
            let journal = try #require(after.daySections.section(.journal))
            let first = try #require(after.lines.firstIndex { $0.text == marker })
            #expect(journal.lineRange.contains(first) && first >= 2)
            #expect(after.lines[first - 1].content.isEmpty)
            #expect(!after.lines[first - 2].content.allSatisfy { $0 == 32 || $0 == 9 })
            let last = try #require(after.lines.lastIndex { !$0.content.allSatisfy { $0 == 32 || $0 == 9 } })
            #expect(journal.lineRange.contains(last) || journal.lineRange.upperBound <= last)
            // Appending again adds a second block and still changes nothing else.
            let again = try after.appendingJournalLines([marker])
            #expect(again.lines.filter { $0.text == marker }.count == 2)
            #expect(Self.records(again) == Self.records(before))
        }
        #expect(written > 1500 && refused > 25)
        #expect(sawEndings.count == 3 && sawMarked)
    }

    @Test func largeDocumentKeepsEveryByte() throws {
        let filler = String(repeating: "Uzun bir günlük satırı. ", count: 8)
        var text = "\u{FEFF}---\r\ntype: journal\r\n---\r\n## Journal\r\n"
        for index in 0..<20_000 { text += "\(index) \(filler)\r\n" }
        let tail = "\r\n\r\n## Notlar\r\nSakla"
        let before = RawDocument(bytes: Array((text + tail).utf8))
        let after = try before.appendingJournalLines(["Yeni"])
        #expect(after.serialized() == Array((text + "\r\nYeni\r\n" + tail).utf8))
    }

    /// The last guard, reached here past the marking that normally makes it unnecessary.
    @Test func unmarkedRecordsAreRefused() throws {
        let before = RawDocument(bytes: Array("## Journal\n- [ ] Kitap\n".utf8))
        for block in [["- [ ] Yeni"], ["  devam"], ["> 1. [x] Alıntı"]] {
            #expect(throws: EditError.contentNotRepresentable) { try before.appendingJournalBlock(block) }
        }
        #expect(try before.appendingJournalBlock(["devam"]).lines.count == 4)
    }

    @Test func emptyAppendNeverChangesOrThrows() throws {
        for bytes in [[], [0xEF, 0xBB, 0xBF], Array("## Journal\n```\n".utf8), [0x23, 0xFF]] as [[UInt8]] {
            let before = RawDocument(bytes: bytes)
            for contents in [[], [""], [" ", "\t"], ["\n", "\r\n"], ["\u{2028}\u{0085}"]] as [[String]] {
                #expect(try before.appendingJournalLines(contents) == before)
            }
        }
    }
}
