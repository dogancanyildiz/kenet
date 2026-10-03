import Foundation

/// Random day files for the merge tests: a plausible ancestor, random edits of it, and noise.
///
/// Edits work on lines of text, so that they stay independent of the merge's own reading code.
enum MergeSampleDay {
    static let people = ["Deniz Arıkan", "Selin Korkmaz", "Baran Tunç", "Ece Yalın", "Mert Aksu"]
    static let places = ["Çınaraltı Kafe", "Liman Ofis", "Tepe Spor Salonu", "Ev"]
    static let words = ["Su", "Kitap", "Spor", "Toplantı", "Kahve", "Yürüyüş", "Plan", "Alışveriş"]

    private static func pick<T>(_ items: [T], using random: inout SeededGenerator) -> T {
        items[Int(random.next() % UInt64(items.count))]
    }

    private static func chance(_ percent: UInt64, using random: inout SeededGenerator) -> Bool {
        random.next() % 100 < percent
    }

    private static func id(_ tag: String, _ counter: inout Int) -> String {
        counter += 1
        return "\(tag)x\(counter)"
    }

    /// A day file with frontmatter and the usual sections, as both devices had it before editing.
    static func ancestor(using random: inout SeededGenerator) -> [String] {
        var lines: [String] = []
        var counter = 0
        if chance(85, using: &random) {
            lines += ["---", "type: journal", "date: 2026-09-21"]
            if chance(70, using: &random) {
                lines.append("goals:")
                lines.append("  spor: \(chance(50, using: &random) ? "true" : "false")")
                lines.append("  kitap: \(random.next() % 40)")
                if chance(50, using: &random) { lines.append("  su: \(random.next() % 10)") }
            }
            if chance(30, using: &random) { lines.append("mood: \(pick(words, using: &random))") }
            lines.append("---")
            if chance(80, using: &random) { lines.append("") }
        } else if chance(30, using: &random) {
            lines += ["Ön yazı.", ""]
        }
        if chance(85, using: &random) {
            lines.append("## Tasks")
            for _ in 0..<(1 + random.next() % 4) {
                let closed = chance(30, using: &random)
                let box = closed ? "[x]" : "[ ]"
                let done = closed ? " ✅ 2026-09-21" : ""
                lines.append(
                    "- \(box) \(pick(words, using: &random)) 📅 2026-09-2\(random.next() % 9)\(done) ^\(id("t", &counter))"
                )
                if chance(25, using: &random) { lines.append("  - alt not \(random.next() % 10)") }
            }
            lines.append("")
        }
        if chance(85, using: &random) {
            lines.append("## Events")
            var hour = 7
            for _ in 0..<(1 + random.next() % 4) {
                hour += Int(1 + random.next() % 3)
                let time = chance(80, using: &random) ? String(format: "%02d:00 ", min(hour, 23)) : ""
                lines.append(
                    "- \(time)[[\(pick(people, using: &random))]] ile [[\(pick(places, using: &random))]] ^\(id("e", &counter))"
                )
            }
            lines.append("")
        }
        if chance(80, using: &random) {
            lines.append("## Journal")
            for index in 0..<(1 + random.next() % 3) {
                lines.append("Gün \(index): \(pick(words, using: &random)) ve [[\(pick(people, using: &random))]].")
            }
        }
        return lines
    }

    /// The ancestor after zero to four random edits, as bytes. Unless `unclosedFences` is allowed,
    /// every code fence the result holds is closed, so that the merge never has to give up.
    static func edited(
        _ ancestor: [String], using random: inout SeededGenerator, tag: String, unclosedFences: Bool = false
    ) -> [UInt8] {
        var lines = ancestor
        var counter = 0
        for _ in 0..<(random.next() % 5) {
            switch random.next() % 23 {
            case 0:
                addToSection(
                    &lines, "## Tasks", "- [ ] \(pick(words, using: &random)) ^\(id(tag, &counter))", using: &random)
            case 1:
                let hour = String(format: "%02d:%02d", random.next() % 24, random.next() % 60)
                let time = chance(75, using: &random) ? "\(hour) " : ""
                addToSection(
                    &lines, "## Events", "- \(time)\(pick(words, using: &random)) ^\(id(tag, &counter))", using: &random
                )
            case 2: deleteBlock(&lines, using: &random)
            case 3: toggleStatus(&lines, using: &random)
            case 4: changeText(&lines, using: &random)
            case 5: addToSection(&lines, "## Journal", "Ek \(tag): \(pick(words, using: &random)).", using: &random)
            case 6: deleteFreeLine(&lines, using: &random, fences: unclosedFences)
            case 7: changeGoal(&lines, using: &random)
            case 8: addField(&lines, "\(pick(words, using: &random).lowercased())\(tag): \(random.next() % 100)")
            case 9: lines.append(contentsOf: ["", "## Notlar \(tag)", "Düşünce \(random.next() % 5)."])
            case 10:
                addToSection(&lines, "## Journal", "```", using: &random)
                addToSection(&lines, "## Journal", "- [ ] sahte \(tag)", using: &random)
                addToSection(&lines, "## Journal", "```", using: &random)
            case 11: duplicateLine(&lines, using: &random)
            case 12: if lines.first == "---" { lines.insert("bozuk satır", at: 1) }
            case 13:
                if let closing = lines.dropFirst().firstIndex(of: "---"), lines.first == "---" {
                    lines.removeSubrange(0...closing)
                }
            case 14:
                addToSection(
                    &lines, "## Journal",
                    chance(50, using: &random) ? "> - [ ] alıntı \(tag)" : "  - [ ] girintili \(tag)", using: &random)
            case 15: addToSection(&lines, "## Tasks", "  - [ ] alt görev \(tag)", using: &random)
            case 16: duplicateFreeLine(&lines, using: &random)
            case 17: swapFreeLines(&lines, using: &random)
            case 18:
                if lines.first == "---", let closing = lines.dropFirst().firstIndex(of: "---") {
                    let position = 1 + Int(random.next() % UInt64(closing))
                    if chance(50, using: &random) || lines[position] == "goals:" || lines[position].hasPrefix("  ") {
                        lines.insert("# yorum \(tag)", at: position)
                    } else {
                        lines[position] += " # yorum \(tag)"
                    }
                }
            case 19:
                if let heading = lines.firstIndex(where: { $0.hasPrefix("## Notlar") }) {
                    lines[heading] = "## Fikirler \(tag)"
                } else if let heading = lines.firstIndex(of: "## Journal"), chance(30, using: &random) {
                    lines[heading] = "## Günlük"
                }
            case 20:
                if let heading = lines.firstIndex(where: { $0.hasPrefix("## ") && !$0.hasSuffix(" ") }) {
                    lines[heading] += "  "
                }
            case 21:
                let starts = blockStarts(lines)
                if !starts.isEmpty { lines.insert("\t- sekmeli not \(tag)", at: pick(starts, using: &random) + 1) }
            default: addToSection(&lines, "## Journal", "", using: &random)
            }
        }
        var bytes = Array((lines.joined(separator: "\n") + "\n").utf8)
        switch random.next() % 8 {
        case 0: bytes = ReferenceModel.bytes(bytes, withEveryEndingAs: .crlf)
        case 1: bytes = ReferenceModel.bytes(bytes, withEveryEndingAs: .cr)
        case 2: bytes = [0xEF, 0xBB, 0xBF] + bytes
        case 3: bytes.removeLast()
        default: break
        }
        return bytes
    }

    /// Random bytes drawn from the characters that carry meaning in the format.
    static func garbage(using random: inout SeededGenerator) -> [UInt8] {
        let alphabet: [[UInt8]] = [
            Array("- [ ] ".utf8), Array("- [x] ".utf8), Array("## Tasks\n".utf8), Array("## Events\n".utf8),
            Array("## Journal\n".utf8), Array("---\n".utf8), Array("goals:\n".utf8), Array("  kitap: 3\n".utf8),
            Array("type: journal\n".utf8), Array("^ab1\n".utf8), Array(" ✅ 2026-09-21".utf8), Array("09:00 ".utf8),
            Array("```\n".utf8), Array("[[Ev]]".utf8), Array("Su".utf8), Array("\n".utf8), Array("\r\n".utf8),
            Array("\r".utf8), Array("  ".utf8), Array("> ".utf8), Array("#".utf8), Array("::".utf8),
            [0xEF, 0xBB, 0xBF],
            [0xFF], Array("ğ".utf8),
        ]
        var bytes: [UInt8] = []
        for _ in 0..<(random.next() % 40) {
            let piece = alphabet[Int(random.next() % UInt64(alphabet.count))]
            if piece == [0xFF], random.next() % 10 != 0 { continue }
            bytes += piece
        }
        return bytes
    }

    /// The bytes with a few random byte-level changes.
    static func mutated(_ bytes: [UInt8], using random: inout SeededGenerator) -> [UInt8] {
        var result = bytes
        for _ in 0..<(1 + random.next() % 3) {
            let position = result.isEmpty ? 0 : Int(random.next() % UInt64(result.count))
            switch random.next() % 3 {
            case 0 where !result.isEmpty: result.remove(at: position)
            case 1: result.insert(contentsOf: garbage(using: &random).prefix(8), at: position)
            default: if !result.isEmpty { result[position] = UInt8(ascii: "x") }
            }
        }
        return result
    }

    private static func section(_ lines: [String], _ heading: String) -> Range<Int>? {
        guard let start = lines.firstIndex(of: heading) else { return nil }
        let end = lines[(start + 1)...].firstIndex { $0.hasPrefix("## ") || $0.hasPrefix("# ") } ?? lines.count
        return start..<end
    }

    private static func addToSection(
        _ lines: inout [String], _ heading: String, _ line: String, using random: inout SeededGenerator
    ) {
        guard let range = section(lines, heading) else {
            lines.append(contentsOf: ["", heading, line])
            return
        }
        let candidates = Array(range.dropFirst()).filter { !lines[$0].hasPrefix("  ") } + [range.upperBound]
        lines.insert(line, at: pick(candidates, using: &random))
    }

    private static func blockStarts(_ lines: [String]) -> [Int] {
        lines.indices.filter { lines[$0].hasPrefix("- ") }
    }

    private static func blockRange(_ lines: [String], at start: Int) -> Range<Int> {
        var end = start + 1
        while end < lines.count, lines[end].hasPrefix("  ") { end += 1 }
        return start..<end
    }

    private static func deleteBlock(_ lines: inout [String], using random: inout SeededGenerator) {
        let starts = blockStarts(lines)
        guard !starts.isEmpty else { return }
        lines.removeSubrange(blockRange(lines, at: pick(starts, using: &random)))
    }

    private static func toggleStatus(_ lines: inout [String], using random: inout SeededGenerator) {
        let tasks = lines.indices.filter { lines[$0].hasPrefix("- [") }
        guard !tasks.isEmpty else { return }
        let index = pick(tasks, using: &random)
        if lines[index].hasPrefix("- [ ]") {
            lines[index] = "- [x]" + lines[index].dropFirst(5)
            if let caret = lines[index].lastIndex(of: "^") {
                lines[index].insert(contentsOf: "✅ 2026-09-21 ", at: caret)
            }
        } else {
            lines[index] = "- [ ]" + lines[index].dropFirst(5).replacingOccurrences(of: " ✅ 2026-09-21", with: "")
        }
    }

    private static func changeText(_ lines: inout [String], using random: inout SeededGenerator) {
        let starts = blockStarts(lines)
        guard !starts.isEmpty else { return }
        let index = pick(starts, using: &random)
        if let caret = lines[index].lastIndex(of: "^") {
            lines[index].insert(contentsOf: "\(pick(words, using: &random)) ", at: caret)
        } else {
            lines[index] += " \(pick(words, using: &random))"
        }
    }

    private static func freeLines(_ lines: [String]) -> [Int] {
        lines.indices.filter {
            !lines[$0].hasPrefix("-") && !lines[$0].hasPrefix("#") && !lines[$0].isEmpty && !lines[$0].contains(":")
                && lines[$0] != "---" && !lines[$0].hasPrefix("  ") && !lines[$0].hasPrefix("\t")
        }
    }

    private static func duplicateFreeLine(_ lines: inout [String], using random: inout SeededGenerator) {
        let candidates = freeLines(lines).filter { lines[$0] != "```" }
        guard !candidates.isEmpty else { return }
        let index = pick(candidates, using: &random)
        lines.insert(lines[index], at: index + (chance(50, using: &random) ? 1 : 0))
    }

    private static func swapFreeLines(_ lines: inout [String], using random: inout SeededGenerator) {
        let candidates = freeLines(lines).filter { lines[$0] != "```" }
        guard candidates.count >= 2 else { return }
        let first = pick(candidates, using: &random)
        let second = pick(candidates, using: &random)
        lines.swapAt(first, second)
    }

    private static func deleteFreeLine(_ lines: inout [String], using random: inout SeededGenerator, fences: Bool) {
        let candidates = lines.indices.filter {
            !lines[$0].hasPrefix("-") && !lines[$0].hasPrefix("#") && !lines[$0].isEmpty && !lines[$0].contains(":")
                && lines[$0] != "---" && (fences || lines[$0] != "```")
        }
        guard !candidates.isEmpty else { return }
        lines.remove(at: pick(candidates, using: &random))
    }

    private static func changeGoal(_ lines: inout [String], using random: inout SeededGenerator) {
        guard let goals = lines.firstIndex(of: "goals:"), lines.first == "---" else {
            addField(&lines, "goals:")
            if lines.first == "---", let goals = lines.firstIndex(of: "goals:") {
                lines.insert("  su: 1", at: goals + 1)
            }
            return
        }
        var end = goals + 1
        while end < lines.count, lines[end].hasPrefix("  ") { end += 1 }
        switch random.next() % 3 {
        case 0:
            lines.insert("  \(pick(["su", "yürüyüş", "meditasyon"], using: &random)): \(random.next() % 5)", at: end)
        case 1 where end > goals + 1:
            let index = goals + 1 + Int(random.next() % UInt64(end - goals - 1))
            let parts = lines[index].split(separator: ":", maxSplits: 1)
            let key = String(parts[0])
            let value = parts.count > 1 ? parts[1].trimmingCharacters(in: .whitespaces) : ""
            if value == "true" || value == "false" {
                lines[index] = "\(key): \(value == "true" ? "false" : "true")"
            } else if let number = Int(value) {
                lines[index] = "\(key): \(max(0, number + Int(random.next() % 7) - 3))"
            }
        default: break
        }
    }

    private static func addField(_ lines: inout [String], _ line: String) {
        guard lines.first == "---", let closing = lines.dropFirst().firstIndex(of: "---") else {
            lines.insert(contentsOf: ["---", line, "---"], at: 0)
            return
        }
        lines.insert(line, at: closing)
    }

    private static func duplicateLine(_ lines: inout [String], using random: inout SeededGenerator) {
        let starts = blockStarts(lines)
        guard !starts.isEmpty else { return }
        let index = pick(starts, using: &random)
        lines.insert(lines[index], at: index + 1)
    }
}
