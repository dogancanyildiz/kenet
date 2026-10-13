import Foundation
import GRDB

extension VaultIndex {
    /// Indexed entity copies (`EntityCopyName`): a copy is any indexed file whose original is an
    /// indexed entity file in the same folder. Copies stay indexed as their own files; this only lists them.
    public func entityCopies() throws -> [CopyFile] {
        try database.read { db in
            let paths = try String.fetchAll(db, sql: "SELECT path FROM files")
            let entities = try String.fetchAll(db, sql: "SELECT file FROM entities")
            return EntityCopyName.copies(in: paths, originals: entities)
        }
    }

    /// Day copies directly under the exact `journal/` folder on disk, in `DayCopyName.copies` merge
    /// order. They are never indexed, so this lists that one folder instead of reading the index.
    public static func dayCopies(vaultRoot: URL) throws -> [CopyFile] {
        let names = try FileManager.default.contentsOfDirectory(atPath: vaultRoot.path)
        // Only the exact spelling: on a case-insensitive volume `Journal/` would also open as `journal`.
        guard names.contains("journal") else { return [] }
        return try VaultScanner.scan(vaultRoot, scopes: [.shallow("journal")]).result.dayCopies.compactMap { copy in
            DayCopyName.dayPath(ofCopy: copy).map { CopyFile(folder: "journal", copy: copy, original: $0) }
        }
    }
}
