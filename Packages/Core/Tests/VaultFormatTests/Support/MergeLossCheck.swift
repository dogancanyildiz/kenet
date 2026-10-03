import VaultFormat

/// An independent check of the merge's promise that no content is lost silently.
///
/// It shares no code with the merge's own guard: it works on lines of text and on the public
/// reading API. Every nonblank body line and every frontmatter line and field of a version has to
/// be in the result, or the version has to be preserved. The exceptions are the ones the format
/// allows: a closed task in place of an open one with the same text, a closed task in place of a
/// closed one with the same checkbox that differs in its completion date only, a goal entry that
/// progressed, a frontmatter value that differs in spelling only, and line endings or the byte
/// order mark. Free text is counted region by region, so a reordered or repeated line is noticed.
enum MergeLossCheck {
    /// Descriptions of the content of `version` that the result lacks although the version is not preserved.
    static func violations(version: [UInt8], result: [UInt8], isPreserved: Bool) -> [String] {
        if isPreserved || version == result { return [] }
        let document = RawDocument(bytes: version)
        let merged = RawDocument(bytes: result)
        if document.isReadOnly { return ["a read-only version that differs from the result is not preserved"] }

        var violations: [String] = []
        let versionBlocks = blocks(of: document)
        let resultBlocks = blocks(of: merged)
        var exactMatches: [[[UInt8]]: [Int]] = [:]
        for (index, block) in resultBlocks.enumerated() {
            exactMatches[block.lines, default: []].append(index)
        }
        var unmatched: [Block] = []
        for block in versionBlocks {
            if var candidates = exactMatches[block.lines], !candidates.isEmpty {
                candidates.removeLast()
                exactMatches[block.lines] = candidates
            } else {
                unmatched.append(block)
            }
        }
        var replacements: [[[UInt8]]: [Int]] = [:]
        for index in exactMatches.values.joined() where resultBlocks[index].task != nil {
            replacements[resultBlocks[index].normalized, default: []].append(index)
        }
        for block in unmatched {
            if var candidates = replacements[block.normalized],
                let allowed = candidates.firstIndex(where: { mayReplace(resultBlocks[$0], block) })
            {
                candidates.remove(at: allowed)
                replacements[block.normalized] = candidates
            } else {
                violations.append("block at line \(block.firstLine + 1) is missing: \(text(block.lines[0]))")
            }
        }

        let versionRegions = regions(of: document, excluding: versionBlocks)
        var resultRegions = regions(of: merged, excluding: blocks(of: merged))
        for region in versionRegions {
            guard let index = resultRegions.firstIndex(where: { $0.key == region.key }) else {
                violations.append("region \(text(region.key ?? [])) is missing")
                continue
            }
            var available = resultRegions.remove(at: index).freeText
            for line in region.freeText {
                if let found = available.firstIndex(of: line) {
                    available.remove(at: found)
                } else {
                    violations.append("free text line is missing from region \(text(region.key ?? [])): \(text(line))")
                }
            }
        }
        violations += frontmatterViolations(document, merged)
        return violations
    }

    private static func text(_ bytes: [UInt8]) -> String { String(decoding: bytes, as: UTF8.self) }

    private static func isBlank(_ bytes: [UInt8]) -> Bool { bytes.allSatisfy { $0 == 0x20 || $0 == 0x09 } }

    // MARK: Blocks

    struct Block {
        let firstLine: Int
        let lines: [[UInt8]]
        let task: TaskLine?

        /// The first line with the checkbox character and a completion date at its end removed.
        var normalized: [[UInt8]] {
            guard let task else { return lines }
            return [normalizedTask(task)] + lines.dropFirst()
        }
    }

    /// The events, and the tasks that are neither indented nor quoted, with their lines.
    static func blocks(of document: RawDocument) -> [Block] {
        let body = document.bodyLines
        var found: [Block] = []
        for task in body.tasks {
            let first = task.block.firstLineContent
            guard let byte = first.first, byte != 0x20, byte != 0x09, byte != UInt8(ascii: ">") else { continue }
            found.append(Block(firstLine: task.block.line, lines: lines(document, task.block), task: task))
        }
        for event in body.events {
            found.append(Block(firstLine: event.block.line, lines: lines(document, event.block), task: nil))
        }
        return found.sorted { $0.firstLine < $1.firstLine }
    }

    private static func lines(_ document: RawDocument, _ block: LineBlock) -> [[UInt8]] {
        block.lineRange.map { document.lines[$0].content }
    }

    /// Rule (a): a closed task for an open one with the same text. Rule (b): a closed task for a
    /// closed one with the same checkbox character, differing in the completion date only.
    static func mayReplace(_ kept: Block, _ lost: Block) -> Bool {
        guard let keptTask = kept.task, let lostTask = lost.task, keptTask.status.isClosed,
            kept.normalized == lost.normalized
        else { return false }
        return lostTask.status.isOpen || keptTask.rawStatus.lowercased() == lostTask.rawStatus.lowercased()
    }

    /// The first line of a task with the checkbox character and a ` ✅ YYYY-MM-DD` that stands at
    /// the end of the text, before the identifier, removed.
    static func normalizedTask(_ task: TaskLine) -> [UInt8] {
        var bytes = task.block.firstLineContent
        let checkbox = Array(("[" + task.rawStatus + "]").utf8)
        if let start = bytes.indices.first(where: { bytes[$0...].starts(with: checkbox) }) {
            bytes.replaceSubrange(start..<(start + checkbox.count), with: Array("[]".utf8))
        }
        var tail: [UInt8] = []
        if let id = task.block.id {
            let suffix = Array(" ^\(id)".utf8)
            let end = bytes.count - bytes.reversed().prefix(while: { $0 == 0x20 || $0 == 0x09 }).count
            if end >= suffix.count, Array(bytes[(end - suffix.count)..<end]) == suffix {
                tail = Array(bytes[(end - suffix.count)...])
                bytes.removeSubrange((end - suffix.count)...)
            }
        }
        let trimmedEnd = bytes.count - bytes.reversed().prefix(while: { $0 == 0x20 || $0 == 0x09 }).count
        let mark = Array(" ✅ ".utf8)
        if trimmedEnd >= mark.count + 10 {
            let date = bytes[(trimmedEnd - 10)..<trimmedEnd]
            let isDate = date.enumerated().allSatisfy { offset, byte in
                offset == 4 || offset == 7 ? byte == UInt8(ascii: "-") : (0x30...0x39).contains(byte)
            }
            if isDate, bytes[(trimmedEnd - 10 - mark.count)..<(trimmedEnd - 10)].elementsEqual(mark) {
                bytes.removeSubrange((trimmedEnd - 10 - mark.count)..<trimmedEnd)
            }
        }
        return bytes + tail
    }

    // MARK: Regions

    struct Region {
        /// The heading without trailing blanks; `nil` before the first heading.
        let key: [UInt8]?
        /// The nonblank lines that are neither the heading nor part of a block.
        var freeText: [[UInt8]]
    }

    /// The body split at first and second level headings outside code fences.
    static func regions(of document: RawDocument, excluding blocks: [Block]) -> [Region] {
        var blockLines: Set<Int> = []
        for block in blocks {
            blockLines.formUnion(block.firstLine..<(block.firstLine + block.lines.count))
        }
        var regions = [Region(key: nil, freeText: [])]
        var fence: (marker: UInt8, count: Int)?
        let start = document.frontmatterLineRange?.upperBound ?? 0
        for index in start..<document.lines.count {
            let content = document.lines[index].content
            let indent = content.prefix { $0 == 0x20 }.count
            let rest = Array(content.dropFirst(indent))
            if let open = fence {
                let run = rest.prefix { $0 == open.marker }.count
                if indent <= 3, run >= open.count, rest.dropFirst(run).allSatisfy({ $0 == 0x20 || $0 == 0x09 }) {
                    fence = nil
                }
            } else if indent <= 3, let marker = rest.first, marker == UInt8(ascii: "`") || marker == UInt8(ascii: "~") {
                let run = rest.prefix { $0 == marker }.count
                if run >= 3, marker != UInt8(ascii: "`") || !rest.dropFirst(run).contains(UInt8(ascii: "`")) {
                    fence = (marker, run)
                }
            } else if indent <= 3, !content.prefix(indent).contains(0x09) {
                let level = rest.prefix { $0 == UInt8(ascii: "#") }.count
                if (1...2).contains(level), rest.count == level || rest[level] == 0x20 || rest[level] == 0x09 {
                    let key = Array(content.reversed().drop(while: { $0 == 0x20 || $0 == 0x09 }).reversed())
                    regions.append(Region(key: key, freeText: []))
                    continue
                }
            }
            if !blockLines.contains(index), !isBlank(content) {
                regions[regions.count - 1].freeText.append(content)
            }
        }
        return regions
    }

    // MARK: Frontmatter

    private static func frontmatterViolations(_ document: RawDocument, _ merged: RawDocument) -> [String] {
        switch document.frontmatter {
        case .absent:
            return []
        case .unreadable:
            let block = document.frontmatterLineRange.map { document.lines[$0].map(\.content) }
            let mergedBlock = merged.frontmatterLineRange.map { merged.lines[$0].map(\.content) }
            return block == mergedBlock ? [] : ["the unreadable frontmatter block was not kept as it was"]
        case .parsed(let frontmatter):
            var violations = frontmatterLineViolations(document, frontmatter.lineRange, merged)
            guard case .parsed(let mergedFrontmatter) = merged.frontmatter else {
                return violations + (frontmatter.fields.isEmpty ? [] : ["the result has no readable frontmatter"])
            }
            for field in frontmatter.fields {
                guard let counterpart = mergedFrontmatter.field(named: field.key) else {
                    violations.append("field \(field.key) is missing")
                    continue
                }
                if sameValue(field.value, counterpart.value) { continue }
                if field.key == "goals", case .mapping(let entries) = field.value,
                    case .mapping(let mergedEntries) = counterpart.value
                {
                    for entry in entries {
                        let found = mergedEntries.first { Array($0.key.utf8) == Array(entry.key.utf8) }
                        guard let found,
                            sameScalar(entry.value, found.value) || progressed(from: entry.value, to: found.value)
                        else {
                            violations.append("goal \(entry.key) lost its value \(entry.value.raw)")
                            continue
                        }
                    }
                } else {
                    violations.append("field \(field.key) lost its value")
                }
            }
            return violations
        }
    }

    /// Every nonblank line between the delimiters is in the merged block verbatim, or is a field
    /// line without a comment (its value is checked separately), or its comment reappears on a
    /// merged line with the same key part.
    private static func frontmatterLineViolations(
        _ document: RawDocument, _ range: Range<Int>, _ merged: RawDocument
    ) -> [String] {
        var available =
            merged.frontmatterLineRange.map { range in
                range.dropFirst().dropLast().map { merged.lines[$0].content }
            } ?? []
        var violations: [String] = []
        for index in range.dropFirst().dropLast() {
            let content = document.lines[index].content
            if isBlank(content) { continue }
            if let found = available.firstIndex(of: content) {
                available.remove(at: found)
                continue
            }
            guard let comment = comment(of: content) else { continue }
            let key = keyPart(of: content)
            if key.isEmpty {
                violations.append("comment line is missing from the frontmatter: \(text(content))")
            } else if let found = available.firstIndex(where: {
                keyPart(of: $0) == key && self.comment(of: $0) == comment
            }) {
                available.remove(at: found)
            } else {
                violations.append("the comment on \(text(key)) is missing from the frontmatter")
            }
        }
        return violations
    }

    /// The comment of a YAML line: a `#` at the start or after a blank, outside quotes. `nil` when there is none.
    static func comment(of line: [UInt8]) -> [UInt8]? {
        var quote: UInt8?
        for (index, byte) in line.enumerated() {
            if let open = quote {
                if byte == open { quote = nil }
            } else if byte == UInt8(ascii: "\"") || byte == UInt8(ascii: "'") {
                quote = byte
            } else if byte == UInt8(ascii: "#"), index == 0 || line[index - 1] == 0x20 || line[index - 1] == 0x09 {
                return Array(line[index...])
            }
        }
        return nil
    }

    /// The line up to and including its key's colon or its list dash, without indentation; empty
    /// for a comment line.
    static func keyPart(of line: [UInt8]) -> [UInt8] {
        let trimmed = Array(line.drop(while: { $0 == 0x20 }))
        if trimmed.first == UInt8(ascii: "#") { return [] }
        if trimmed.first == UInt8(ascii: "-"), trimmed.count == 1 || trimmed[1] == 0x20 { return [UInt8(ascii: "-")] }
        var quote: UInt8?
        for (index, byte) in trimmed.enumerated() {
            if let open = quote {
                if byte == open { quote = nil }
            } else if index == 0, byte == UInt8(ascii: "\"") || byte == UInt8(ascii: "'") {
                quote = byte
            } else if byte == UInt8(ascii: ":"),
                index + 1 == trimmed.count || trimmed[index + 1] == 0x20 || trimmed[index + 1] == 0x09
            {
                return Array(trimmed[...index])
            }
        }
        return trimmed
    }

    // MARK: Values

    static func sameScalar(_ first: FrontmatterScalar, _ second: FrontmatterScalar) -> Bool {
        switch (first.kind, second.kind) {
        case (.text, .text): Array(first.text.utf8) == Array(second.text.utf8)
        case (.number, .number): first.doubleValue == second.doubleValue
        case (.boolean(let a), .boolean(let b)): a == b
        case (.date(let a), .date(let b)): a == b
        case (.empty, .empty): true
        default: false
        }
    }

    static func sameValue(_ first: FrontmatterValue, _ second: FrontmatterValue) -> Bool {
        switch (first, second) {
        case (.raw(let a), .raw(let b)):
            return Array(a.utf8) == Array(b.utf8)
        case (.mapping(let a), .mapping(let b)):
            return a.count == b.count
                && a.allSatisfy { entry in
                    b.contains { Array($0.key.utf8) == Array(entry.key.utf8) && sameScalar($0.value, entry.value) }
                }
        default:
            guard let a = first.listItems, let b = second.listItems, a.count == b.count else { return false }
            return zip(a, b).allSatisfy(sameScalar)
        }
    }

    /// Whether the merged goal value is at least as far along as the version's: a larger or equal
    /// number, or `true` against `false`.
    static func progressed(from old: FrontmatterScalar, to new: FrontmatterScalar) -> Bool {
        switch (old.kind, new.kind) {
        case (.number, .number):
            guard let a = old.doubleValue, let b = new.doubleValue else { return false }
            return b >= a
        case (.boolean, .boolean(let b)):
            return b
        default:
            return false
        }
    }
}
