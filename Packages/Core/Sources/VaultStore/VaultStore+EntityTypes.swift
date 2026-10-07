import Foundation
import VaultFormat
import VaultIndex

extension VaultStore {
    public func entityTypes() -> EntityTypeCatalog { EntityTypeReader.read(vaultRoot: root) }

    /// Edits only one definition, refusing stale or damaged schemas instead of replacing them.
    public func savingEntityType(_ definition: EntityTypeDefinition, replacing expected: EntityTypeDefinition? = nil)
        async throws
    {
        try definition.validate()
        try await perform {
            let url = try EntityTypeReader.fileURL(vaultRoot: self.root)
            let catalog = EntityTypeReader.read(vaultRoot: self.root)
            guard catalog.issue == nil else { throw EntityTypeError.invalidFile }
            if let expected {
                guard definition.id == expected.id, catalog.types.first(where: { $0.id == expected.id }) == expected
                else { throw EntityTypeError.staleDefinition }
            } else if catalog.types.contains(where: { $0.id == definition.id }) {
                throw EntityTypeError.invalidDefinition
            }
            let data: Data
            do {
                data = try EntityTypeJSONEdit(try self.readFile(url)).upserting(definition, replacing: expected?.id)
            } catch CocoaError.fileReadNoSuchFile {
                guard expected == nil else { throw EntityTypeError.staleDefinition }
                let encoder = JSONEncoder()
                encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
                data = try encoder.encode(EntityTypesFile(types: [definition]))
            }
            try self.persistEntityTypes(data, at: url)
        }
    }

    public func deletingEntityType(_ expected: EntityTypeDefinition) async throws {
        try await perform {
            let url = try EntityTypeReader.fileURL(vaultRoot: self.root)
            let catalog = EntityTypeReader.read(vaultRoot: self.root)
            guard catalog.issue == nil else { throw EntityTypeError.invalidFile }
            guard catalog.types.first(where: { $0.id == expected.id }) == expected else {
                throw EntityTypeError.staleDefinition
            }
            let data = try EntityTypeJSONEdit(try self.readFile(url)).deleting(expected.id)
            try self.persistEntityTypes(data, at: url)
        }
    }

    private nonisolated func persistEntityTypes(_ data: Data, at url: URL) throws {
        guard EntityTypeReader.decode(data).issue == nil else { throw EntityTypeError.invalidFile }
        try atomicWrite(data, to: url, exclusive: !FileManager.default.fileExists(atPath: url.path))
        do { try index.refresh(vaultRoot: root) } catch {
            throw VaultStoreError.indexUpdateFailed(path: ".app/types.json", underlying: error)
        }
    }
}
