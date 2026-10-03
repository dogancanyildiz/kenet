/// A region of the merged body with where it came from.
struct MergedRegion: Sendable {
    let key: [UInt8]?
    let kind: DaySectionKind?
    /// The index of the region in the older version, when the older version has it.
    let olderIndex: Int?
    var entries: [RegionEntry]

    var lines: [RawLine] { entries.flatMap(\.lines) }
}

/// The merged body, with the structure the merge built so that it can be checked after reading
/// the result back.
struct MergedBody: Sendable {
    let lines: [RawLine]
    /// The line contents of every region in order, the one before the first heading first.
    let regions: [[[UInt8]]]
    /// The contents of every block in order.
    let blocks: [[[UInt8]]]

    init(_ regions: [MergedRegion]) {
        lines = regions.flatMap(\.lines)
        self.regions = regions.map { $0.lines.map(\.content) }
        blocks = regions.flatMap { $0.entries.filter(\.isBlock).map { $0.lines.map(\.content) } }
    }
}

/// Merges the bodies of two versions region by region.
enum BodyMerge {
    static func merge(
        newer: MergeBody, older: MergeBody, hasFrontmatter: Bool, preserved: inout Preservation
    ) -> MergedBody {
        let pairs = RegionPair.pairs(newer: newer, older: older)
        let matching = BlockMatching(newer: newer, older: older, regionPairs: pairs, preserved: &preserved)

        var merged: [MergedRegion] = []
        for pair in pairs {
            guard let newerIndex = pair.newer else { continue }
            let region = newer.regions[newerIndex]
            let entries: [RegionEntry]
            if let olderIndex = pair.older {
                entries = RegionMerge.merge(
                    newer: newer, newerRegion: newerIndex, older: older, olderRegion: olderIndex,
                    matching: matching, preserved: &preserved)
            } else {
                entries = RegionMerge.entries(of: newerIndex, in: newer, dropping: [])
            }
            merged.append(MergedRegion(key: region.key, kind: region.kind, olderIndex: pair.older, entries: entries))
        }

        let newLine = RawLine(content: [], ending: newer.document.lineEndingForNewLines)
        let onlyOlder = Set(pairs.compactMap { $0.newer == nil ? $0.older : nil })
        for (olderIndex, region) in older.regions.enumerated() where onlyOlder.contains(olderIndex) {
            var entries = RegionMerge.entries(of: olderIndex, in: older, dropping: matching.droppedOlder)
            let position = insertionPosition(for: region, olderIndex: olderIndex, in: merged)
            // A blank line separates the region from what precedes it, the frontmatter included,
            // and from what follows it; nothing is added when the file would otherwise start here.
            // The blank before the heading belongs to the region that precedes it when read back.
            if position > 0 {
                let previous = merged[..<position].lazy.flatMap(\.lines).last
                if previous.map({ !MergeBody.isBlank($0.content) }) ?? hasFrontmatter {
                    merged[position - 1].entries.append(.plain(newLine))
                }
            }
            if let last = entries.last?.lines.last, !MergeBody.isBlank(last.content),
                merged[position...].contains(where: { !$0.entries.isEmpty })
            {
                entries.append(.plain(newLine))
            }
            merged.insert(
                MergedRegion(key: region.key, kind: region.kind, olderIndex: olderIndex, entries: entries), at: position
            )
        }
        return MergedBody(merged)
    }

    /// Where a region only the older version has goes: a recognized section before the first
    /// later section in creation order, any other region after the nearest region before it in
    /// the older version that the merged body already has. Regions with the same key keep the
    /// order they have in the older version, because that order pairs them when merging again.
    private static func insertionPosition(for region: MergeRegion, olderIndex: Int, in merged: [MergedRegion]) -> Int {
        var position = merged.count
        if let kind = region.kind {
            let following = DaySectionKind.allCases.drop { $0 != kind }.dropFirst()
            position = merged.firstIndex { $0.kind.map(following.contains) == true } ?? merged.count
        } else {
            for candidate in stride(from: olderIndex - 1, through: 0, by: -1) {
                if let index = merged.firstIndex(where: { $0.olderIndex == candidate }) {
                    position = index + 1
                    break
                }
            }
        }
        let sameKey = merged.indices.filter { merged[$0].key == region.key && merged[$0].olderIndex != nil }
        let lower = sameKey.last { merged[$0].olderIndex! < olderIndex }.map { $0 + 1 } ?? 0
        let upper = sameKey.first { merged[$0].olderIndex! > olderIndex } ?? merged.count
        return min(max(position, lower), upper)
    }
}
