import VaultFormat

/// Whether a value read from a file is the value that was written, judged independently of the writer.
func literal(_ literal: FrontmatterLiteral, isReadBackAs scalar: FrontmatterScalar) -> Bool {
    switch literal {
    case .text(let text): scalar.kind == .text && Array(scalar.text.utf8) == Array(text.utf8)
    case .boolean(let value): scalar.kind == .boolean(value)
    case .integer(let value): scalar.kind == .number && scalar.doubleValue == Double(value)
    case .number(let spelling): scalar.kind == .number && scalar.doubleValue == Double(spelling)
    case .date(let date): scalar.kind == .date(date)
    }
}

/// Returns every way a successful frontmatter edit broke its contract.
///
/// An empty result means: the edited document is what reading its bytes gives, every byte
/// outside the frontmatter is unchanged, inside the frontmatter only the lines of the target
/// key changed, a new key sits at the end of the block, every other field still reads the same,
/// the written value reads back, and applying the same operation again changes nothing.
///
/// The comparison is made on bytes, so it also holds for files that mix line endings.
func frontmatterEditViolations(
    before: RawDocument,
    after: RawDocument,
    operation: FrontmatterOperation
) -> [String] {
    var violations: [String] = []
    let bytes = after.serialized()
    if RawDocument(bytes: bytes) != after {
        violations.append("the edited document differs from what reading its bytes gives")
    }
    violations += losslessViolations(of: bytes)
    if after.hasByteOrderMark != before.hasByteOrderMark {
        violations.append("the byte order mark changed")
    }

    switch (before.frontmatter, after.frontmatter) {
    case (.unreadable, _):
        violations.append("an edit succeeded although the frontmatter is unreadable")
    case (.absent, .parsed(let edited)):
        if Array(after.lines[edited.lineRange.upperBound...]) != before.lines {
            violations.append("lines of the file changed when a frontmatter block was added in front")
        }
        if edited.fields.map({ Array($0.key.utf8) }) != [Array(operation.key.utf8)] {
            violations.append("the new block holds other fields than the target: \(edited.fields.map(\.key))")
        }
        if after.lines[edited.lineRange].contains(where: { $0.ending != before.lineEndingForNewLines }) {
            violations.append("a line of the new block does not end with the line ending for new lines")
        }
    case (.absent, _):
        if after != before { violations.append("the file changed but has no readable frontmatter") }
        if !operation.isRemoval { violations.append("nothing was written") }
    case (.parsed, .absent), (.parsed, .unreadable):
        violations.append("the frontmatter is no longer readable")
    case (.parsed(let original), .parsed(let edited)):
        let bodyBefore = before.lines[original.lineRange.upperBound...].flatMap(\.bytes)
        let bodyAfter = after.lines[edited.lineRange.upperBound...].flatMap(\.bytes)
        if bodyBefore != bodyAfter {
            violations.append("bytes after the frontmatter changed")
        }
        let keptBefore = untargetedBytes(of: original, in: before, key: operation.key)
        let keptAfter = untargetedBytes(of: edited, in: after, key: operation.key)
        if !keptAfter.contains(keptBefore[0]) {
            violations.append(
                "frontmatter bytes outside the target key changed: \(visible(keptBefore[0])) became \(visible(keptAfter[0]))"
            )
        }
        if original.field(named: operation.key) == nil, let added = edited.field(named: operation.key),
            added.lineRange.upperBound != edited.lineRange.upperBound - 1
        {
            violations.append("the new key is not at the end of the frontmatter")
        }
        let othersBefore = otherFields(of: original, key: operation.key)
        let othersAfter = otherFields(of: edited, key: operation.key)
        if othersBefore != othersAfter {
            violations.append("other fields read differently: \(othersBefore) became \(othersAfter)")
        }
    }

    if !operation.isReadBack(from: after.frontmatter) {
        violations.append("the written value does not read back")
    }
    if (try? operation.apply(to: after)) != after {
        violations.append("applying the operation a second time changes the document")
    }
    return violations.map { "\($0) [\(operation)]" }
}

/// The bytes of the block without the key, item and entry lines of the target field. Comment
/// and blank lines inside the target field are not its lines and must survive.
///
/// The first element takes every target line with its whole line ending. A target line that
/// ends in CRLF may owe its LF to an untouched empty line that followed a CR (the two bytes
/// read as one ending), so the other elements are the readings in which such an LF is kept.
private func untargetedBytes(of frontmatter: Frontmatter, in document: RawDocument, key: String) -> [[UInt8]] {
    var targeted: Set<Int> = []
    if let field = frontmatter.field(named: key) {
        targeted = Set(
            field.lineRange.filter { index in
                let content = document.lines[index].content.drop { $0 == 0x20 || $0 == 0x09 }
                return !content.isEmpty && content.first != 0x23
            }
        )
    }
    var readings: [[UInt8]] = [[]]
    for index in frontmatter.lineRange {
        let line = document.lines[index]
        if !targeted.contains(index) {
            readings = readings.map { $0 + line.bytes }
        } else if line.ending == .crlf {
            readings += readings.map { $0 + [0x0A] }
        }
    }
    return readings
}

/// Every field except the one with the target key, without line numbers.
private func otherFields(of frontmatter: Frontmatter, key: String) -> [JSONValue] {
    frontmatter.fields
        .filter { Array($0.key.utf8) != Array(key.utf8) }
        .map { FrontmatterSnapshot.json($0, withLines: false) }
}

extension FrontmatterOperation {
    var isRemoval: Bool {
        switch self {
        case .removeEntry, .removeField: true
        case .setValue, .setList, .setEntry: false
        }
    }

    /// Whether reading the frontmatter shows the result the operation asked for.
    func isReadBack(from state: FrontmatterState) -> Bool {
        var field: FrontmatterField?
        if case .parsed(let frontmatter) = state {
            field = frontmatter.field(named: key)
        }
        switch self {
        case .setValue(_, let value):
            guard case .scalar(let scalar) = field?.value else { return false }
            return literal(value, isReadBackAs: scalar)
        case .setList(_, let items):
            guard let read = field?.value.listItems, read.count == items.count else { return false }
            return zip(items, read).allSatisfy { literal($0, isReadBackAs: $1) }
        case .setEntry(_, let entryKey, let value):
            guard case .mapping(let entries) = field?.value else { return false }
            guard let entry = entries.first(where: { Array($0.key.utf8) == Array(entryKey.utf8) }) else { return false }
            return literal(value, isReadBackAs: entry.value)
        case .removeEntry(_, let entryKey):
            guard case .mapping(let entries) = field?.value else { return true }
            return !entries.contains { Array($0.key.utf8) == Array(entryKey.utf8) }
        case .removeField:
            return field == nil
        }
    }
}
