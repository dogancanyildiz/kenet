import EntityRecognition
import Foundation
import VaultFormat

enum EntityOrdering: String, CaseIterable { case name, recent }

enum EntityListQuery {
    static func entities(
        in content: VaultReadModel, usage: [EntityUsage], kind: String, search: String, order: EntityOrdering
    ) -> [EntitySummary] {
        let search = search.trimmingCharacters(in: .whitespacesAndNewlines)
        // The vault's name rule, either reading: `DENİZ` finds `Deniz`, `SELIN` still finds `Selin`.
        let key = NameCollision(search)
        let dates = Dictionary(uniqueKeysWithValues: usage.map { ($0.file, $0.lastDate?.description ?? "") })
        return content.entities.filter { entity in
            entity.kind == kind
                && (search.isEmpty
                    || ([entity.name, entity.qualifier ?? ""] + entity.aliases).contains { key.occurs(in: $0) })
        }.sorted {
            if order == .recent, dates[$0.id] != dates[$1.id] { return (dates[$0.id] ?? "") > (dates[$1.id] ?? "") }
            let name = $0.name.localizedStandardCompare($1.name)
            if name != .orderedSame { return name == .orderedAscending }
            return $0.id < $1.id
        }
    }
}
