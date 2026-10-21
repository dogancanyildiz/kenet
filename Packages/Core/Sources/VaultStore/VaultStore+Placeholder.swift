import Foundation
import VaultFormat
import VaultIndex

extension VaultStore {
    /// Throws `awaitingDownload` when the missing target has a placeholder sibling.
    ///
    /// Siblings match by the vault's name collision rule (``NameCollision``), not by the file system:
    /// a case-sensitive volume would otherwise let `selin.md` be created beside `.Selin.md.icloud`. The error carries
    /// the placeholder's original spelling so the host can request exactly that download.
    /// Called inside the operation's coordination boundary, before anything is written.
    nonisolated func rejectPendingDownload(at url: URL, path: String) throws {
        guard !FileManager.default.fileExists(atPath: url.path) else { return }
        let directory = url.deletingLastPathComponent()
        var isDirectory: ObjCBool = false
        guard FileManager.default.fileExists(atPath: directory.path, isDirectory: &isDirectory), isDirectory.boolValue
        else { return }
        let collision = NameCollision(url.lastPathComponent)
        let names = try FileManager.default.contentsOfDirectory(atPath: directory.path).sorted {
            $0.utf8.lexicographicallyPrecedes($1.utf8)
        }
        guard
            let original = names.lazy.compactMap(PlaceholderName.originalName(ofPlaceholder:)).first(where: {
                collision.matches($0)
            })
        else { return }
        let parent = (path as NSString).deletingLastPathComponent
        throw VaultStoreError.awaitingDownload(path: parent.isEmpty ? original : parent + "/" + original)
    }
}
