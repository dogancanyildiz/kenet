/// Tracks fences at the top level or relative to the nearest less-indented list item.
struct FenceScanner {
    private var fence: (byte: UInt8, count: Int, level: Int)?
    private var ancestors: [(indent: Int, content: Int?)] = []

    var isOpen: Bool { fence != nil }

    /// Returns true for opening, interior and closing fence lines.
    mutating func consumes(_ bytes: [UInt8]) -> Bool {
        let indent = LineSyntax.indentation(bytes)
        if !bytes.allSatisfy(Syntax.isBlank) {
            while let previous = ancestors.last, previous.indent >= indent.columns { ancestors.removeLast() }
        }
        let parent = ancestors.last?.content
        defer {
            if !bytes.allSatisfy(Syntax.isBlank) {
                ancestors.append((indent.columns, LineSyntax.listContentColumn(bytes, indent: indent)))
            }
        }
        let text = bytes.dropFirst(indent.bytes)
        if let open = fence {
            let run = text.prefix { $0 == open.byte }.count
            if indent.columns >= open.level, indent.columns <= open.level + 3,
                run >= open.count, text.dropFirst(run).allSatisfy(Syntax.isBlank)
            {
                fence = nil
            }
            return true
        }
        guard let marker = text.first, marker == 0x60 || marker == 0x7E else { return false }
        let count = text.prefix { $0 == marker }.count
        guard count >= 3, marker != 0x60 || !text.dropFirst(count).contains(0x60) else { return false }
        let level: Int
        if indent.columns <= 3 {
            level = 0
        } else if let parent, indent.columns >= parent, indent.columns <= parent + 3 {
            level = parent
        } else {
            return false
        }
        fence = (marker, count, level)
        return true
    }
}
