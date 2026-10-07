/// Byte-sensitive semantic snapshot; Swift String equality alone normalizes Unicode.
struct WrittenBlock: Equatable, Sendable {
    var block: LineBlock
    var time: EventTime?
    var status: String?
    var task: TaskFieldValues? = nil

    static func == (lhs: Self, rhs: Self) -> Bool {
        lhs.block.lineRange == rhs.block.lineRange
            && Array(lhs.block.text.utf8) == Array(rhs.block.text.utf8)
            && lhs.block.id.map { Array($0.utf8) } == rhs.block.id.map { Array($0.utf8) }
            && lhs.time == rhs.time && lhs.status == rhs.status
            && lhs.task == rhs.task
            && lhs.task.map { Array($0.text.utf8) } == rhs.task.map { Array($0.text.utf8) }
            && lhs.task?.project.map { Array($0.utf8) } == rhs.task?.project.map { Array($0.utf8) }
    }

    static func all(_ document: RawDocument) -> [Self] {
        let body = document.bodyLines
        return
            (body.events.map { Self(block: $0.block, time: $0.time, status: nil) }
            + body.tasks.map { Self(block: $0.block, time: nil, status: $0.rawStatus, task: $0.fields.values) })
            .sorted { $0.block.line < $1.block.line }
    }
}

extension RawDocument {
    /// Verifies semantics, physical ownership and untouched bytes after a fresh read.
    func validatingLines(
        _ edited: RawDocument, origins: [Int?], target: LineBlock?, desired: WrittenBlock?,
        changedLine: Int? = nil, addedSection: DaySectionKind? = nil
    ) throws(EditError) -> RawDocument {
        let result = RawDocument(bytes: edited.serialized())
        guard result.lines.count == origins.count else { throw .contentNotRepresentable }
        var positions: [Int: Int] = [:]
        for (index, source) in origins.enumerated() {
            if let source { positions[source] = index }
        }
        guard result.hasByteOrderMark == hasByteOrderMark,
            result.frontmatter == frontmatter, result.frontmatterLineRange == frontmatterLineRange
        else { throw .sectionNotWritable }
        let beforeSections = daySections.sections
        let afterSections = result.daySections.sections.filter {
            addedSection == nil || $0.kind != addedSection
        }
        guard beforeSections.count == afterSections.count else { throw .sectionNotWritable }
        for (before, after) in zip(beforeSections, afterSections) {
            guard before.kind == after.kind, before.level == after.level,
                positions[before.headingLine] == after.headingLine
            else { throw .sectionNotWritable }
            for source in before.lineRange {
                if let position = positions[source], !after.lineRange.contains(position) {
                    throw .sectionNotWritable
                }
            }
        }
        for (index, source) in origins.enumerated() {
            guard let source, source != changedLine else { continue }
            guard result.lines[index].content == lines[source].content else { throw .contentNotRepresentable }
            // Moving a block gives its lines new endings; appending may terminate the old EOF.
            let moved = target?.lineRange.contains(source) == true && positions[target!.line] != target!.line
            if !moved, let ending = lines[source].ending, result.lines[index].ending != ending {
                throw .contentNotRepresentable
            }
        }
        let oldFence = SectionParser.scan(lines, startingAt: frontmatterLineRange?.upperBound ?? 0).fencedBoundaries
        let newFence = SectionParser.scan(result.lines, startingAt: result.frontmatterLineRange?.upperBound ?? 0)
            .fencedBoundaries
        for (position, source) in origins.enumerated() {
            guard let source, source != changedLine else { continue }
            guard oldFence.contains(source) == newFence.contains(position) else { throw .contentNotRepresentable }
        }
        guard oldFence.contains(lines.count) == newFence.contains(result.lines.count) else {
            throw .contentNotRepresentable
        }
        var expected: [WrittenBlock] = []
        for var original in WrittenBlock.all(self) {
            if original.block == target { continue }
            var mapped = original.block.lineRange.compactMap { positions[$0] }
            if mapped.isEmpty { continue }
            let removed = original.block.lineRange.filter { positions[$0] == nil }
            let shortenedParent =
                desired == nil
                && target.map {
                    original.block.line < $0.line && original.block.lineRange.upperBound >= $0.lineRange.upperBound
                        && removed.allSatisfy($0.lineRange.contains)
                } == true
            if shortenedParent {
                // Removed children can leave retained blank lines outside the parent's new extent.
                while mapped.count > 1, result.lines[mapped.last!].content.allSatisfy(Syntax.isBlank) {
                    mapped.removeLast()
                }
            }
            guard mapped.count == original.block.lineRange.count || shortenedParent,
                mapped == Array(mapped[0]..<(mapped[0] + mapped.count))
            else { throw .contentNotRepresentable }
            original.block = LineBlock(
                lineRange: mapped[0]..<(mapped[0] + mapped.count), id: original.block.id, text: original.block.text)
            expected.append(original)
        }
        if let desired { expected.append(desired) }
        expected.sort { $0.block.line < $1.block.line }
        guard expected == WrittenBlock.all(result) else { throw .contentNotRepresentable }
        return result
    }

    func requireTarget(_ target: LineBlock) throws(EditError) -> WrittenBlock {
        guard !isReadOnly else { throw .readOnlyDocument }
        guard
            let found = WrittenBlock.all(self).first(where: {
                $0.block.lineRange == target.lineRange
                    && $0.block.id.map { Array($0.utf8) } == target.id.map { Array($0.utf8) }
                    && Array($0.block.text.utf8) == Array(target.text.utf8)
                    && $0.block.kind == target.kind && $0.block.firstLineContent == target.firstLineContent
            })
        else { throw .targetNotFound }
        return found
    }
}
