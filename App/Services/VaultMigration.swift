import CryptoKit
import Foundation

/// A verified copy is published by renaming a sibling directory. The source is never removed.
struct VaultMigration: Sendable {
    struct Result: Sendable {
        let opened: URL
        let copied: URL
        var openedExistingVault: Bool { opened != copied }
    }

    /// Fault injection exercises verification against incomplete and corrupt copies.
    var copyDirectory: @Sendable (URL, URL) throws -> Void = {
        try FileManager.default.copyItem(at: $0, to: $1)
    }

    func copy(source: URL, container: URL, temporaryName: String, deviceName: String) throws -> Result {
        let documents = container.appendingPathComponent("Documents", isDirectory: true)
        try FileManager.default.createDirectory(at: documents, withIntermediateDirectories: true)
        let coordinator = NSFileCoordinator()
        var coordinationError: NSError?
        var outcome: Swift.Result<Result, any Error>?
        coordinator.coordinate(
            readingItemAt: source, options: .withoutChanges,
            writingItemAt: documents, options: .forMerging, error: &coordinationError
        ) { source, documents in
            outcome = Swift.Result {
                try copyCoordinated(
                    source: source, documents: documents, temporaryName: temporaryName, deviceName: deviceName)
            }
        }
        if let coordinationError { throw coordinationError }
        guard let outcome else { throw CocoaError(.fileWriteUnknown) }
        return try outcome.get()
    }

    private func copyCoordinated(
        source: URL, documents: URL, temporaryName: String, deviceName: String
    ) throws -> Result {
        let manager = FileManager.default
        let temporary = documents.appendingPathComponent(temporaryName, isDirectory: true)
        let canonical = documents.appendingPathComponent("Kenet", isDirectory: true)
        let before = try inventory(source)
        try copyDirectory(source, temporary)
        // Includes hidden files, empty directories, sizes and content digests, not just Markdown.
        guard try inventory(temporary) == before, try inventory(source) == before else {
            throw CocoaError(.fileWriteUnknown)
        }
        var destination = canonical
        let existing = manager.fileExists(atPath: canonical.path)
        if existing {
            guard manager.fileExists(atPath: canonical.appendingPathComponent(".app/vault.json").path)
            else { throw CocoaError(.fileReadUnknown) }
            let name = "Kenet-" + Self.safeDeviceName(deviceName)
            destination = documents.appendingPathComponent(name, isDirectory: true)
            var suffix = 2
            while manager.fileExists(atPath: destination.path) {
                destination = documents.appendingPathComponent(name + "-" + String(suffix), isDirectory: true)
                suffix += 1
            }
        }
        // moveItem fails if another process has claimed the destination; it never replaces it.
        try manager.moveItem(at: temporary, to: destination)
        return Result(opened: existing ? canonical : destination, copied: destination)
    }

    static func safeDeviceName(_ name: String) -> String {
        let allowed = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "-_"))
        let cleaned = name.unicodeScalars.map { allowed.contains($0) ? String($0) : "-" }.joined()
        let trimmed = cleaned.trimmingCharacters(in: CharacterSet(charactersIn: "-_"))
        return trimmed.isEmpty ? "Device" : String(trimmed.prefix(60))
    }

    private struct Entry: Equatable {
        let bytes: Int
        let digest: String
    }

    private func inventory(_ root: URL) throws -> [String: Entry] {
        let manager = FileManager.default
        guard try root.resourceValues(forKeys: [.isSymbolicLinkKey]).isSymbolicLink != true else {
            throw CocoaError(.fileReadUnknown)
        }
        var result: [String: Entry] = [:]
        func walk(_ directory: URL, relative: String) throws {
            for url in try manager.contentsOfDirectory(
                at: directory, includingPropertiesForKeys: [.isDirectoryKey, .isRegularFileKey, .isSymbolicLinkKey])
            {
                let path = relative + url.lastPathComponent
                let values = try url.resourceValues(forKeys: [.isDirectoryKey, .isRegularFileKey, .isSymbolicLinkKey])
                // A link could escape the source or change while copying. Placeholders are not file bytes.
                guard values.isSymbolicLink != true, !url.lastPathComponent.hasSuffix(".icloud") else {
                    throw CocoaError(.fileReadUnknown)
                }
                if values.isDirectory == true {
                    result[path + "/"] = Entry(bytes: 0, digest: "")
                    try walk(url, relative: path + "/")
                } else {
                    guard values.isRegularFile == true else { throw CocoaError(.fileReadUnknown) }
                    let bytes = try Data(contentsOf: url, options: .mappedIfSafe)
                    result[path] = Entry(bytes: bytes.count, digest: SHA256.hash(data: bytes).description)
                }
            }
        }
        try walk(root, relative: "")
        return result
    }
}
