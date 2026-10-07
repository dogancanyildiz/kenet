import Foundation
import VaultFormat
import VaultStore

struct EntityTypeChoice: Identifiable, Hashable {
    let definition: EntityTypeDefinition
    let language: String
    var id: String { definition.id }
    var name: String {
        switch id {
        case "person": String(localized: "Kişi")
        case "place": String(localized: "Konum")
        default: definition.name.localized(language: language)
        }
    }
    var plural: String {
        switch id {
        case "person": String(localized: "Kişiler")
        case "place": String(localized: "Konumlar")
        default: definition.plural.localized(language: language)
        }
    }
    var kind: VaultEntityKind {
        switch id {
        case "person": .person
        case "place": .place
        default: .custom(id)
        }
    }
}

enum EntityTypeChoices {
    static func choices(
        _ catalog: EntityTypeCatalog, language: String = Locale.current.language.languageCode?.identifier ?? "en"
    ) -> [EntityTypeChoice] {
        catalog.allTypes.map { EntityTypeChoice(definition: $0, language: language) }
    }
    static func selection(_ selected: String, in catalog: EntityTypeCatalog) -> String {
        catalog.allTypes.contains { $0.id == selected } ? selected : "person"
    }
}
