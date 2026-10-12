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
        let parent = path.split(separator: "/").dropLast().joined(separator: "/")
        let newPath = (parent.isEmpty ? "" : parent + "/") + stem + ".md"
        let targetURL = try checkedURL(newPath, writing: true)
        guard try !filenameIsTaken(stem, excluding: path) else { throw VaultStoreError.nameTaken }
        let files = try markdownPaths()
        let newFiles = Set(files).subtracting(try index.files().map(\.path))
        let candidates = Set(try index.links(to: path).map(\.file))
        let targets = RenameTargets(oldPath: path, newPath: newPath, files: files)
        let operation: FileCoordinationOperation =
            path.utf8.elementsEqual(newPath.utf8)
            ? .modify(sourceURL) : .move(source: sourceURL, destination: targetURL)
        let primary: (changed: Bool, failure: RenameResult?) = try fileCoordination.coordinate(operation) { access in
            try rejectPendingDownload(at: targetURL, path: newPath)
            let original = RawDocument(bytes: try readFile(sourceURL))
            guard case .parsed(let frontmatter) = original.frontmatter,
                case .scalar(let type) = frontmatter.field(named: "type")?.value,
                ["person", "place"].contains(type.text) || customDefinition(type.text) != nil
            else { throw VaultStoreError.staleTarget }
            var changed = try original.settingFrontmatterValue(.text(name), forKey: "name")
            if let qualifier {
                changed = try changed.settingFrontmatterValue(.text(qualifier), forKey: "qualifier")
            } else {
                changed = try changed.removingFrontmatterField(forKey: "qualifier")
            }
            if changed != original { try atomicWrite(Data(changed.serialized()), to: sourceURL, exclusive: false) }
            if !path.utf8.elementsEqual(newPath.utf8) {
                access.itemWillMove(from: sourceURL, to: targetURL)
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
                        return (true, RenameResult(path: path, updatedFiles: [path], failures: failures))
                    }
                    _ = try? index.update(paths: [path, newPath], vaultRoot: root)
                    if FileManager.default.fileExists(atPath: targetURL.path) { throw VaultStoreError.nameTaken }
                    throw moveError
                }
                access.itemDidMove(from: sourceURL, to: targetURL)
            }
            return (changed != original, nil)
        }
        if let failure = primary.failure { return failure }
        var updated: Set<String> = primary.changed || path != newPath ? [newPath] : []
        var failures: [RenameFailure] = []
        let sources =
            path.utf8.elementsEqual(newPath.utf8) ? [] : updateSources(files, candidates, targets, path, newPath)
        for source in sources {
            let destination = source == path ? newPath : source
            do {
                let url = try checkedURL(destination, writing: true)
                try fileCoordination.coordinate(.modify(url)) { _ in
                    let document = RawDocument(bytes: try readFile(url))
                    if document.isReadOnly && !candidates.contains(source) { return }
                    let rewrite = try RenameDocument.rewrite(
                        document, targets: targets, eligible: candidates.contains(source))
                    if rewrite.document != document {
                        try atomicWrite(Data(rewrite.document.serialized()), to: url, exclusive: false)
                        updated.insert(destination)
                    }
                    failures += rewrite.rawFields.map { RenameFailure(path: destination, reason: .rawField($0)) }
                    failures += rewrite.listFailures.map {
                        RenameFailure(
                            path: destination,
                            reason: .frontmatterList(key: $0.key, reason: $0.reason))
                    }
                }
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

    /// The files the update pass claims, in path order: every indexed link source, plus any other
    /// file whose claimed pass would report something. Such a file is never rewritten (it is not
    /// eligible); it can only report a raw frontmatter field naming the old file, which deliberately
    /// has no link row. A plain read finds those, and the claimed pass then reads them again; a file
    /// that cannot be read or checked here is claimed, as before.
    private nonisolated func updateSources(
        _ files: [String], _ candidates: Set<String>, _ targets: RenameTargets, _ path: String, _ newPath: String
    ) -> [String] {
        Set(files).union(candidates).sorted().filter { source in
            if candidates.contains(source) { return true }
            guard let url = try? checkedURL(source == path ? newPath : source, writing: true),
                let bytes = try? readFile(url)
            else { return true }
            let document = RawDocument(bytes: bytes)
            if document.isReadOnly { return false }
            guard let rewrite = try? RenameDocument.rewrite(document, targets: targets, eligible: false) else {
                return true
            }
            return !rewrite.rawFields.isEmpty
        }
    }
}
