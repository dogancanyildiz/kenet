import Foundation
import VaultFormat
import VaultIndex

enum SearchGroup: String, CaseIterable, Identifiable {
    case people, places, events, tasks, notes
    var id: String { rawValue }
    var title: String {
        switch self {
        case .people: String(localized: "Kişiler")
        case .places: String(localized: "Konumlar")
        case .events: String(localized: "Olaylar")
        case .tasks: String(localized: "Görevler")
        case .notes: String(localized: "Notlar")
        }
    }
}

enum SearchDestination: Hashable {
    case entity(String)
    case day(CalendarDate)
    case note(String)
}

struct SearchItem: Identifiable, Hashable {
    let id: String
    let group: SearchGroup
    let title: String
    let detail: String
    let destination: SearchDestination
}

enum SearchResults {
    static func build(query: String, entities: [EntitySummary], matches: [SearchResult]) -> [SearchItem] {
        let key = comparisonKey(query)
        let entityMatches = Set(matches.filter { $0.block == nil }.map(\.file))
        let names = entities.filter {
            entityMatches.contains($0.id) || ([$0.name] + $0.aliases).contains { comparisonKey($0).hasPrefix(key) }
        }.sorted {
            let left = ([$0.name] + $0.aliases).contains { comparisonKey($0).hasPrefix(key) }
            let right = ([$1.name] + $1.aliases).contains { comparisonKey($0).hasPrefix(key) }
            if left != right { return left }
            if $0.name != $1.name { return $0.name < $1.name }
            return $0.id < $1.id
        }
        let named = names.map { entity in
            let alias =
                entity.aliases.first { comparisonKey($0).hasPrefix(key) }
                ?? matches.first { $0.file == entity.id && $0.block == nil && $0.text != entity.name }?.text
            return SearchItem(
                id: "entity:" + entity.id, group: entity.kind == "person" ? .people : .places,
                title: entity.name,
                detail: [entity.qualifier, alias, entity.id].compactMap { $0 }.joined(separator: " · "),
                destination: .entity(entity.id))
        }
        var seen = Set<String>()
        let blocks = matches.compactMap { match -> SearchItem? in
            if match.block == nil && (match.fileKind == "person" || match.fileKind == "place") { return nil }
            let id = match.file + ":" + (match.block.map(String.init) ?? "name")
            guard seen.insert(id).inserted else { return nil }
            let group: SearchGroup = match.blockKind == "event" ? .events : match.blockKind == "task" ? .tasks : .notes
            let day = match.fileKind == "day" ? match.date.flatMap { CalendarDate($0) } : nil
            return SearchItem(
                id: id, group: group, title: match.text, detail: match.date ?? match.file,
                destination: day.map { .day($0) } ?? .note(match.file))
        }
        // Stable partition preserves prefix/name ordering for entities and FTS rank for blocks.
        return SearchGroup.allCases.flatMap { group in (named + blocks).filter { $0.group == group } }
    }

    static func comparisonKey(_ text: String) -> String {
        text.precomposedStringWithCanonicalMapping.lowercased()
    }
}
