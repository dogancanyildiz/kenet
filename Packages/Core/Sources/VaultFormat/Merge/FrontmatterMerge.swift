/// Merges the frontmatter blocks of two versions.
enum FrontmatterMerge {
    static let goalsKey = "goals"

    /// The lines of the merged frontmatter block, or no lines when the merged file has none.
    static func merge(newer: RawDocument, older: RawDocument, preserved: inout Preservation) -> [RawLine] {
        let newerBlock = newer.frontmatterLineRange.map { Array(newer.lines[$0]) } ?? []
        let olderBlock = older.frontmatterLineRange.map { Array(older.lines[$0]) } ?? []
        let newerFields: [FrontmatterField]
        let olderFields: [FrontmatterField]
        switch (newer.frontmatter, older.frontmatter) {
        case (.unreadable, _), (_, .unreadable):
            if newerBlock.map(\.content) != olderBlock.map(\.content) { preserved.keep(.older) }
            return newerBlock
        case (_, .absent):
            return newerBlock
        case (.parsed(let a), .parsed(let b)):
            (newerFields, olderFields) = (a.fields, b.fields)
        case (.absent, .parsed(let b)):
            (newerFields, olderFields) = ([], b.fields)
        }

        var plan = Plan()
        for olderField in olderFields {
            guard let newerField = newerFields.first(where: { Syntax.exactlyEqual($0.key, olderField.key) }) else {
                plan.appendedFields.append(olderField)
                continue
            }
            if Syntax.exactlyEqual(olderField.key, goalsKey), case .mapping(let newerEntries) = newerField.value,
                case .mapping(let olderEntries) = olderField.value
            {
                plan.goals = newerField
                for olderEntry in olderEntries {
                    guard let newerEntry = newerEntries.first(where: { Syntax.exactlyEqual($0.key, olderEntry.key) })
                    else {
                        plan.appendedEntries.append(olderEntry)
                        continue
                    }
                    if FrontmatterValueEquality.same(newerEntry.value, olderEntry.value) { continue }
                    switch FrontmatterValueEquality.progressed(newer: newerEntry.value, older: olderEntry.value) {
                    case .older: plan.progressedEntries.append(olderEntry)
                    case .newer: break
                    case nil: preserved.keep(.older)
                    }
                }
            } else if !FrontmatterValueEquality.same(newerField.value, olderField.value) {
                preserved.keep(.older)
            }
        }

        guard let merged = apply(plan, to: newer, older: older),
            isComplete(merged, newerFields: newerFields, plan: plan)
        else {
            preserved.keep(.older)
            return newerBlock
        }
        // Comments are not values: a comment of the older version that the merged block lacks is content.
        if !FrontmatterLineSurvival.linesSurvive(of: older, in: merged) { preserved.keep(.older) }
        return merged.frontmatterLineRange.map { Array(merged.lines[$0]) } ?? []
    }

    /// What the older version adds to the newer version's block.
    private struct Plan {
        var goals: FrontmatterField?
        var progressedEntries: [FrontmatterEntry] = []
        var appendedEntries: [FrontmatterEntry] = []
        var appendedFields: [FrontmatterField] = []
    }

    /// The newer document with the plan applied to its frontmatter, or `nil` when an edit is refused.
    private static func apply(_ plan: Plan, to newer: RawDocument, older: RawDocument) -> RawDocument? {
        do {
            var document = newer
            for entry in plan.progressedEntries {
                let value: FrontmatterLiteral = entry.value.kind == .number ? .number(entry.value.raw) : .boolean(true)
                document = try document.settingFrontmatterEntry(value, forKey: entry.key, inMapping: goalsKey)
            }
            if let goals = plan.goals, !plan.appendedEntries.isEmpty {
                let indent = goals.layout.childIndent
                let lines = plan.appendedEntries.map { entry in
                    indent + Syntax.string(older.lines[entry.line].content.drop(while: Syntax.isBlank))
                }
                let end = goals.lineRange.upperBound
                document = try document.replacingLines(in: end..<end, with: lines)
            }
            if !plan.appendedFields.isEmpty {
                let lines = plan.appendedFields.flatMap { field in
                    field.lineRange.map { Syntax.string(older.lines[$0].content) }
                }
                if case .parsed(let frontmatter) = document.frontmatter {
                    let closing = frontmatter.lineRange.upperBound - 1
                    document = try document.replacingLines(in: closing..<closing, with: lines)
                } else {
                    document = try document.replacingLines(in: 0..<0, with: FrontmatterWriter.block(lines))
                }
            }
            return document
        } catch {
            return nil
        }
    }

    /// Whether the merged block reads back with every field the two versions contribute.
    private static func isComplete(_ document: RawDocument, newerFields: [FrontmatterField], plan: Plan) -> Bool {
        guard case .parsed(let frontmatter) = document.frontmatter else {
            return newerFields.isEmpty && plan.appendedFields.isEmpty
        }
        for field in newerFields where !Syntax.exactlyEqual(field.key, goalsKey) || plan.goals == nil {
            guard let merged = frontmatter.field(named: field.key),
                FrontmatterValueEquality.same(merged.value, field.value)
            else { return false }
        }
        for field in plan.appendedFields {
            guard let merged = frontmatter.field(named: field.key),
                FrontmatterValueEquality.same(merged.value, field.value)
            else { return false }
        }
        if let goals = plan.goals {
            guard case .mapping(let entries) = frontmatter.field(named: goals.key)?.value,
                case .mapping(let newerEntries) = goals.value
            else { return false }
            let fromOlder = plan.progressedEntries + plan.appendedEntries
            let expected =
                newerEntries.filter { entry in !fromOlder.contains { Syntax.exactlyEqual($0.key, entry.key) } }
                + fromOlder
            guard entries.count == expected.count else { return false }
            for entry in expected {
                guard let merged = entries.first(where: { Syntax.exactlyEqual($0.key, entry.key) }),
                    FrontmatterValueEquality.same(merged.value, entry.value)
                else { return false }
            }
        }
        return true
    }
}
