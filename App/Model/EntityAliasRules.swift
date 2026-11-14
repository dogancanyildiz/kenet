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
    /// (`[[Ad|takma ad]]`), so the characters that end or split a link are refused, and so are the
    /// ones nobody can see in a name.
    static func adding(_ text: String, to aliases: [String], name: String) throws(Rejection) -> [String] {
        let alias = cleaned(text)
        guard !alias.isEmpty else { throw .empty }
        guard !hasRefusedCharacter(alias) else { throw .invalidCharacter }
        let key = nameComparisonFold(alias)
        guard key != nameComparisonFold(cleaned(name)) else { throw .sameAsName }
        guard !aliases.contains(where: { nameComparisonFold(cleaned($0)) == key }) else { throw .alreadyAlias }
        return aliases + [alias]
    }

    /// `|`, `[`, `]`; control characters and the line and paragraph separators (U+2028, U+2029);
    /// format characters, which draw nothing: zero-width space, byte order mark, direction marks,
    /// soft hyphen. Two kinds of format character belong to an emoji and stay: the joiner (U+200D)
    /// between two emoji, and the tag letters of a flag after the black flag (U+1F3F4).
    static func hasRefusedCharacter(_ text: String) -> Bool {
        let scalars = Array(text.unicodeScalars)
        return scalars.indices.contains { index in
            let scalar = scalars[index]
            if "|[]".unicodeScalars.contains(scalar) { return true }
            switch scalar.properties.generalCategory {
            case .control, .lineSeparator, .paragraphSeparator: return true
            case .format: return !isEmojiFormat(at: index, in: scalars)
            default: return false
            }
        }
    }

    private static func isEmojiFormat(at index: Int, in scalars: [Unicode.Scalar]) -> Bool {
        let scalar = scalars[index]
        if scalar == "\u{200D}" {
            guard index > 0, index + 1 < scalars.count else { return false }
            // The variation selector and a skin tone sit between an emoji and its joiner.
            let before = scalars[index - 1]
            return (isPictograph(before) || before == "\u{FE0F}") && isPictograph(scalars[index + 1])
        }
        guard (0xE0020...0xE007F).contains(scalar.value), index > 0 else { return false }
        let before = scalars[index - 1]
        return before == "\u{1F3F4}" || (0xE0020...0xE007E).contains(before.value)
    }

    /// An emoji that is not also a digit or a sign of plain text (`0`–`9`, `#`, `*`, `©`, `®`).
    private static func isPictograph(_ scalar: Unicode.Scalar) -> Bool {
        scalar.properties.isEmoji && scalar.value > 0xFF
    }

    /// The list without that item. Values compare byte for byte, as the file does
    /// (docs/vault-format.md): a composed and a decomposed spelling are two items, and only the
    /// first item with these bytes goes.
    static func removing(_ alias: String, from aliases: [String]) -> [String] {
        guard let index = aliases.firstIndex(where: { $0.utf8.elementsEqual(alias.utf8) }) else { return aliases }
        var kept = aliases
        kept.remove(at: index)
        return kept
    }

    /// One chip per shown alias, identified by the item's bytes and its turn among equal ones, so
    /// two spellings of one name are two chips and each removes itself.
    static func chips(_ aliases: [String]) -> [(id: [UInt8], text: String)] {
        var seen: [[UInt8]: UInt8] = [:]
        return aliases.filter { !cleaned($0).isEmpty }.map { alias in
            let bytes = Array(alias.utf8)
            let turn = seen[bytes, default: 0]
            seen[bytes] = turn &+ 1
            return (bytes + [0xFF, turn], alias)
        }
    }

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
