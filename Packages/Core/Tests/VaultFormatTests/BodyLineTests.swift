import Foundation
import Testing
import VaultFormat

struct BodyLineTests {
    @Test func sampleVaultHasDocumentedCounts() throws {
        let paths = try Fixtures.markdownPaths(in: "vaults/sample/journal")
        #expect(paths.count == 14)
        var tasks = 0
        var events = 0
        for path in paths {
            let body = RawDocument(bytes: try Fixtures.bytes(at: path)).bodyLines
            tasks += body.tasks.count
            events += body.events.count
        }
        #expect(tasks == 22)
        #expect(events == 40)
        let note = RawDocument(bytes: try Fixtures.bytes(at: "vaults/sample/notes/Proje Fikirleri.md")).bodyLines
        #expect(note.tasks.count == 2)
        #expect(note.tasks.allSatisfy { $0.block.id == nil })
        #expect(note.events.isEmpty)
        let meeting = RawDocument(bytes: try Fixtures.bytes(at: "vaults/sample/notes/Toplantı Notları.md")).bodyLines
        #expect(meeting.tasks.isEmpty)
        #expect(meeting.events.isEmpty)
    }

    @Test func randomBytesHaveBoundedBlocksAndRealCheckboxes() throws {
        let checkbox = try NSRegularExpression(pattern: "^[ \t>]*(?:[-*+]|[0-9]+[.)]) +\\[.\\]( |$)")
        var random = SeededGenerator(seed: 0xE7E1_11AE)
        var taskCount = 0
        var eventCount = 0
        for _ in 0..<1000 {
            var bytes = (0..<Int.random(in: 0...300, using: &random)).map { _ in
                UInt8.random(in: 0...255, using: &random)
            }
            // Inject recognizable structure as well as arbitrary bytes, so invariants are exercised.
            if Bool.random(using: &random) {
                bytes += Array("\n## Events\n- 9:05 olay\n- [X] görev\n  devam\n".utf8)
                for _ in 0..<Int.random(in: 2...12, using: &random) {
                    let prefix = ["", "  ", "    ", "\t", " \t ", "> ", "> > "].randomElement(using: &random)!
                    let marker = ["-", "12.", "3)"].randomElement(using: &random)!
                    bytes += Array((prefix + marker + "  [ ] görev\n").utf8)
                    if Bool.random(using: &random) { bytes += Array("\n".utf8) }
                }
            }
            let document = RawDocument(bytes: bytes)
            let body = document.bodyLines
            taskCount += body.tasks.count
            eventCount += body.events.count
            for block in body.tasks.map(\.block) + body.events.map(\.block) {
                #expect(block.lineRange.lowerBound >= 0)
                #expect(block.lineRange.upperBound <= document.lines.count)
                #expect(!block.lineRange.isEmpty)
                #expect(block.line == block.lineRange.lowerBound)
                let firstIndent = columns(document.lines[block.line].content)
                for index in block.lineRange.dropFirst() {
                    let content = document.lines[index].content
                    if !content.allSatisfy({ $0 == 32 || $0 == 9 }) {
                        #expect(columns(content) > firstIndent)
                    }
                }
            }
            for task in body.tasks {
                let content = document.lines[task.block.line].content
                if content.prefix(while: { $0 == 32 || $0 == 9 || $0 == 62 }).contains(62) {
                    #expect(task.block.lineRange.count == 1)
                }
                let text = document.lines[task.block.line].displayText
                let range = NSRange(text.startIndex..<text.endIndex, in: text)
                #expect(checkbox.firstMatch(in: text, range: range) != nil)
            }
            #expect(document.serialized() == bytes)
        }
        #expect(taskCount > 100)
        #expect(eventCount > 100)
    }

    /// Independent column counting for the block ownership invariant.
    private func columns(_ bytes: [UInt8]) -> Int {
        var column = 0
        for byte in bytes {
            switch byte {
            case 32: column += 1
            case 9: column = (column / 4 + 1) * 4
            default: return column
            }
        }
        return column
    }
}
