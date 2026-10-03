/// How the blocks of the two versions correspond to each other.
struct BlockMatching: Sendable {
    /// For each block of the newer version, the index of its partner in the older version.
    var olderPartner: [Int: Int] = [:]
    /// For each block of the older version, the index of its partner in the newer version.
    var newerPartner: [Int: Int] = [:]
    /// Blocks of the older version that are left out because the newer version has their
    /// identifier in another region or with another kind.
    var droppedOlder: Set<Int> = []

    /// Matches the blocks of two versions: first by identifier across the whole body, then,
    /// inside each pair of regions, by content.
    init(newer: MergeBody, older: MergeBody, regionPairs: [RegionPair], preserved: inout Preservation) {
        let olderRegionOf = Dictionary(
            uniqueKeysWithValues: regionPairs.compactMap { pair in pair.newer.map { ($0, pair.older) } })

        let newerIDs = Self.uniqueIDs(newer)
        let olderIDs = Self.uniqueIDs(older)
        for (id, newerIndex) in newerIDs {
            guard let olderIndex = olderIDs[id] else { continue }
            let newerBlock = newer.blocks[newerIndex]
            let olderBlock = older.blocks[olderIndex]
            if olderRegionOf[newerBlock.region] == olderBlock.region, newerBlock.kind == olderBlock.kind {
                pair(newerIndex, olderIndex)
            } else {
                droppedOlder.insert(olderIndex)
                preserved.keep(.older)
            }
        }

        for pair in regionPairs {
            guard let newerRegion = pair.newer, let olderRegion = pair.older else { continue }
            var olderByContent: [[[UInt8]]: [Int]] = [:]
            for index in older.regions[olderRegion].blocks
            where newerPartner[index] == nil && !droppedOlder.contains(index) {
                olderByContent[older.blocks[index].contents, default: []].append(index)
            }
            for index in newer.regions[newerRegion].blocks where olderPartner[index] == nil {
                guard var candidates = olderByContent[newer.blocks[index].contents], !candidates.isEmpty else {
                    continue
                }
                self.pair(index, candidates.removeFirst())
                olderByContent[newer.blocks[index].contents] = candidates
            }
        }
    }

    private mutating func pair(_ newerIndex: Int, _ olderIndex: Int) {
        olderPartner[newerIndex] = olderIndex
        newerPartner[olderIndex] = newerIndex
    }

    /// The identifiers that occur exactly once in the body, with the block that carries them.
    /// An identifier that occurs more than once in either version is not used for matching.
    private static func uniqueIDs(_ body: MergeBody) -> [String: Int] {
        var counts: [String: Int] = [:]
        var first: [String: Int] = [:]
        for (index, block) in body.blocks.enumerated() {
            guard let id = block.id else { continue }
            counts[id, default: 0] += 1
            if first[id] == nil { first[id] = index }
        }
        return first.filter { counts[$0.key] == 1 }
    }

    /// Decides which of two matched blocks the merged file holds and which version, if any,
    /// loses content by it.
    static func resolve(newer: MergeBlock, older: MergeBlock) -> (winner: MergeSide, loser: MergeSide?) {
        if newer.contents == older.contents { return (.newer, nil) }
        var winner = MergeSide.newer
        if let newerClosed = newer.isClosed, let olderClosed = older.isClosed, newerClosed != olderClosed {
            winner = newerClosed ? .newer : .older
        }
        let lost = winner == .newer ? older : newer
        let kept = winner == .newer ? newer : older
        return (winner, isAllowedToReplace(kept, lost) ? nil : winner.other)
    }

    /// Whether a task may stand in for another one without a conflict copy: a closed task for an
    /// open one with the same normalized text, or a closed task for a closed one with the same
    /// checkbox character that differs in its completion date only.
    static func isAllowedToReplace(_ kept: MergeBlock, _ lost: MergeBlock) -> Bool {
        guard let keptClosed = kept.isClosed, let lostClosed = lost.isClosed, keptClosed,
            kept.normalized == lost.normalized
        else { return false }
        return !lostClosed || kept.status == lost.status
    }
}

/// A region of the newer version and the region of the older version it corresponds to.
/// Either may be missing when only one version has the region.
struct RegionPair: Sendable {
    let newer: Int?
    let older: Int?

    /// Pairs the regions of two versions by key. The region before the first heading always
    /// pairs; a key that occurs several times pairs in order.
    static func pairs(newer: MergeBody, older: MergeBody) -> [RegionPair] {
        var olderByKey: [[UInt8]: [Int]] = [:]
        for (index, region) in older.regions.enumerated().dropFirst() {
            olderByKey[region.key!, default: []].append(index)
        }
        var pairs = [RegionPair(newer: 0, older: 0)]
        var pairedOlder: Set<Int> = [0]
        for (index, region) in newer.regions.enumerated().dropFirst() {
            if var candidates = olderByKey[region.key!], !candidates.isEmpty {
                let partner = candidates.removeFirst()
                olderByKey[region.key!] = candidates
                pairedOlder.insert(partner)
                pairs.append(RegionPair(newer: index, older: partner))
            } else {
                pairs.append(RegionPair(newer: index, older: nil))
            }
        }
        for index in older.regions.indices where !pairedOlder.contains(index) {
            pairs.append(RegionPair(newer: nil, older: index))
        }
        return pairs
    }
}
