/// Puts the merged frontmatter and body together as a document.
enum MergeAssembly {
    /// Lines taken from a version keep their own endings; a line that lacks one and is not the
    /// last line gets the newer version's ending for new lines. A trailing empty line without an
    /// ending is nothing at all and is dropped. An empty line ending in LF that comes to stand
    /// after a line ending in CR takes a CR ending, because the bytes would otherwise read as one
    /// CRLF and the empty line would vanish.
    static func document(
        frontmatter: [RawLine], body: [RawLine], hasByteOrderMark: Bool, newLineEnding: LineEnding
    ) -> RawDocument {
        var lines = frontmatter + body
        while let last = lines.last, last.ending == nil, last.content.isEmpty {
            lines.removeLast()
        }
        for index in lines.indices {
            if lines[index].ending == nil, index < lines.count - 1 {
                lines[index] = RawLine(content: lines[index].content, ending: newLineEnding)
            }
            if index > 0, lines[index - 1].ending == .cr, lines[index].content.isEmpty, lines[index].ending == .lf {
                lines[index] = RawLine(content: [], ending: .cr)
            }
        }
        return RawDocument(hasByteOrderMark: hasByteOrderMark, lines: lines)
    }
}
