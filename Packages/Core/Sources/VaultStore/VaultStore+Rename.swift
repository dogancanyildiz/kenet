import Foundation
import VaultFormat

extension VaultStore {
    /// Renames a person/place and updates resolved links under the shared vault write queue.
    public func renamingEntity(at path: String, to name: String, qualifier: String? = nil) async throws -> RenameResult
    {
        try await perform { try self.rename(path: path, name: name, qualifier: qualifier) }
    }

    private nonisolated func rename(path: String, name: String, qualifier: String?) throws -> RenameResult {
        let name = try displayName(name)
        let qualifier = try qualifier.map(displayName)
        let stem = try filenameComponent(name) + (try qualifier.map { " (" + (try filenameComponent($0)) + ")" } ?? "")
        guard (stem + ".md").utf8.count <= 255 else { throw VaultStoreError.invalidName }
        let sourceURL = try checkedURL(path, writing: true)
        let newPath = ((path as NSString).deletingLastPathComponent as NSString).appendingPathComponent(stem + ".md")
        let targetURL = try checkedURL(newPath, writing: true)
        guard try !filenameIsTaken(stem, excluding: path) else { throw VaultStoreError.nameTaken }
        let original = RawDocument(bytes: try Data(contentsOf: sourceURL))
        guard case .parsed(let frontmatter) = original.frontmatter,
            case .scalar(let type) = frontmatter.field(named: "type")?.value,
            ["person", "place"].contains(type.text)
        else { throw VaultStoreError.staleTarget }
        let files = try markdownPaths()
        let newFiles = Set(files).subtracting(try index.files().map(\.path))
        let candidates = Set(try index.links(to: path).map(\.file))
        let targets = RenameTargets(oldPath: path, newPath: newPath, files: files)
        var changed = try original.settingFrontmatterValue(.text(name), forKey: "name")
        if let qualifier {
            changed = try changed.settingFrontmatterValue(.text(qualifier), forKey: "qualifier")
        } else {
            changed = try changed.removingFrontmatterField(forKey: "qualifier")
        }
        if changed != original { try atomicWrite(Data(changed.serialized()), to: sourceURL, exclusive: false) }
        if !path.utf8.elementsEqual(newPath.utf8) {
            do { try moveFile(sourceURL, targetURL) } catch {
                let moveError = error
                do {
                    if changed != original {
                        if let restoreRenameFile {
                            try restoreRenameFile(Data(original.serialized()), sourceURL)
                        } else {
                            try atomicWrite(Data(original.serialized()), to: sourceURL, exclusive: false)
                        }
                    }
                } catch {
                    var failures = [
                        RenameFailure(
                            path: path,
                            reason: .partialChange(
                                "move: \(moveError); restore: \(error)"))
                    ]
                    do { try index.update(paths: [path, newPath], vaultRoot: root) } catch {
                        failures.append(RenameFailure(path: path, reason: .index(String(describing: error))))
                    }
                    return RenameResult(path: path, updatedFiles: [path], failures: failures)
                }
                _ = try? index.update(paths: [path, newPath], vaultRoot: root)
                if FileManager.default.fileExists(atPath: targetURL.path) { throw VaultStoreError.nameTaken }
                throw moveError
            }
        }
        var updated: Set<String> = changed != original || path != newPath ? [newPath] : []
        var failures: [RenameFailure] = []
        // Also inspect indexed raw fields, which deliberately have no link rows.
        for source in (path.utf8.elementsEqual(newPath.utf8) ? [] : Set(files).union(candidates).sorted()) {
            let destination = source == path ? newPath : source
            do {
                let url = try checkedURL(destination, writing: true)
                let document = RawDocument(bytes: try Data(contentsOf: url))
                if document.isReadOnly && !candidates.contains(source) { continue }
                let rewrite = try RenameDocument.rewrite(
                    document, targets: targets, eligible: candidates.contains(source))
                if rewrite.document != document {
                    try atomicWrite(Data(rewrite.document.serialized()), to: url, exclusive: false)
                    updated.insert(destination)
                }
                failures += rewrite.rawFields.map { RenameFailure(path: destination, reason: .rawField($0)) }
            } catch {
                if candidates.contains(source) {
                    failures.append(RenameFailure(path: destination, reason: .file(String(describing: error))))
                }
            }
        }
        do {
            try index.update(paths: updated.union(candidates).union(newFiles).union([path, newPath]), vaultRoot: root)
        } catch {
            failures.append(RenameFailure(path: newPath, reason: .index(String(describing: error))))
        }
        return RenameResult(path: newPath, updatedFiles: updated.sorted(), failures: failures)
    }
}
