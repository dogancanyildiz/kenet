/// Checks that the lines below a key are block YAML every reader accepts.
///
/// The lines are never interpreted here; the supported subset is read elsewhere. This only
/// decides between "valid but possibly outside the subset" and "not to be trusted". It accepts
/// nested mappings and lists with consistent indentation, including a mapping or list that
/// starts on the line of a list dash, and refuses everything it is not sure about.
struct BlockValidator {
    private struct Line {
        let bytes: [UInt8]
        /// The column the node on this line starts at. For a node that starts after a list
        /// dash on the same line it is the column after the dash.
        var start: Int
    }

    private var lines: [Line]
    private var index = 0
    private var anchors: Set<[UInt8]>
    private var holdsBlockScalar = false

    /// Whether the lines, which must not be blank or comments, form valid block YAML.
    /// `holdsBlockScalar` tells whether a block scalar is among them: its text cannot be
    /// checked here, because blank and comment-like lines were left out.
    static func isValid(_ contents: [[UInt8]], anchors: inout Set<[UInt8]>, holdsBlockScalar: inout Bool) -> Bool {
        let lines = contents.map { Line(bytes: $0, start: $0.prefix { $0 == Syntax.space }.count) }
        guard let first = lines.first else { return true }
        var validator = BlockValidator(lines: lines, anchors: anchors)
        let isValid = validator.collection(at: first.start, onlyItems: false) && validator.index == lines.count
        anchors = validator.anchors
        holdsBlockScalar = validator.holdsBlockScalar
        return isValid
    }

    /// Reads the mapping or list whose entries start at `column`. With `onlyItems`, a list at
    /// the column of its parent key ends at the first line that is not an item.
    private mutating func collection(at column: Int, onlyItems: Bool) -> Bool {
        let isList = FrontmatterLineScanner.isListItem(lines[index].bytes, at: column)
        var keys: Set<[UInt8]> = []
        while index < lines.count, lines[index].start == column {
            let line = lines[index].bytes
            let isItem = FrontmatterLineScanner.isListItem(line, at: column)
            if isList {
                if !isItem { return onlyItems }
                guard item(line, at: column) else { return false }
            } else {
                guard !isItem, entry(line, at: column, keys: &keys) else { return false }
            }
        }
        return index == lines.count || lines[index].start < column
    }

    private mutating func item(_ line: [UInt8], at column: Int) -> Bool {
        var content = column + 1
        while content < line.count, line[content] == Syntax.space {
            content += 1
        }
        guard content < line.count, line[content] != Syntax.hash else {
            index += 1
            return nested(below: column, allowsItemsAtColumn: false)
        }
        guard line[content] != Syntax.tab else { return false }

        // A list or a mapping may start on the line of the dash; it continues below at that column.
        var startsCollection = FrontmatterLineScanner.isListItem(line, at: content)
        if !startsCollection {
            switch FrontmatterLineScanner.key(in: line, from: content) {
            case .key: startsCollection = true
            case .broken: return false
            case .notAKey: break
            }
        }
        if startsCollection {
            lines[index].start = content
            return collection(at: content, onlyItems: false)
        }
        return value(line, from: column + 1, column: column, allowsItemsAtColumn: false)
    }

    private mutating func entry(_ line: [UInt8], at column: Int, keys: inout Set<[UInt8]>) -> Bool {
        guard case .key(let key, let colon) = FrontmatterLineScanner.key(in: line, from: column) else { return false }
        let keyBytes = Array(key.utf8)
        guard keyBytes != Syntax.mergeKey, keys.insert(keyBytes).inserted else { return false }
        return value(line, from: colon + 1, column: column, allowsItemsAtColumn: true)
    }

    private mutating func value(_ line: [UInt8], from start: Int, column: Int, allowsItemsAtColumn: Bool) -> Bool {
        let scanned = FrontmatterLineScanner.value(in: line, from: start, allowsList: true, anchors: &anchors)
        index += 1
        switch scanned {
        case .broken:
            return false
        case .blockScalar(let indentation):
            // The text is every deeper line, none indented less than the first. A header that
            // states the indentation is not accepted this deep.
            guard indentation == nil else { return false }
            holdsBlockScalar = true
            let first = index < lines.count ? lines[index].start : 0
            while index < lines.count, lines[index].start > column {
                guard lines[index].start >= first else { return false }
                index += 1
            }
            return true
        case .scalar(let scalar, _, _) where scalar.raw.isEmpty:
            return nested(below: column, allowsItemsAtColumn: allowsItemsAtColumn)
        case .unsupported(acceptsChildren: true):
            return nested(below: column, allowsItemsAtColumn: allowsItemsAtColumn)
        case .scalar, .list, .unsupported:
            // Text that continues on deeper lines is valid YAML, but not accepted this deep.
            return index == lines.count || lines[index].start <= column
        }
    }

    /// Reads the collection that belongs to the entry or item just read, when one follows.
    private mutating func nested(below column: Int, allowsItemsAtColumn: Bool) -> Bool {
        guard index < lines.count else { return true }
        let next = lines[index]
        if next.start > column { return collection(at: next.start, onlyItems: false) }
        if allowsItemsAtColumn, next.start == column, FrontmatterLineScanner.isListItem(next.bytes, at: column) {
            return collection(at: column, onlyItems: true)
        }
        return true
    }
}
