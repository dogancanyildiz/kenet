extension RawDocument {
    /// Returns a document in which the field holds the given single value.
    ///
    /// Only the lines of that key change. A key that is not there yet is added at the end of
    /// the frontmatter, and a file without frontmatter gets a new block at its start. Writing
    /// the value the field already has returns the document unchanged.
    public func settingFrontmatterValue(
        _ value: FrontmatterLiteral,
        forKey key: String
    ) throws(EditError) -> RawDocument {
        let frontmatter = try writableFrontmatter()
        let keySpelling = try FrontmatterWriter.keySpelling(key)
        guard let frontmatter else {
            let line = FrontmatterWriter.line(key: keySpelling, value: try value.spelling(inFlow: false))
            return try replacingLines(in: 0..<0, with: FrontmatterWriter.block([line]))
        }
        guard let field = frontmatter.field(named: key) else {
            let line = FrontmatterWriter.line(key: keySpelling, value: try value.spelling(inFlow: false))
            return try appending([line], to: frontmatter)
        }

        switch field.value {
        case .raw:
            throw .rawField(key: key)
        case .scalar(let current) where value.matches(current):
            return self
        case .scalar, .list, .mapping:
            return try replacingValue(of: field, with: try value.spelling(inFlow: false))
        }
    }

    /// Returns a document in which the field holds the given list.
    ///
    /// A list that is already there keeps its form: an inline list stays on its line, and in a
    /// list with one line per item only the lines of items that differ change. Anything else is
    /// written as an inline list. A single value counts as a list of one item, so writing the
    /// items the field already has returns the document unchanged.
    public func settingFrontmatterList(
        _ items: [FrontmatterLiteral],
        forKey key: String
    ) throws(EditError) -> RawDocument {
        let frontmatter = try writableFrontmatter()
        let keySpelling = try FrontmatterWriter.keySpelling(key)
        guard let frontmatter, let field = frontmatter.field(named: key) else {
            let value = FrontmatterWriter.inlineList(try spellings(of: items, reusing: [], inFlow: true))
            let line = FrontmatterWriter.line(key: keySpelling, value: value)
            guard let frontmatter else { return try replacingLines(in: 0..<0, with: FrontmatterWriter.block([line])) }
            return try appending([line], to: frontmatter)
        }

        if case .raw = field.value { throw .rawField(key: key) }
        let current = field.value.listItems
        if let current, current.count == items.count, zip(items, current).allSatisfy({ $0.matches($1) }) {
            return self
        }
        if case .list(let current, style: .block) = field.value {
            return try applying(try blockListEdits(from: current, to: items, layout: field.layout))
        }
        let value = FrontmatterWriter.inlineList(try spellings(of: items, reusing: current ?? [], inFlow: true))
        return try replacingValue(of: field, with: value)
    }

    /// Returns a document in which the mapping under `key` holds the given value for `entryKey`.
    ///
    /// Only the line of that entry changes; a new entry is added after the last one. A key that
    /// is missing or has no value yet becomes a mapping. Writing the value the entry already
    /// has returns the document unchanged.
    public func settingFrontmatterEntry(
        _ value: FrontmatterLiteral,
        forKey entryKey: String,
        inMapping key: String
    ) throws(EditError) -> RawDocument {
        let frontmatter = try writableFrontmatter()
        let keySpelling = try FrontmatterWriter.keySpelling(key)
        let entrySpelling = try FrontmatterWriter.keySpelling(entryKey)
        func entryLine(indent: String) throws(EditError) -> String {
            FrontmatterWriter.line(key: entrySpelling, value: try value.spelling(inFlow: false), indent: indent)
        }

        guard let frontmatter, let field = frontmatter.field(named: key) else {
            let lines = [keySpelling + ":", try entryLine(indent: FrontmatterWriter.entryIndent)]
            guard let frontmatter else { return try replacingLines(in: 0..<0, with: FrontmatterWriter.block(lines)) }
            return try appending(lines, to: frontmatter)
        }

        switch field.value {
        case .raw:
            throw .rawField(key: key)
        case .mapping(let entries):
            guard let index = entries.firstIndex(where: { Syntax.exactlyEqual($0.key, entryKey) }) else {
                let line = try entryLine(indent: field.layout.childIndent)
                return try replacingLines(in: field.lineRange.upperBound..<field.lineRange.upperBound, with: [line])
            }
            if value.matches(entries[index].value) { return self }
            let part = field.layout.children[index]
            return try replacingLines(
                in: part.line..<(part.line + 1),
                with: [part.rebuilt(with: try value.spelling(inFlow: false))]
            )
        case .scalar(let scalar) where scalar.raw.isEmpty:
            let line = try entryLine(indent: FrontmatterWriter.entryIndent)
            return try replacingLines(in: field.lineRange.upperBound..<field.lineRange.upperBound, with: [line])
        case .scalar, .list:
            throw .notAMapping(key: key)
        }
    }

    /// Returns a document without the entry `entryKey` in the mapping under `key`.
    ///
    /// Only the line of that entry is removed; the key of the mapping stays even when no entry
    /// is left. When there is no such entry the document is returned unchanged.
    public func removingFrontmatterEntry(
        forKey entryKey: String,
        inMapping key: String
    ) throws(EditError) -> RawDocument {
        guard let field = try writableFrontmatter()?.field(named: key) else { return self }
        if case .raw = field.value { throw .rawField(key: key) }
        guard case .mapping(let entries) = field.value else { return self }
        guard let entry = entries.first(where: { Syntax.exactlyEqual($0.key, entryKey) }) else { return self }
        return try replacingLines(in: entry.line..<(entry.line + 1), with: [])
    }

    /// Returns a document without the field `key`.
    ///
    /// The key line and the item or entry lines below it are removed. Comment and blank lines
    /// between them stay. When there is no such field the document is returned unchanged.
    public func removingFrontmatterField(forKey key: String) throws(EditError) -> RawDocument {
        guard let field = try writableFrontmatter()?.field(named: key) else { return self }
        if case .raw = field.value { throw .rawField(key: key) }
        let lines = [field.layout.keyPart.line] + field.layout.children.map(\.line)
        return try applying(lines.map(LineEdit.removing))
    }
}

extension RawDocument {
    /// The frontmatter to edit, or `nil` when the file has none and a block has to be created.
    private func writableFrontmatter() throws(EditError) -> Frontmatter? {
        guard !isReadOnly else { throw .readOnlyDocument }
        switch frontmatter {
        case .absent: return nil
        case .unreadable: throw .unreadableFrontmatter
        case .parsed(let frontmatter): return frontmatter
        }
    }

    /// Adds field lines at the end of the frontmatter, directly before its closing line.
    private func appending(_ fieldLines: [String], to frontmatter: Frontmatter) throws(EditError) -> RawDocument {
        let closingLine = frontmatter.lineRange.upperBound - 1
        return try replacingLines(in: closingLine..<closingLine, with: fieldLines)
    }

    /// Puts a value on the key line of a field and removes the item or entry lines below it.
    private func replacingValue(of field: FrontmatterField, with raw: String) throws(EditError) -> RawDocument {
        let keyPart = field.layout.keyPart
        let edits = [LineEdit.replacing(line: keyPart.line, with: keyPart.rebuilt(with: raw))]
        return try applying(edits + field.layout.children.map { LineEdit.removing(line: $0.line) })
    }

    private func spellings(
        of items: [FrontmatterLiteral],
        reusing existing: [FrontmatterScalar],
        inFlow: Bool
    ) throws(EditError) -> [String] {
        var spellings: [String] = []
        for item in items {
            spellings.append(try item.spelling(reusing: existing, inFlow: inFlow))
        }
        return spellings
    }

    /// The edits that turn a list written one item per line into the given items.
    ///
    /// Items at the start and at the end that stay the same keep their lines untouched. Between
    /// them, lines are rewritten in place, then added after or removed from the changed stretch,
    /// so comment and blank lines inside the list stay where they are.
    private func blockListEdits(
        from current: [FrontmatterScalar],
        to items: [FrontmatterLiteral],
        layout: FieldLayout
    ) throws(EditError) -> [LineEdit] {
        let shorter = min(current.count, items.count)
        var prefix = 0
        while prefix < shorter, items[prefix].matches(current[prefix]) {
            prefix += 1
        }
        var suffix = 0
        while suffix < shorter - prefix, items[items.count - 1 - suffix].matches(current[current.count - 1 - suffix]) {
            suffix += 1
        }
        let changedParts = Array(layout.children[prefix..<(current.count - suffix)])
        let changedItems = Array(items[prefix..<(items.count - suffix)])
        let newSpellings = try spellings(of: changedItems, reusing: current, inFlow: false)

        var edits: [LineEdit] = []
        for (part, spelling) in zip(changedParts, newSpellings) {
            edits.append(.replacing(line: part.line, with: part.rebuilt(with: spelling)))
        }
        if newSpellings.count > changedParts.count {
            let added = newSpellings[changedParts.count...].map { layout.childIndent + "- " + $0 }
            let position: Int
            if let lastChanged = changedParts.last {
                position = lastChanged.line + 1
            } else if prefix > 0 {
                position = layout.children[prefix - 1].line + 1
            } else {
                position = layout.children[0].line
            }
            edits.append(.inserting(added, at: position))
        }
        for part in changedParts.dropFirst(newSpellings.count) {
            edits.append(.removing(line: part.line))
        }
        return edits
    }
}
