/// A piece of a merged region: one plain line, or a whole block.
struct RegionEntry: Sendable {
    let lines: [RawLine]
    /// The clock time when the entry is an event; used to place events added from the other version.
    let time: EventTime?
    let isBlock: Bool

    var isBlank: Bool { !isBlock && lines.allSatisfy { MergeBody.isBlank($0.content) } }

    static func plain(_ line: RawLine) -> RegionEntry { RegionEntry(lines: [line], time: nil, isBlock: false) }

    static func block(_ block: MergeBlock, in body: MergeBody) -> RegionEntry {
        RegionEntry(lines: block.range.map { body.document.lines[$0] }, time: block.time, isBlock: true)
    }
}

/// Merges one region that both versions have.
enum RegionMerge {
    static func merge(
        newer: MergeBody, newerRegion: Int, older: MergeBody, olderRegion: Int,
        matching: BlockMatching, preserved: inout Preservation
    ) -> [RegionEntry] {
        let newerText = freeText(of: newer, region: newerRegion)
        let olderText = freeText(of: older, region: olderRegion)
        let layout: MergeSide
        if isSubsequence(olderText, of: newerText) {
            layout = .newer
        } else if isSubsequence(newerText, of: olderText) {
            layout = .older
        } else {
            layout = .newer
            preserved.keep(.older)
        }

        let (base, other) = layout == .newer ? (newer, older) : (older, newer)
        let baseRegion = layout == .newer ? newerRegion : olderRegion
        let partnerOf = layout == .newer ? matching.olderPartner : matching.newerPartner
        var entries = entries(of: baseRegion, in: base) { blockIndex in
            if layout == .older, matching.droppedOlder.contains(blockIndex) { return nil }
            let block = base.blocks[blockIndex]
            guard let partner = partnerOf[blockIndex] else { return .block(block, in: base) }
            let newerBlock = layout == .newer ? block : other.blocks[partner]
            let olderBlock = layout == .newer ? other.blocks[partner] : block
            let decision = BlockMatching.resolve(newer: newerBlock, older: olderBlock)
            if let loser = decision.loser { preserved.keep(loser) }
            return decision.winner == layout ? .block(block, in: base) : .block(other.blocks[partner], in: other)
        }

        let otherRegion = layout == .newer ? olderRegion : newerRegion
        let otherPartnerOf = layout == .newer ? matching.newerPartner : matching.olderPartner
        for blockIndex in other.regions[otherRegion].blocks where otherPartnerOf[blockIndex] == nil {
            if layout == .newer, matching.droppedOlder.contains(blockIndex) { continue }
            insert(.block(other.blocks[blockIndex], in: other), into: &entries)
        }
        // The newer version's layout separates regions; when the older version's layout is used
        // for this one, the blank line the newer version ended it with is kept.
        if layout == .older, let last = newer.regions[newerRegion].range.last,
            MergeBody.isBlank(newer.document.lines[last].content), entries.last?.isBlank == false
        {
            entries.append(.plain(newer.document.lines[last]))
        }
        return entries
    }

    /// The region's lines as entries: a plain entry for every line outside a block, and for each
    /// block whatever `entry` decides, which may be nothing when the block is left out.
    static func entries(of region: Int, in body: MergeBody, block entry: (Int) -> RegionEntry?) -> [RegionEntry] {
        var entries: [RegionEntry] = []
        var line = body.regions[region].range.lowerBound
        var blocks = body.regions[region].blocks.makeIterator()
        var upcoming = blocks.next()
        while line < body.regions[region].range.upperBound {
            guard let blockIndex = upcoming, body.blocks[blockIndex].range.lowerBound == line else {
                entries.append(.plain(body.document.lines[line]))
                line += 1
                continue
            }
            upcoming = blocks.next()
            line = body.blocks[blockIndex].range.upperBound
            if let made = entry(blockIndex) { entries.append(made) }
        }
        return entries
    }

    /// The region's lines as entries with every block but the dropped ones.
    static func entries(of region: Int, in body: MergeBody, dropping dropped: Set<Int>) -> [RegionEntry] {
        entries(of: region, in: body) { dropped.contains($0) ? nil : .block(body.blocks[$0], in: body) }
    }

    /// The content of every nonblank line of the region that is neither its heading nor part of a block.
    static func freeText(of body: MergeBody, region index: Int) -> [[UInt8]] {
        let region = body.regions[index]
        var blockLines: Set<Int> = []
        for blockIndex in region.blocks {
            blockLines.formUnion(body.blocks[blockIndex].range)
        }
        var text: [[UInt8]] = []
        for line in region.range where !blockLines.contains(line) {
            if line == region.range.lowerBound, region.key != nil { continue }
            let content = body.document.lines[line].content
            if !MergeBody.isBlank(content) { text.append(content) }
        }
        return text
    }

    /// Whether every element of `part` occurs in `whole` in the same order.
    static func isSubsequence(_ part: [[UInt8]], of whole: [[UInt8]]) -> Bool {
        var position = 0
        for element in part {
            while position < whole.count, whole[position] != element { position += 1 }
            guard position < whole.count else { return false }
            position += 1
        }
        return true
    }

    /// Adds a block the other version has: a timed event before the first event with a later
    /// time, anything else after the last nonblank entry.
    private static func insert(_ entry: RegionEntry, into entries: inout [RegionEntry]) {
        if let time = entry.time {
            let minutes = time.hour * 60 + time.minute
            if let later = entries.firstIndex(where: { existing in
                existing.time.map { $0.hour * 60 + $0.minute > minutes } == true
            }) {
                entries.insert(entry, at: later)
                return
            }
        }
        let last = entries.lastIndex { !$0.isBlank } ?? -1
        entries.insert(entry, at: last + 1)
    }
}
