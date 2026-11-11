import Foundation
import VaultIndex

/// The in-memory index Core's writer updates after a write from the widget or the share extension.
///
/// Core rebuilds an empty index from the whole vault before it updates one file: seconds and
/// megabytes on a five-year vault, more than an extension has, and all of it inside the day file's
/// coordinated write. So the index starts from a stand-in vault of one empty note and the vault's
/// own entity types (`.app/types.json`, which Core compares): the update after the write then reads
/// the written file alone. Should the stand-in fail, the empty index still writes correctly, only
/// slower. Nothing reads this index afterwards; the app rescans the files it names.
/// `readFile` is the index's file reader; tests count its reads.
enum ThrowawayIndex {
    static func make(
        for root: URL, readFile: @escaping @Sendable (URL) throws -> Data = { try Data(contentsOf: $0) }
    ) throws -> VaultIndex {
        let index = try VaultIndex(readFile: readFile)
        let manager = FileManager.default
        let standIn = manager.temporaryDirectory.appendingPathComponent(
            "throwaway-index-" + UUID().uuidString, isDirectory: true)
        defer { try? manager.removeItem(at: standIn) }
        do {
            let app = standIn.appendingPathComponent(".app", isDirectory: true)
            try manager.createDirectory(at: app, withIntermediateDirectories: true)
            let types = root.appendingPathComponent(".app/types.json")
            if manager.fileExists(atPath: types.path) {
                try Data(contentsOf: types).write(to: app.appendingPathComponent("types.json"))
            }
            try Data().write(to: standIn.appendingPathComponent("stand-in.md"))
            try index.rebuild(vaultRoot: standIn)
        } catch {
            return try VaultIndex(readFile: readFile)
        }
        return index
    }
}
