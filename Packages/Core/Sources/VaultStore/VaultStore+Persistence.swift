import Foundation
import VaultFormat

extension VaultStore {
    nonisolated func persist(_ document: RawDocument, path: String, exclusive: Bool = false) throws {
        let url = try checkedURL(path, writing: true)
        try atomicWrite(Data(document.serialized()), to: url, exclusive: exclusive)
        do {
            try index.update(paths: [path], vaultRoot: root)
        } catch {
            throw VaultStoreError.indexUpdateFailed(path: path, underlying: error)
        }
    }

    nonisolated func atomicWrite(_ bytes: Data, to url: URL, exclusive: Bool) throws {
        let manager = FileManager.default
        let directory = url.deletingLastPathComponent()
        try manager.createDirectory(at: directory, withIntermediateDirectories: true)
        let temporary = directory.appendingPathComponent(".vault-store-" + UUID().uuidString)
        defer { try? manager.removeItem(at: temporary) }
        try bytes.write(to: temporary, options: .withoutOverwriting)
        if !exclusive, manager.fileExists(atPath: url.path) {
            // Default replacement retains the destination's permissions and extended attributes.
            _ = try manager.replaceItemAt(url, withItemAt: temporary)
        } else {
            // Linking a complete sibling publishes atomically and never overwrites another process's file.
            do {
                try manager.linkItem(at: temporary, to: url)
            } catch CocoaError.fileWriteFileExists {
                throw VaultStoreError.nameTaken
            }
        }
    }
}
