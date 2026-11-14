import Foundation
import VaultFormat

/// What the entity page accepts as a new alias (pure, unit-tested). Names compare with the vault's
/// own fold (`nameComparisonFold`): Turkish `İ`/`i` and `I`/`ı`, on every device.
enum EntityAliasRules {
    enum Rejection: Error, Equatable {
        case empty, invalidCharacter, sameAsName, alreadyAlias
        /// The file's `aliases` is not a list of plain text (a mapping, raw text, a number).
        case notEditable

        var message: String {
            switch self {
            case .empty: String(localized: "Takma ad boş olamaz.")
            case .invalidCharacter: String(localized: "Takma ad | [ ] ya da satır sonu içeremez.")
            case .sameAsName: String(localized: "Bu, kaydın kendi adı.")
            case .alreadyAlias: String(localized: "Bu takma ad zaten var.")
            case .notEditable: String(localized: "Takma ad alanı salt okunur.")
            }
        }
    }

    static func cleaned(_ text: String) -> String { text.trimmingCharacters(in: .whitespacesAndNewlines) }

    /// The file's items as text, as the editor reads them.
    static func texts(_ items: [FrontmatterScalar]?) throws(Rejection) -> [String] {
        guard let items, items.allSatisfy({ $0.kind == .text }) else { throw .notEditable }
        return items.map(\.text)
    }

    /// The list with the trimmed alias at its end. An alias is the visible text of a link
    /// (`[[Ad|takma ad]]`), so the characters that end or split a link are refused.
    static func adding(_ text: String, to aliases: [String], name: String) throws(Rejection) -> [String] {
        let alias = cleaned(text)
        guard !alias.isEmpty else { throw .empty }
        let breaksLink = alias.unicodeScalars.contains {
            "|[]".unicodeScalars.contains($0) || $0.properties.generalCategory == .control
                || $0 == "\u{2028}" || $0 == "\u{2029}"
        }
        guard !breaksLink else { throw .invalidCharacter }
        let key = nameComparisonFold(alias)
        guard key != nameComparisonFold(cleaned(name)) else { throw .sameAsName }
        guard !aliases.contains(where: { nameComparisonFold(cleaned($0)) == key }) else { throw .alreadyAlias }
        return aliases + [alias]
    }

    /// The list without that spelling; every other item keeps its place.
    static func removing(_ alias: String, from aliases: [String]) -> [String] { aliases.filter { $0 != alias } }

    /// Other records the text also names. Recognition then finds two candidates and links none
    /// until the user chooses (docs/vault-format.md, "Otomatik tanıma ve belirsizlik").
    static func conflicts(_ text: String, path: String, entities: [EntitySummary]) -> [EntitySummary] {
        let key = nameComparisonFold(cleaned(text))
        guard !key.isEmpty else { return [] }
        return entities.filter { entity in
            entity.id != path && ([entity.name] + entity.aliases).contains { nameComparisonFold(cleaned($0)) == key }
        }
    }
}
