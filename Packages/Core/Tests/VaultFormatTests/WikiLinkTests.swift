import Foundation
import Testing
import VaultFormat

struct WikiLinkTests {
    @Test func sampleVaultHasExactTargetsAndCount() throws {
        let paths = try Fixtures.markdownPaths(in: "vaults/sample").filter { !$0.contains("/conflicts/") }
        let expected: Set<String> = [
            "Baran Tunç", "Deniz Arıkan", "Ece Yalın", "Ev", "Henüz Yazılmamış Not", "Liman Ofis",
            "Mert Aksu", "Mert Aksu (iş)", "Okuma Listesi", "Proje Fikirleri", "Selin Korkmaz",
            "Tepe Spor Salonu", "Toplantı Notları", "Çınaraltı Kafe",
        ]
        var targets: Set<String> = []
        var count = 0
        for path in paths {
            let document = RawDocument(bytes: try Fixtures.bytes(at: path))
            let links = document.links
            targets.formUnion(links.map(\.target))
            count += links.count
            if path.hasSuffix("notes/Toplantı Notları.md") {
                #expect(links.count == 1)
                #expect(links.first?.target == "Liman Ofis")
                #expect(links.allSatisfy { $0.line == 15 })
            }
        }
        #expect(targets == expected)
        // Independent regex count: 62 spellings outside conflicts minus one fenced example.
        #expect(count == 61)
        let names = Set(
            paths.map {
                URL(fileURLWithPath: $0).deletingPathExtension().lastPathComponent.precomposedStringWithCanonicalMapping
            })
        #expect(expected.subtracting(["Henüz Yazılmamış Not"]).isSubset(of: names))
        #expect(!names.contains("Henüz Yazılmamış Not"))
    }

    @Test func randomInputHasPhysicalLinkRangesAndPreservesBytes() {
        var random = SeededGenerator(seed: 0x11A1_B17E)
        var count = 0
        for _ in 0..<1000 {
            var bytes = (0..<Int.random(in: 0...200, using: &random)).map { _ in
                UInt8.random(in: 0...255, using: &random)
            }
            let pieces = [
                "[[", "]]", "Ev", "Çınaraltı Kafe", "🙂", "#^kimlik", "|metin|ek",
                "`", "``", "!", "\\", " ", "\n", "\r",
            ]
            bytes += Array("\n".utf8)
            for _ in 0..<80 { bytes += Array(pieces.randomElement(using: &random)!.utf8) }
            bytes += Array("\n[[Deniz Arıkan]] [[#Başlık]] ![[Ev]]\n".utf8)
            let document = RawDocument(bytes: bytes)
            let links = document.links
            count += links.count
            for link in links {
                #expect(document.lines.indices.contains(link.line))
                let content = document.lines[link.line].content
                #expect(link.byteRange.lowerBound >= 0)
                #expect(link.byteRange.upperBound <= content.count)
                #expect(link.byteRange.count >= 4)
                #expect(link.targetRange.lowerBound >= link.byteRange.lowerBound + 2)
                #expect(link.targetRange.upperBound <= link.byteRange.upperBound - 2)
                #expect(link.targetRange.lowerBound <= link.targetRange.upperBound)
                #expect(content[link.byteRange].starts(with: [91, 91]))
                #expect(content[link.byteRange].suffix(2).elementsEqual([93, 93]))
                #expect(Array(link.rawTarget.utf8) == Array(content[link.targetRange]))
            }
            #expect(document.serialized() == bytes)
        }
        #expect(count > 1000)
    }
}
