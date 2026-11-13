import EntityRecognition
import VaultFormat
import VaultIndex

/// Entity usage (incoming link count, last source date, shared diary days) counted from the
/// files already in the read model. It gives the same rows as `VaultIndex.entityUsage()` without a
/// database read: the self-join that query runs grows faster than the vault and held the index
/// connection for the whole publish.
enum EntityUsageCalculator {
    /// One indexed file: its row, its entity (if any) and its links in source order.
    typealias Source = (file: IndexSnapshot.File, entity: IndexedEntity?, links: [IndexedLink])

    /// Rows for every non-goal entity, ordered by path as the index orders them (byte order).
    static func usage(of sources: some Sequence<Source>) -> [EntityUsage] {
        var ids: [String: Int] = [:]
        var paths: [String] = []
        var linked: [(file: IndexSnapshot.File, links: [IndexedLink])] = []
        for source in sources {
            if let entity = source.entity, entity.kind != "goal", ids[entity.file] == nil {
                ids[entity.file] = paths.count
                paths.append(entity.file)
            }
            if !source.links.isEmpty { linked.append((source.file, source.links)) }
        }
        var totals = [Int](repeating: 0, count: paths.count)
        var lastDates = [String?](repeating: nil, count: paths.count)
        // Distinct entities per diary date; two day files with one date count as one day.
        var days: [String: Set<Int>] = [:]
        for (file, links) in linked {
            let dayDate = file.kind == "day" ? file.date : nil
            for link in links {
                guard let target = link.resolvedFile, let id = ids[target] else { continue }
                totals[id] += 1
                if let date = file.date, lastDates[id].map({ $0.utf8.lexicographicallyPrecedes(date.utf8) }) ?? true {
                    lastDates[id] = date
                }
                if let dayDate { days[dayDate, default: []].insert(id) }
            }
        }
        // Shared-day counts per ordered pair: a flat table while it stays small, else per-entity maps.
        let count = paths.count
        var table = count <= 1024 ? [Int32](repeating: 0, count: count * count) : []
        var together = table.isEmpty ? [[Int: Int]](repeating: [:], count: count) : []
        for entities in days.values where entities.count > 1 {
            let members = Array(entities)
            for first in members {
                for second in members where second != first {
                    if table.isEmpty {
                        together[first][second, default: 0] += 1
                    } else {
                        table[first * count + second] += 1
                    }
                }
            }
        }
        return paths.indices
            .sorted { paths[$0].utf8.lexicographicallyPrecedes(paths[$1].utf8) }
            .map { id in
                var cooccurrences: [String: Int] = [:]
                if table.isEmpty {
                    for (other, shared) in together[id] { cooccurrences[paths[other]] = shared }
                } else {
                    let row = id * count
                    for other in 0..<count where table[row + other] > 0 {
                        cooccurrences[paths[other]] = Int(table[row + other])
                    }
                }
                return EntityUsage(
                    file: paths[id], totalCount: totals[id], lastDate: lastDates[id].flatMap { CalendarDate($0) },
                    cooccurrences: cooccurrences)
            }
    }
}
