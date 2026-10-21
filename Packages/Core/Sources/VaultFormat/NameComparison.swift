import Foundation

/// The vault's single name comparison rule (`docs/vault-format.md`, "Adlar ve karşılaştırma"): the
/// Turkish capitals `İ` → `i` and `I` → `ı`, then Unicode's default, locale-independent lowercase
/// mapping, where a combining dot right after `i` is dropped.
///
/// The result is canonically equal for canonically equal inputs, so Swift `String` equality and
/// hashing compare it without Foundation; the recognizer relies on that. Stored and byte-compared
/// keys use ``nameComparisonKey(_:)`` instead.
public func nameComparisonFold(_ text: String) -> String {
    var mapped = String.UnicodeScalarView()
    var scalars = text.unicodeScalars.makeIterator()
    var pending = scalars.next()
    while let scalar = pending {
        pending = scalars.next()
        switch scalar {
        case "\u{0130}":
            mapped.append("i")
        case "I":
            // A decomposed `İ` is `I` followed by a combining dot above.
            if pending == "\u{0307}" {
                mapped.append("i")
                pending = scalars.next()
            } else {
                mapped.append("\u{0131}")
            }
        default:
            mapped.append(scalar)
        }
    }
    var folded = String.UnicodeScalarView()
    for scalar in String(mapped).lowercased().unicodeScalars {
        // Default lowercasing spells `İ` as `i` with a combining dot; it reads as plain `i`.
        if scalar == "\u{0307}", folded.last == "i" { continue }
        folded.append(scalar)
    }
    return String(folded)
}

/// The NFC bytes of ``nameComparisonFold(_:)``: the key the index stores and the store compares
/// byte for byte for filenames, entity names, aliases and link targets.
public func nameComparisonKey(_ text: String) -> String {
    nameComparisonFold(text.precomposedStringWithCanonicalMapping).precomposedStringWithCanonicalMapping
}

/// The name collision rule (`docs/vault-format.md`): two names may not share the vault when their
/// ``nameComparisonKey(_:)`` match, or when Unicode's default lowercase mapping alone matches them.
///
/// The second reading is how the Mac file system and Obsidian compare names, so `SELIN.md` and
/// `Selin.md` still collide although their keys differ. Only uniqueness checks use it; lookup and
/// link resolution use ``nameComparisonKey(_:)`` alone.
public struct NameCollision: Sendable, Hashable {
    /// The name's ``nameComparisonKey(_:)``.
    public let key: String
    /// The NFC bytes of the name under Unicode's default lowercase mapping alone.
    public let lowercaseKey: String

    /// Prepares the comparison for `name`, a filename stem or a display name.
    public init(_ name: String) {
        key = nameComparisonKey(name)
        lowercaseKey = name.precomposedStringWithCanonicalMapping.lowercased().precomposedStringWithCanonicalMapping
    }

    /// Whether `other` collides with the prepared name.
    public func matches(_ other: String) -> Bool {
        collides(with: NameCollision(other))
    }

    /// Whether the prepared text, a search fragment, occurs inside `name` under either reading.
    public func occurs(in name: String) -> Bool {
        let other = NameCollision(name)
        return other.key.contains(key) || other.lowercaseKey.contains(lowercaseKey)
    }

    /// Whether the two prepared names collide: either reading makes them the same name.
    public func collides(with other: NameCollision) -> Bool {
        key.utf8.elementsEqual(other.key.utf8) || lowercaseKey.utf8.elementsEqual(other.lowercaseKey.utf8)
    }
}
