/// A line that holds one value, split around the value so that it can be rewritten in place.
struct LinePart: Hashable, Sendable {
    /// The index of the line in the document.
    let line: Int
    /// Everything before the value: the key through its colon, or the indentation and the dash.
    let head: String
    /// The blanks between the head and the value. Empty when the line has no value.
    let gap: String
    /// Everything after the value: trailing blanks and a comment.
    let tail: String

    /// The line with another value in place of the current one. The head, the spacing before
    /// the value and a trailing comment are kept.
    func rebuilt(with raw: String) -> String {
        let keptTail = tail.utf8.contains(Syntax.hash) ? tail : ""
        return head + (gap.isEmpty ? " " : gap) + raw + keptTail
    }
}

/// Where the parts of a field are in the document.
struct FieldLayout: Hashable, Sendable {
    /// The key line. Its value is the scalar or inline list, or nothing when children follow.
    let keyPart: LinePart
    /// The item lines of a block list or the entry lines of a mapping, in order.
    let children: [LinePart]
    /// The indentation of the children.
    let childIndent: String
}
