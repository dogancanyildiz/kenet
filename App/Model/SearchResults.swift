import Foundation
import VaultFormat
import VaultIndex

enum SearchGroup: String, CaseIterable, Identifiable {
    case people, places, entities, events, tasks, notes
    var id: String { rawValue }
    var title: String {
        switch self {
        case .people: String(localized: "Kişiler")
        case .places: String(localized: "Konumlar")
        case .entities: String(localized: "Varlıklar")
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
    static func build(
        query: String, entities: [EntitySummary], matches: [SearchResult],
        locale: Locale = .autoupdatingCurrent
    ) -> [SearchItem] {
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
                id: "entity:" + entity.id,
                group: entity.kind == "person" ? .people : entity.kind == "place" ? .places : .entities,
                title: entity.name,
                detail: [entity.qualifier, alias].compactMap { $0 }.joined(separator: " · "),
                destination: .entity(entity.id))
        }
        var seen = Set<String>()
        let blocks = matches.compactMap { match -> SearchItem? in
            if match.block == nil && entities.contains(where: { $0.id == match.file }) { return nil }
            let id = match.file + ":" + (match.block.map(String.init) ?? "name")
            guard seen.insert(id).inserted else { return nil }
            let group: SearchGroup =
                match.blockKind == "event" ? .events : match.blockKind == "task" ? .tasks : .notes
            let day = match.fileKind == "day" ? match.date.flatMap { CalendarDate($0) } : nil
            let detail = formattedDetail(date: match.date, locale: locale)
            return SearchItem(
                id: id, group: group, title: SearchPreviewText.display(match.text), detail: detail,
                destination: day.map { .day($0) } ?? .note(match.file))
        }
        // Stable partition preserves prefix/name ordering for entities and FTS rank for blocks.
        return SearchGroup.allCases.flatMap { group in (named + blocks).filter { $0.group == group } }
    }

    /// Localized day when present; never a vault path (entity/note paths stay out of detail).
    private static func formattedDetail(date: String?, locale: Locale) -> String {
        guard let date, let day = CalendarDate(date) else { return "" }
        return LocalDay.instant(for: day).formatted(
            .dateTime.day().month(.abbreviated).year().locale(locale))
    }

    static func comparisonKey(_ text: String) -> String {
        text.precomposedStringWithCanonicalMapping.lowercased()
    }
}
