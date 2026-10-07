import Foundation
import Testing
import VaultFormat

struct SectionRandomTests {
    private struct Block {
        var kind: DaySectionKind?
        var lines: [String]
    }

    @Test func randomDocumentsAndAppendsPreserveBytesAndStructure() throws {
        var random = SeededGenerator(seed: 0x5EC7_10A5)
        for iteration in 0..<500 {
            var ending = ["\n", "\r\n", "\r"].randomElement(using: &random)!
            let bom = Bool.random(using: &random) ? "\u{FEFF}" : ""
            let front = Bool.random(using: &random) ? ["---", "type: day", "---"] : []
            var preamble = Bool.random(using: &random) ? ["ön", ""] : []
            var seen: Set<DaySectionKind> = []
            var blocks: [Block] = []
            for _ in 0..<Int.random(in: 0...8, using: &random) {
                let kind = DaySectionKind.allCases.randomElement(using: &random)!
                let known = seen.insert(kind).inserted
                var lines = ["## " + kind.rawValue, "not \(iteration)"]
                if Bool.random(using: &random) { lines += ["### Notes", "not"] }
                if Bool.random(using: &random) { lines += ["~~~", "## Events", "~~~~"] }
                lines += Array(repeating: "", count: Int.random(in: 0...3, using: &random))
                blocks.append(Block(kind: known ? kind : nil, lines: lines))
                if Bool.random(using: &random) { blocks.append(Block(kind: nil, lines: ["## Other", "not"])) }
            }
            let originalLines = front + preamble + blocks.flatMap(\.lines)
            if originalLines.isEmpty { ending = "\n" }
            let terminated = Bool.random(using: &random) || originalLines.last == ""
            func bytes(_ lines: [String], terminated: Bool) -> [UInt8] {
                Array((bom + lines.joined(separator: ending) + (terminated && !lines.isEmpty ? ending : "")).utf8)
            }
            let input = bytes(originalLines, terminated: terminated)
            let before = RawDocument(bytes: input)
            #expect(before.serialized() == input)
            #expect(
                SectionSnapshot.json(before.daySections) == snapshot(front: front, preamble: preamble, blocks: blocks))
            let target = DaySectionKind.allCases.randomElement(using: &random)!
            let additions = (0..<Int.random(in: 1...4, using: &random)).map { "yeni \(iteration)-\($0)" }
            var expectedLines = originalLines
            let position: Int
            var inserted = additions
            if let blockIndex = blocks.firstIndex(where: { $0.kind == target }) {
                let start = front.count + preamble.count + blocks.prefix(blockIndex).flatMap(\.lines).count
                let tail = blocks[blockIndex].lines.reversed().prefix { $0.isEmpty }.count
                let local = blocks[blockIndex].lines.count - tail
                position = start + local
                blocks[blockIndex].lines.insert(contentsOf: additions, at: local)
            } else {
                let ranks: [DaySectionKind: Int] = [.tasks: 0, .events: 1, .journal: 2]
                let later = DaySectionKind.allCases.filter { ranks[$0]! > ranks[target]! }
                let blockIndex =
                    later.compactMap { next in blocks.firstIndex { $0.kind == next } }.first ?? blocks.count
                position = front.count + preamble.count + blocks.prefix(blockIndex).flatMap(\.lines).count
                inserted = ["## " + target.rawValue] + additions
                let needsBefore = position > 0 && expectedLines[position - 1] != ""
                if needsBefore { inserted.insert("", at: 0) }
                if position < expectedLines.count { inserted.append("") }
                // A separating blank belongs to the preceding region.
                if needsBefore {
                    if blockIndex > 0 {
                        blocks[blockIndex - 1].lines.append("")
                    } else {
                        preamble.append("")
                    }
                }
                blocks.insert(
                    Block(kind: target, lines: Array(inserted.dropFirst(needsBefore ? 1 : 0))), at: blockIndex)
            }
            expectedLines.insert(contentsOf: inserted, at: position)
            let after = try before.appendingLines(additions, toSection: target)
            let expected = bytes(expectedLines, terminated: position == originalLines.count || terminated)
            let reread = RawDocument(bytes: after.serialized())
            let targetSection = try #require(reread.daySections.section(target))
            for addition in additions {
                #expect(targetSection.lineRange.contains { reread.lines[$0].text == addition })
            }
            #expect(after.serialized() == expected, "iteration \(iteration)")
            #expect(after.daySections == RawDocument(bytes: expected).daySections)
            #expect(
                SectionSnapshot.json(after.daySections) == snapshot(front: front, preamble: preamble, blocks: blocks))
            // Every original line survives in order with identical bytes, except the primitive's
            // documented termination of a last line when appending beyond EOF.
            var cursor = 0
            for (index, line) in before.lines.enumerated() {
                let match = after.lines.indices.dropFirst(cursor).first { after.lines[$0].content == line.content }
                let found = try #require(match)
                if line.ending != nil || found == after.lines.count - 1 {
                    #expect(after.lines[found].bytes == line.bytes)
                } else {
                    #expect(index == before.lines.count - 1)
                    #expect(after.lines[found].bytes == line.content + before.lineEndingForNewLines.bytes)
                }
                cursor = found + 1
            }
        }
    }

    private func snapshot(front: [String], preamble: [String], blocks: [Block]) -> JSONValue {
        var offset = front.count + preamble.count
        let items = blocks.map { block -> JSONValue in
            defer { offset += block.lines.count }
            return .object([
                "kind": block.kind.map { .string($0.rawValue) } ?? .null,
                "headingLine": .integer(offset + 1), "level": .integer(2),
                "firstLine": .integer(offset + 1), "lastLine": .integer(offset + block.lines.count),
            ])
        }
        return .object([
            "preamble": preamble.isEmpty
                ? .null
                : .object([
                    "firstLine": .integer(front.count + 1), "lastLine": .integer(front.count + preamble.count),
                ]),
            "items": .array(items),
        ])
    }
}
