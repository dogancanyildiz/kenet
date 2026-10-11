import Foundation

/// The only data that leaves the system contact picker: a display name and an optional nickname.
struct ContactName: Equatable, Sendable {
    let name: String
    let nickname: String?

    init(name: String, nickname: String? = nil) {
        self.name = name
        self.nickname = nickname
    }
}

/// What the vault already holds under one entity, of any type: creation refuses a filename that
/// exists anywhere in the vault, and a name or alias that is already recognized must not be doubled.
struct ExistingEntityInfo: Equatable, Sendable {
    let name: String
    let aliases: [String]
    /// The filename without its folder and extension; `nil` when only the name is known.
    let fileStem: String?

    init(name: String, aliases: [String] = [], fileStem: String? = nil) {
        self.name = name
        self.aliases = aliases
        self.fileStem = fileStem
    }
}

/// The pure import plan calculated before any file is written.
struct ContactImportPlan: Equatable, Sendable {
    struct Item: Equatable, Sendable, Identifiable {
        /// Position in the selection.
        let id: Int
        /// The visible name as it is written to the `name` field (the store derives the filename).
        let name: String
        let aliases: [String]
    }

    struct SkippedItem: Equatable, Sendable, Identifiable {
        enum Reason: Equatable, Sendable {
            case alreadyExists
            case duplicateInSelection
        }

        let id: Int
        let name: String
        let reason: Reason
    }

    struct InvalidItem: Equatable, Sendable, Identifiable {
        let id: Int
        /// The trimmed selection name; empty when the contact has no usable name.
        let name: String
    }

    let toCreate: [Item]
    let alreadyExists: [SkippedItem]
    let invalid: [InvalidItem]

    var isEmpty: Bool { toCreate.isEmpty && alreadyExists.isEmpty && invalid.isEmpty }

    /// Same key as the store's filename collision check (`storeComparisonKey` in Core): NFC and
    /// locale-independent lowercase.
    static func comparisonKey(_ text: String) -> String {
        text.precomposedStringWithCanonicalMapping.lowercased().precomposedStringWithCanonicalMapping
    }

    /// The visible name and the filename the store would derive from it, or `nil` when
    /// `VaultStore.creatingEntity` would reject the name. `ContactImportModelTests` pins this to
    /// the store's own answer.
    static func validatedName(_ text: String) -> (name: String, fileStem: String)? {
        guard let name = displayText(text) else { return nil }
        let forbidden = Set("/\\:*?\"<>|#^[]".unicodeScalars)
        let stripped = String(name.unicodeScalars.filter { !forbidden.contains($0) })
        let stem = stripped.split(whereSeparator: \.isWhitespace).joined(separator: " ")
            .precomposedStringWithCanonicalMapping
        guard !stem.isEmpty, !stem.hasPrefix("."), (stem + ".md").utf8.count <= 255 else { return nil }
        return (name, stem)
    }

    private static func displayText(_ text: String) -> String? {
        let result = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !result.isEmpty,
            !result.unicodeScalars.contains(where: {
                CharacterSet.controlCharacters.contains($0) || CharacterSet.newlines.contains($0)
            })
        else { return nil }
        return result
    }

    static func build(
        selected: [ContactName], existingNames: [String] = [], existingAliases: [String] = []
    ) -> ContactImportPlan {
        build(
            selected: selected,
            existingEntities: existingNames.map { ExistingEntityInfo(name: $0) }
                + (existingAliases.isEmpty ? [] : [ExistingEntityInfo(name: "", aliases: existingAliases)]))
    }

    static func build(selected: [ContactName], existingEntities: [ExistingEntityInfo]) -> ContactImportPlan {
        var taken = Set<String>()
        for entity in existingEntities {
            for text in [entity.name] + entity.aliases + [entity.fileStem ?? ""] where !text.isEmpty {
                taken.insert(comparisonKey(text))
            }
        }

        // A nickname must not shadow any selected name, wherever that name stands in the selection.
        var selectedNameKeys = Set<String>()
        for contact in selected {
            guard let valid = validatedName(contact.name) else { continue }
            selectedNameKeys.insert(comparisonKey(valid.name))
            selectedNameKeys.insert(comparisonKey(valid.fileStem))
        }

        var toCreate: [Item] = []
        var alreadyExists: [SkippedItem] = []
        var invalid: [InvalidItem] = []
        var planned = Set<String>()

        for (index, contact) in selected.enumerated() {
            guard let valid = validatedName(contact.name) else {
                invalid.append(
                    InvalidItem(id: index, name: contact.name.trimmingCharacters(in: .whitespacesAndNewlines)))
                continue
            }
            let keys = [comparisonKey(valid.name), comparisonKey(valid.fileStem)]
            if keys.contains(where: taken.contains) {
                alreadyExists.append(SkippedItem(id: index, name: valid.name, reason: .alreadyExists))
                continue
            }
            if keys.contains(where: planned.contains) {
                alreadyExists.append(SkippedItem(id: index, name: valid.name, reason: .duplicateInSelection))
                continue
            }
            planned.formUnion(keys)

            var aliases: [String] = []
            if let nickname = contact.nickname.flatMap(displayText) {
                let key = comparisonKey(nickname)
                if !taken.contains(key), !planned.contains(key), !selectedNameKeys.contains(key) {
                    aliases.append(nickname)
                    planned.insert(key)
                }
            }
            toCreate.append(Item(id: index, name: valid.name, aliases: aliases))
        }

        return ContactImportPlan(toCreate: toCreate, alreadyExists: alreadyExists, invalid: invalid)
    }
}
