import EntityRecognition
import Foundation

enum EntityOrdering: String, CaseIterable { case name, recent }

enum EntityListQuery {
    static func entities(
        in content: VaultReadModel, usage: [EntityUsage], kind: String, search: String, order: EntityOrdering
    ) -> [EntitySummary] {
        let key = search.trimmingCharacters(in: .whitespacesAndNewlines).precomposedStringWithCanonicalMapping
            .lowercased()
        let dates = Dictionary(uniqueKeysWithValues: usage.map { ($0.file, $0.lastDate?.description ?? "") })
        return content.entities.filter { entity in
            entity.kind == kind
                && (key.isEmpty
                    || ([entity.name, entity.qualifier ?? ""] + entity.aliases).contains {
                        $0.precomposedStringWithCanonicalMapping.lowercased().contains(key)
                    })
        }.sorted {
            if order == .recent, dates[$0.id] != dates[$1.id] { return (dates[$0.id] ?? "") > (dates[$1.id] ?? "") }
            let name = $0.name.localizedStandardCompare($1.name)
            if name != .orderedSame { return name == .orderedAscending }
            return $0.id < $1.id
        }
    }
}
