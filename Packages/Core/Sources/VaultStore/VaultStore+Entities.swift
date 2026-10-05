import Foundation
import VaultFormat
import VaultIndex

extension VaultStore {
    /// Creates a person or place from its compatible template, then indexes the new file.
    /// Returns the vault-relative filename used by wikilinks.
    @discardableResult
    public func creatingEntity(
        kind: VaultEntityKind, name: String, qualifier: String? = nil, aliases: [String]? = nil
    ) async throws -> String {
        try await perform {
            let name = try self.displayName(name)
            let qualifier = try qualifier.map(self.displayName)
            let cleanName = try self.filenameComponent(name)
            let cleanQualifier = try qualifier.map(self.filenameComponent)
            let stem = cleanName + (cleanQualifier.map { " (" + $0 + ")" } ?? "")
            guard (stem + ".md").utf8.count <= 255 else { throw VaultStoreError.invalidName }
            guard try !self.filenameIsTaken(stem) else { throw VaultStoreError.nameTaken }
            let definition: EntityTypeDefinition
            if case .custom(let id) = kind {
                guard let value = self.customDefinition(id) else { throw EntityTypeError.unknownType }
                definition = value
            } else {
                definition = EntityTypeDefinition.builtIns.first { $0.id == kind.rawValue }!
            }
            let path = definition.folder + "/" + stem + ".md"
            var document = try self.template(for: kind, definition: definition)
            document = try document.settingFrontmatterValue(.text(name), forKey: "name")
            if let qualifier { document = try document.settingFrontmatterValue(.text(qualifier), forKey: "qualifier") }
            if let aliases {
                document = try document.settingFrontmatterList(
                    aliases.filter { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }.map { .text($0) },
                    forKey: "aliases")
            }
            try self.persist(document, path: path, exclusive: true)
            return path
        }
    }

    nonisolated func customDefinition(_ id: String) -> EntityTypeDefinition? {
        EntityTypeReader.read(vaultRoot: root).types.first { $0.id == id }
    }

    private nonisolated func template(for kind: VaultEntityKind, definition: EntityTypeDefinition) throws -> RawDocument
    {
        if case .custom = kind, definition.template == nil {
            return try RawDocument(bytes: []).settingFrontmatterValue(.text(kind.rawValue), forKey: "type")
        }
        let path = definition.template ?? "templates/" + kind.rawValue + ".md"
        let url = try checkedURL(path)
        let document: RawDocument
        do {
            document = RawDocument(bytes: try readFile(url))
        } catch CocoaError.fileReadNoSuchFile {
            return try RawDocument(bytes: []).settingFrontmatterValue(.text(kind.rawValue), forKey: "type")
        }
        if case .custom = kind {
            guard !document.isReadOnly, document.frontmatter != .unreadable else { throw EntityTypeError.invalidFile }
            return try document.settingFrontmatterValue(.text(kind.rawValue), forKey: "type")
        }
        if case .parsed(let frontmatter) = document.frontmatter,
            case .scalar(let value) = frontmatter.field(named: "type")?.value,
            value.kind == .text, value.text == kind.rawValue
        {
            return document
        }
        return try RawDocument(bytes: []).settingFrontmatterValue(.text(kind.rawValue), forKey: "type")
    }

    nonisolated func displayName(_ text: String) throws -> String {
        let result = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !result.isEmpty,
            !result.unicodeScalars.contains(where: {
                CharacterSet.controlCharacters.contains($0) || CharacterSet.newlines.contains($0)
            })
        else { throw VaultStoreError.invalidName }
        return result
    }

    nonisolated func filenameComponent(_ text: String) throws -> String {
        let forbidden = Set("/\\:*?\"<>|#^[]".unicodeScalars)
        let stripped = String(text.unicodeScalars.filter { !forbidden.contains($0) })
        let result = stripped.split(whereSeparator: \.isWhitespace).joined(separator: " ")
            .precomposedStringWithCanonicalMapping
        guard !result.isEmpty, !result.hasPrefix(".") else { throw VaultStoreError.invalidName }
        return result
    }
}
