import Foundation
import GoalTracking
import VaultFormat
import VaultIndex

extension VaultReadModel {
    /// Whether fragment deltas require rebuilding every derived screen field.
    func requiresFullRederive(
        before: [String: VaultFileFragment], touched: Set<String>, removed: Set<String>
    ) -> Bool {
        if touched.count + removed.count > 32 { return true }
        for path in touched.union(removed) {
            let old = before[path]
            let new = fragments[path]
            if old?.entity != nil || new?.entity != nil { return true }
            if (old?.file.kind ?? new?.file.kind) == "goal" { return true }
            if !(old?.goalLogs.isEmpty ?? true) || !(new?.goalLogs.isEmpty ?? true) {
                // Goal values change statuses; cheap enough to still patch, but keys may appear.
            }
        }
        return false
    }

    /// Patches derived screen fields using before/after fragments for a small content delta.
    mutating func patchDerived(
        before: [String: VaultFileFragment], touched: Set<String>, removed: Set<String>,
        today: CalendarDate
    ) {
        goalLogStart = today.addingDays(-399) ?? today
        let goalLogEnd = today.addingDays(6) ?? today

        for path in removed.union(touched) {
            if let old = before[path] {
                subtractContributions(of: old)
            }
        }
        for path in touched {
            if let fragment = fragments[path] {
                addContributions(of: fragment)
            }
        }

        tasks.sort { left, right in
            if left.file != right.file { return left.file < right.file }
            return left.sourceLine < right.sourceLine
        }

        let goalTouched = removed.union(touched).contains { path in
            !(before[path]?.goalLogs.isEmpty ?? true)
                || !(fragments[path]?.goalLogs.isEmpty ?? true)
        }
        if goalTouched {
            // Sparse; rebuild in path order so arrays match a full snapshot derive.
            let indexedLogs = fragments.keys.sorted().flatMap { fragments[$0]!.goalLogs }
            // Same source as `rederive`: entity goal keys (including invalid definitions).
            reservedGoalKeys = Set(
                fragments.values.compactMap(\.entity?.goalKey) + indexedLogs.map(\.key))
            let allLogs = Dictionary(grouping: indexedLogs, by: \.key).mapValues {
                $0.compactMap(GoalLog.init(indexed:))
            }
            goalLogs = allLogs.mapValues { $0.filter { $0.day >= goalLogStart && $0.day <= goalLogEnd } }
            for goal in goals {
                goalStatuses[goal.key] = GoalProgress.compute(
                    definition: goal, logs: allLogs[goal.key] ?? [], today: today)
            }
        }
    }

    private mutating func subtractContributions(of fragment: VaultFileFragment) {
        let path = fragment.file.path
        tasks.removeAll { $0.file == path }
        adjustIncoming(links: fragment.links, delta: -1)
        adjustCounts(of: fragment, delta: -1)
    }

    private mutating func addContributions(of fragment: VaultFileFragment) {
        let links = fragment.links
        tasks += fragment.blocks.filter { $0.kind == "task" }.map { TaskRow(row: $0, links: links) }
        adjustIncoming(links: links, delta: 1)
        adjustCounts(of: fragment, delta: 1)
    }

    private mutating func adjustCounts(of fragment: VaultFileFragment, delta: Int) {
        counts.filesByKind[fragment.file.kind, default: 0] += delta
        if counts.filesByKind[fragment.file.kind] == 0 { counts.filesByKind[fragment.file.kind] = nil }
        if fragment.entity != nil { counts.entities += delta }
        for block in fragment.blocks {
            if block.kind == "event" { counts.events += delta }
            if block.kind == "task" { counts.tasks += delta }
        }
        counts.links += delta * fragment.links.count
        let unresolved = fragment.links.filter { $0.resolvedFile == nil }.count
        counts.unresolvedLinks += delta * unresolved
    }

    private mutating func adjustIncoming(links: [IndexedLink], delta: Int) {
        var deltas: [String: Int] = [:]
        for link in links {
            if let target = link.resolvedFile { deltas[target, default: 0] += delta }
        }
        guard !deltas.isEmpty else { return }
        entities = entities.map { entity in
            guard let change = deltas[entity.id] else { return entity }
            return EntitySummary(
                id: entity.id, kind: entity.kind, name: entity.name, qualifier: entity.qualifier,
                aliases: entity.aliases, incomingLinks: max(0, entity.incomingLinks + change))
        }
    }
}
