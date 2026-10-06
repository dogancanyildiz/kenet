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
        let knownGraph = Set(
            entities.filter { $0.kind == "person" || $0.kind == "place" }.map(\.id))

        for path in removed.union(touched) {
            if let old = before[path] {
                subtractContributions(of: old, knownGraph: knownGraph)
            }
        }
        for path in touched {
            if let fragment = fragments[path] {
                addContributions(of: fragment, knownGraph: knownGraph)
            }
        }

        tasks.sort { left, right in
            if left.file != right.file { return left.file < right.file }
            return left.sourceLine < right.sourceLine
        }
        days.sort { $0.date > $1.date }
        graphInput.days.sort { $0.date < $1.date }
        graphInput.entities = entities.filter { knownGraph.contains($0.id) }

        let goalTouched = removed.union(touched).contains { path in
            !(before[path]?.goalLogs.isEmpty ?? true)
                || !(fragments[path]?.goalLogs.isEmpty ?? true)
        }
        if goalTouched {
            // Sparse; rebuild in path order so arrays match a full snapshot derive.
            let indexedLogs = fragments.keys.sorted().flatMap { fragments[$0]!.goalLogs }
            reservedGoalKeys = Set(goals.map(\.key) + indexedLogs.map(\.key))
            let allLogs = Dictionary(grouping: indexedLogs, by: \.key).mapValues {
                $0.compactMap(GoalLog.init(indexed:))
            }
            goalLogs = allLogs.mapValues { $0.filter { $0.day >= goalLogStart && $0.day <= goalLogEnd } }
            for goal in goals {
                goalStatuses[goal.key] = GoalProgress.compute(
                    definition: goal, logs: allLogs[goal.key] ?? [], today: today)
            }
            let goalFiles = Set(indexedLogs.map(\.file))
            for index in days.indices {
                days[index].hasGoalRecords = goalFiles.contains(days[index].id)
            }
        }
    }

    private mutating func subtractContributions(
        of fragment: VaultFileFragment, knownGraph: Set<String>
    ) {
        let path = fragment.file.path
        tasks.removeAll { $0.file == path }
        days.removeAll { $0.id == path }
        removeTimelineRows(
            from: path, targets: Set(fragment.links.compactMap(\.resolvedFile)))
        adjustIncoming(links: fragment.links, delta: -1)
        adjustGraph(links: fragment.links, dates: dayDate(fragment), knownGraph: knownGraph, delta: -1)
        adjustCounts(of: fragment, delta: -1)
    }

    private mutating func addContributions(
        of fragment: VaultFileFragment, knownGraph: Set<String>
    ) {
        let links = fragment.links
        tasks += fragment.blocks.filter { $0.kind == "task" }.map { TaskRow(row: $0, links: links) }
        if fragment.file.kind == "day", let value = fragment.file.date, let date = CalendarDate(value) {
            days.append(daySummary(fragment: fragment, date: date, hasGoalRecords: !fragment.goalLogs.isEmpty))
            addTimelineRows(fragment: fragment, date: date)
        }
        adjustIncoming(links: links, delta: 1)
        adjustGraph(links: links, dates: dayDate(fragment), knownGraph: knownGraph, delta: 1)
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

    private func dayDate(_ fragment: VaultFileFragment) -> CalendarDate? {
        guard fragment.file.kind == "day", let value = fragment.file.date else { return nil }
        return CalendarDate(value)
    }

    private func daySummary(
        fragment: VaultFileFragment, date: CalendarDate, hasGoalRecords: Bool
    ) -> DaySummary {
        let rows = fragment.blocks.sorted { $0.ordinal < $1.ordinal }
        let sourceLinks = fragment.links
        let events = rows.filter { $0.kind == "event" }.map { row in
            EventRow(
                id: row.ordinal,
                time: row.time.flatMap {
                    RawDocument(bytes: Array("## Events\n- \($0) event".utf8)).bodyLines.events.first?.time
                },
                text: LinkedText(row: row, links: sourceLinks),
                sourceLine: row.firstLine - 1, sourceEnd: row.lastLine,
                sourceText: row.text, sourceIdentifier: row.identifier)
        }
        let journal = rows.filter { $0.section == "Journal" && ["paragraph", "heading"].contains($0.kind) }
            .map { row in
                JournalRow(
                    id: row.ordinal, headingLevel: row.headingLevel,
                    text: LinkedText(row: row, links: sourceLinks))
            }
        return DaySummary(
            id: fragment.file.path, date: date, events: events, journal: journal,
            hasGoalRecords: hasGoalRecords)
    }

    private mutating func removeTimelineRows(from path: String, targets: Set<String>) {
        for key in targets {
            guard var days = entityTimeline[key] else { continue }
            days = days.compactMap { day in
                let rows = day.rows.filter { $0.file != path }
                return rows.isEmpty ? nil : EntityTimelineDay(date: day.date, rows: rows)
            }
            entityTimeline[key] = days.isEmpty ? nil : days
        }
    }

    private mutating func addTimelineRows(fragment: VaultFileFragment, date: CalendarDate) {
        let links = fragment.links
        var byTarget: [String: [EntityTimelineRow]] = [:]
        for block in fragment.blocks
        where block.kind == "event" || (block.kind == "paragraph" && block.section == "Journal") {
            let targets = Set(links.filter { $0.block == block.ordinal }.compactMap(\.resolvedFile))
            guard !targets.isEmpty else { continue }
            let row = EntityTimelineRow(
                file: fragment.file.path, ordinal: block.ordinal,
                text: LinkedText(row: block, links: links))
            for target in targets { byTarget[target, default: []].append(row) }
        }
        for (target, rows) in byTarget {
            var days = entityTimeline[target] ?? []
            if let index = days.firstIndex(where: { $0.date == date }) {
                let merged = (days[index].rows + rows).sorted {
                    ($0.file, $0.ordinal) > ($1.file, $1.ordinal)
                }
                days[index] = EntityTimelineDay(date: date, rows: merged)
            } else {
                days.append(
                    EntityTimelineDay(
                        date: date, rows: rows.sorted { ($0.file, $0.ordinal) > ($1.file, $1.ordinal) }))
                days.sort { $0.date > $1.date }
            }
            entityTimeline[target] = days
        }
    }

    private mutating func adjustGraph(
        links: [IndexedLink], dates: CalendarDate?, knownGraph: Set<String>, delta: Int
    ) {
        var dayMentions = dates.map { date -> (CalendarDate, [String: Int]) in
            if let existing = graphInput.days.first(where: { $0.date == date }) {
                return (date, existing.mentions)
            }
            return (date, [:])
        }
        for link in links {
            guard let target = link.resolvedFile, knownGraph.contains(target) else { continue }
            graphInput.totals[target, default: 0] += delta
            if graphInput.totals[target] == 0 { graphInput.totals[target] = nil }
            if var pair = dayMentions {
                pair.1[target, default: 0] += delta
                if pair.1[target] == 0 { pair.1[target] = nil }
                dayMentions = pair
            }
        }
        if let pair = dayMentions {
            graphInput.days.removeAll { $0.date == pair.0 }
            if !pair.1.isEmpty {
                graphInput.days.append(GraphInput.Day(date: pair.0, mentions: pair.1))
            }
        }
    }
}
