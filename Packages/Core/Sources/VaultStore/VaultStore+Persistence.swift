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
                try linkFile(temporary, url)
            } catch {
                if isExistingFileError(error) { throw VaultStoreError.nameTaken }
                // Some external vault filesystems cannot hard-link. Keep exclusive creation there,
                // accepting a non-atomic initial write rather than overwriting another process's file.
                do {
                    try bytes.write(to: url, options: .withoutOverwriting)
                } catch {
                    if isExistingFileError(error) { throw VaultStoreError.nameTaken }
                    throw error
                }
            }
        }
    }
}

private func isExistingFileError(_ error: any Error) -> Bool {
    let error = error as NSError
    if error.domain == NSCocoaErrorDomain, error.code == CocoaError.fileWriteFileExists.rawValue { return true }
    if error.domain == NSPOSIXErrorDomain, error.code == Int(POSIXErrorCode.EEXIST.rawValue) { return true }
    if let underlying = error.userInfo[NSUnderlyingErrorKey] as? any Error {
        return isExistingFileError(underlying)
    }
    return false
}
