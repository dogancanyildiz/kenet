/// The last guard of the merge: reads the result back and checks that nothing of a version that
/// is not kept as a conflict copy is missing from it.
///
/// The check is deliberately simple and independent of how the merge was computed: blocks are
/// looked up by content, free text region by region and line by line with counts, frontmatter
/// field by field and line by line. Its only purpose is to keep a mistake in the merge from
/// becoming lost content.
enum LossCheck {
    static func passes(
        result: RawDocument, frontmatterLineCount: Int, built: MergedBody, newer: RawDocument, older: RawDocument,
        preserved: Preservation
    ) -> Bool {
        let merged = MergeBody(result)
        guard merged.start == frontmatterLineCount, hasBuiltStructure(merged, built: built) else { return false }
        for (isPreserved, document) in [(preserved.newer, newer), (preserved.older, older)] where !isPreserved {
            let body = MergeBody(document)
            guard blocksSurvive(body, in: merged), freeTextSurvives(body, in: merged),
                frontmatterSurvives(document, in: result)
            else { return false }
        }
        return true
    }

    /// Reading the result finds exactly the regions and blocks the merge put together. A line
    /// from one version can change how lines from the other are read, for example a code fence
    /// that is not closed; then the merged file would not say what the merge decided.
    private static func hasBuiltStructure(_ merged: MergeBody, built: MergedBody) -> Bool {
        let regions = merged.regions.map { region in region.range.map { merged.document.lines[$0].content } }
        return regions == built.regions && merged.blocks.map(\.contents) == built.blocks
    }

    /// Every block of the version is in the result, either as it is or replaced by a task the
    /// rules allow in its place (`BlockMatching.isAllowedToReplace`).
    private static func blocksSurvive(_ body: MergeBody, in merged: MergeBody) -> Bool {
        var byContents: [[[UInt8]]: [Int]] = [:]
        for (index, block) in merged.blocks.enumerated() {
            byContents[block.contents, default: []].append(index)
        }
        var unmatched: [MergeBlock] = []
        for block in body.blocks {
            if var candidates = byContents[block.contents], !candidates.isEmpty {
                candidates.removeLast()
                byContents[block.contents] = candidates
            } else {
                unmatched.append(block)
            }
        }
        var byNormalized: [[[UInt8]]: [Int]] = [:]
        for index in byContents.values.joined() where merged.blocks[index].isTask {
            byNormalized[merged.blocks[index].normalized, default: []].append(index)
        }
        for block in unmatched {
            guard var candidates = byNormalized[block.normalized],
                let position = candidates.firstIndex(where: {
                    BlockMatching.isAllowedToReplace(merged.blocks[$0], block)
                })
            else { return false }
            candidates.remove(at: position)
            byNormalized[block.normalized] = candidates
        }
        return true
    }

    /// Every nonblank free text line of every region of the version is in the free text of the
    /// result's region with the same key, as many times as the version has it.
    private static func freeTextSurvives(_ body: MergeBody, in merged: MergeBody) -> Bool {
        for pair in RegionPair.pairs(newer: merged, older: body) {
            guard let versionRegion = pair.older else { continue }
            guard let mergedRegion = pair.newer else { return false }
            var available: [[UInt8]: Int] = [:]
            for line in RegionMerge.freeText(of: merged, region: mergedRegion) {
                available[line, default: 0] += 1
            }
            for line in RegionMerge.freeText(of: body, region: versionRegion) {
                guard let count = available[line], count > 0 else { return false }
                available[line] = count - 1
            }
        }
        return true
    }

    /// Every frontmatter field of the version is in the result with the same value, or, for a
    /// goal entry, with a value at least as far along; and every line of its block survives.
    private static func frontmatterSurvives(_ document: RawDocument, in result: RawDocument) -> Bool {
        switch document.frontmatter {
        case .absent:
            return true
        case .unreadable:
            let block = document.frontmatterLineRange.map { document.lines[$0].map(\.content) }
            return block == result.frontmatterLineRange.map { result.lines[$0].map(\.content) }
        case .parsed(let frontmatter):
            guard case .parsed(let merged) = result.frontmatter else {
                return frontmatter.fields.isEmpty && FrontmatterLineSurvival.linesSurvive(of: document, in: result)
            }
            for field in frontmatter.fields {
                guard let counterpart = merged.field(named: field.key) else { return false }
                if FrontmatterValueEquality.same(counterpart.value, field.value) { continue }
                guard Syntax.exactlyEqual(field.key, FrontmatterMerge.goalsKey),
                    case .mapping(let entries) = field.value, case .mapping(let mergedEntries) = counterpart.value
                else { return false }
                for entry in entries {
                    guard let found = mergedEntries.first(where: { Syntax.exactlyEqual($0.key, entry.key) }),
                        FrontmatterValueEquality.same(found.value, entry.value)
                            || FrontmatterValueEquality.progressed(newer: found.value, older: entry.value) == .newer
                    else { return false }
                }
            }
            return FrontmatterLineSurvival.linesSurvive(of: document, in: result)
        }
    }
}
