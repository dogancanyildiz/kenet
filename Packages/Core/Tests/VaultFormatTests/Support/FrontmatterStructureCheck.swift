import VaultFormat

/// Returns every way the frontmatter read from a document contradicts the document's own lines.
///
/// The check holds for any input, so it is what the random input tests assert: the block is
/// delimited by the first two `---` lines, fields lie inside it in order without overlapping,
/// every line outside a field is blank or a comment, and values are spelled on their lines.
func frontmatterStructureViolations(of document: RawDocument) -> [String] {
    let lines = document.lines
    let delimiter = Array("---".utf8)
    guard case .parsed(let frontmatter) = document.frontmatter else { return [] }
    var violations: [String] = []
    let range = frontmatter.lineRange

    guard range.lowerBound == 0, range.count >= 2, range.upperBound <= lines.count else {
        return ["the block \(range) does not fit the \(lines.count) lines of the document"]
    }
    let closing = range.upperBound - 1
    if lines[0].content != delimiter || lines[closing].content != delimiter {
        violations.append("the block is not delimited by --- lines")
    }
    if lines[1..<closing].contains(where: { $0.content == delimiter }) {
        violations.append("the block does not end at the first closing line")
    }
    if lines[range].contains(where: { $0.text == nil }) {
        violations.append("a line of a parsed block is not valid UTF-8")
    }

    var covered: Set<Int> = []
    var previousEnd = 1
    for field in frontmatter.fields {
        let fieldRange = field.lineRange
        guard !fieldRange.isEmpty, fieldRange.lowerBound >= previousEnd, fieldRange.upperBound <= closing else {
            violations.append("the field \(field.key) at \(fieldRange) is out of order or outside the block")
            continue
        }
        previousEnd = fieldRange.upperBound
        covered.formUnion(fieldRange)
        let keyLine = lines[fieldRange.lowerBound].content

        switch field.value {
        case .scalar(let scalar):
            if fieldRange.count != 1 { violations.append("the single value \(field.key) spans \(fieldRange)") }
            if !contains(keyLine, scalar.raw) { violations.append("\(field.key): \(scalar.raw) is not on its line") }
        case .list(let items, .inline):
            if fieldRange.count != 1 { violations.append("the inline list \(field.key) spans \(fieldRange)") }
            for item in items where !contains(keyLine, item.raw) {
                violations.append("\(field.key): the item \(item.raw) is not on its line")
            }
        case .list(let items, .block):
            if items.isEmpty || fieldRange.count < items.count + 1 {
                violations.append("the block list \(field.key) has \(items.count) items on \(fieldRange)")
            }
        case .mapping(let entries):
            var previousLine = fieldRange.lowerBound
            for entry in entries {
                if entry.line <= previousLine || entry.line >= fieldRange.upperBound {
                    violations.append("\(field.key): the entry \(entry.key) is on line \(entry.line)")
                } else if !contains(lines[entry.line].content, entry.value.raw) {
                    violations.append("\(field.key): the entry value \(entry.value.raw) is not on its line")
                }
                previousLine = entry.line
            }
            if entries.isEmpty { violations.append("the mapping \(field.key) has no entries") }
        case .raw:
            break
        }
    }

    for index in 1..<closing where !covered.contains(index) {
        let content = lines[index].content.drop { $0 == 0x20 || $0 == 0x09 }
        if !content.isEmpty, content.first != 0x23 {
            violations.append("line \(index) belongs to no field but is neither blank nor a comment")
        }
    }
    return violations.map { "\($0) [input: \(hex(document.serialized().prefix(96)))]" }
}

private func contains(_ line: [UInt8], _ text: String) -> Bool {
    let needle = Array(text.utf8)
    guard !needle.isEmpty else { return true }
    guard line.count >= needle.count else { return false }
    return (0...(line.count - needle.count)).contains { Array(line[$0..<($0 + needle.count)]) == needle }
}
