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
            try self.fileCoordination.coordinate(.modify(url)) { _ in
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
                    // A new file beside an undownloaded one would drop every other definition on sync.
                    try self.rejectPendingDownload(at: url, path: ".app/types.json")
                    guard expected == nil else { throw EntityTypeError.staleDefinition }
                    let encoder = JSONEncoder()
                    encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
                    data = try encoder.encode(EntityTypesFile(types: [definition]))
                }
                try self.persistEntityTypes(data, at: url)
            }
        }
    }

    /// Creates a new type, then its ``EntityTypeDefinition/starterTemplate`` when the definition
    /// names a file under the root `templates/` folder that does not exist yet. An existing
    /// template is the user's and stays untouched.
    ///
    /// The definition is saved first and stays saved. A template that is not written although the
    /// definition names one then throws ``EntityTypeTemplateError``: a path outside `templates/`
    /// (it would be indexed as a note, and `Templates/` is not the template folder), a template
    /// still downloading (it stays the user's), or a failed write. An index failure of the
    /// definition takes precedence and is thrown instead.
    public func creatingEntityType(_ definition: EntityTypeDefinition) async throws {
        var indexFailure: VaultStoreError?
        do {
            try await savingEntityType(definition)
        } catch let error as VaultStoreError {
            guard case .indexUpdateFailed = error else { throw error }
            indexFailure = error
        }
        var templateFailure: (any Error)?
        if let path = definition.template {
            if path.hasPrefix("templates/") {
                do {
                    try await perform {
                        try self.ensureReservedFolderCase(forCanonicalFolder: "templates")
                        let url = try self.checkedURL(path)
                        try self.fileCoordination.coordinate(.modify(url)) { _ in
                            guard !FileManager.default.fileExists(atPath: url.path) else { return }
                            try self.rejectPendingDownload(at: url, path: path)
                            do {
                                try self.atomicWrite(Data(definition.starterTemplate.utf8), to: url, exclusive: true)
                            } catch VaultStoreError.nameTaken {
                                // Another process created the template meanwhile; it wins.
                            }
                        }
                    }
                } catch {
                    templateFailure = error
                }
            } else {
                templateFailure = VaultStoreError.invalidPath
            }
        }
        if let indexFailure { throw indexFailure }
        if let templateFailure, let path = definition.template {
            throw EntityTypeTemplateError(path: path, underlying: templateFailure)
        }
    }

    public func deletingEntityType(_ expected: EntityTypeDefinition) async throws {
        try await perform {
            let url = try EntityTypeReader.fileURL(vaultRoot: self.root)
            try self.fileCoordination.coordinate(.modify(url)) { _ in
                let catalog = EntityTypeReader.read(vaultRoot: self.root)
                guard catalog.issue == nil else { throw EntityTypeError.invalidFile }
                guard catalog.types.first(where: { $0.id == expected.id }) == expected else {
                    throw EntityTypeError.staleDefinition
                }
                let data = try EntityTypeJSONEdit(try self.readFile(url)).deleting(expected.id)
                try self.persistEntityTypes(data, at: url)
            }
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

/// The type definition was saved; only its new template file could not be written.
public struct EntityTypeTemplateError: Error, Sendable {
    public let path: String
    public let underlying: any Error
}
