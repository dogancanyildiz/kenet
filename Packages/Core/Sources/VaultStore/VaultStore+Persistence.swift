import Foundation
import VaultFormat

extension VaultStore {
    /// Called inside the operation’s coordination boundary; never starts nested coordination.
    nonisolated func persist(_ document: RawDocument, path: String, exclusive: Bool = false) throws {
        let url = try checkedURL(path, writing: true)
        try atomicWrite(Data(document.serialized()), to: url, exclusive: exclusive)
        do {
            try index.update(paths: [path], vaultRoot: root)
        } catch {
            throw VaultStoreError.indexUpdateFailed(path: path, underlying: error)
        }
    }

    /// `synchronize` and `renameExclusively` are seams for tests; production callers use the defaults.
    nonisolated func atomicWrite(
        _ bytes: Data, to url: URL, exclusive: Bool,
        synchronize: (FileHandle) throws -> Void = { try $0.synchronize() },
        renameExclusively: (URL, URL) throws -> Void = renameWithoutReplacing
    ) throws {
        let manager = FileManager.default
        let directory = url.deletingLastPathComponent()
        try manager.createDirectory(at: directory, withIntermediateDirectories: true)
        let temporary = directory.appendingPathComponent(".vault-store-" + UUID().uuidString)
        defer { try? manager.removeItem(at: temporary) }
        try bytes.write(to: temporary, options: .withoutOverwriting)
        // Flush the complete bytes before any name points at them, so a crash cannot publish a partial file.
        try synchronizeFile(at: temporary, using: synchronize)
        if !exclusive, manager.fileExists(atPath: url.path) {
            // Default replacement retains the destination's permissions and extended attributes.
            _ = try manager.replaceItemAt(url, withItemAt: temporary)
        } else {
            // Linking a complete sibling publishes atomically and never overwrites another process's file.
            do {
                try linkFile(temporary, url)
            } catch {
                if isExistingFileError(error) { throw VaultStoreError.nameTaken }
                // Some external vault filesystems cannot hard-link. An exclusive rename still publishes
                // the complete sibling atomically without overwriting another process's file.
                do {
                    try renameExclusively(temporary, url)
                } catch {
                    if isExistingFileError(error) { throw VaultStoreError.nameTaken }
                    // Without exclusive rename either, keep exclusive creation and accept a
                    // non-atomic initial write rather than overwriting another process's file.
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
}

private func synchronizeFile(at url: URL, using synchronize: (FileHandle) throws -> Void) throws {
    let handle = try FileHandle(forWritingTo: url)
    defer { try? handle.close() }
    try synchronize(handle)
}

/// Renames `source` to `destination` only when `destination` does not exist yet.
func renameWithoutReplacing(_ source: URL, _ destination: URL) throws {
    #if canImport(Darwin)
        // errno is captured right after the call, before the path buffers are released.
        let outcome = source.withUnsafeFileSystemRepresentation { from in
            destination.withUnsafeFileSystemRepresentation { to -> (result: Int32, code: Int32)? in
                guard let from, let to else { return nil }
                let result = renamex_np(from, to, UInt32(RENAME_EXCL))
                return (result, result == 0 ? 0 : errno)
            }
        }
        guard let outcome else { throw CocoaError(.fileWriteInvalidFileName) }
        guard outcome.result == 0 else { throw POSIXError(POSIXErrorCode(rawValue: outcome.code) ?? .EIO) }
    #else
        throw CocoaError(.featureUnsupported)
    #endif
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
