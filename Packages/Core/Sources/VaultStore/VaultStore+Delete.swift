import Foundation
import VaultFormat

extension VaultStore {
    /// Deletes only a definition; incoming links and journal bytes remain in the vault.
    public func deletingEntity(path: String) async throws {
        try await perform { try self.deleteDefinition(path: path, goal: false) }
    }

    /// Deletes only the goal file, retaining every historical goal log.
    public func deletingGoal(path: String) async throws {
        try await perform { try self.deleteDefinition(path: path, goal: true) }
    }

    private nonisolated func deleteDefinition(path: String, goal: Bool) throws {
        let url = try checkedURL(path, writing: true)
        try fileCoordination.coordinate(.delete(url)) { _ in
            // Recheck after presenters have saved and before reading or removing anything.
            _ = try checkedURL(path, writing: true)
            try rejectPendingDownload(at: url, path: path)
            guard try url.resourceValues(forKeys: [.isRegularFileKey]).isRegularFile == true else {
                throw VaultStoreError.invalidPath
            }
            let document = RawDocument(bytes: try readFile(url))
            guard !document.isReadOnly, case .parsed(let fields) = document.frontmatter,
                case .scalar(let type) = fields.field(named: "type")?.value, type.kind == .text
            else { throw VaultStoreError.staleTarget }
            let folder: String
            if goal {
                guard type.text == "goal" else { throw VaultStoreError.staleTarget }
                folder = "goals"
            } else {
                switch type.text {
                case "person": folder = "people"
                case "place": folder = "places"
                default:
                    guard let definition = customDefinition(type.text) else { throw VaultStoreError.staleTarget }
                    folder = definition.folder
                }
            }
            let parent = path.split(separator: "/").dropLast().joined(separator: "/")
            guard parent == folder else { throw VaultStoreError.invalidPath }
            try removeFile(url)
            do {
                try index.update(paths: [path], vaultRoot: root)
            } catch {
                throw VaultStoreError.indexUpdateFailed(path: path, underlying: error)
            }
        }
    }
}
