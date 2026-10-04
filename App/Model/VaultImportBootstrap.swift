import Foundation
import VaultFormat

/// Only creates missing structural files; existing files are never replaced.
enum VaultImportBootstrap {
    static func checked(_ path: String, root: URL) throws -> URL {
        var url = root
        for part in path.split(separator: "/") {
            guard part != "..", part != "." else { throw CocoaError(.fileWriteInvalidFileName) }
            url.appendPathComponent(String(part))
            if (try? url.resourceValues(forKeys: [.isSymbolicLinkKey]).isSymbolicLink) == true {
                throw CocoaError(.fileWriteNoPermission)
            }
        }
        return url
    }
    static func directory(_ path: String, root: URL) throws -> Bool {
        let url = try checked(path, root: root)
        if FileManager.default.fileExists(atPath: url.path) {
            guard try url.resourceValues(forKeys: [.isDirectoryKey]).isDirectory == true else {
                throw CocoaError(.fileWriteFileExists)
            }
            return false
        }
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return true
    }
    static func file(_ path: String, bytes: Data, root: URL) throws -> Bool {
        let url = try checked(path, root: root)
        if FileManager.default.fileExists(atPath: url.path) { return false }
        _ = try directory(String(path.split(separator: "/").dropLast().joined(separator: "/")), root: root)
        let temporary = url.deletingLastPathComponent().appendingPathComponent(".vault-import-" + UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: temporary) }
        try bytes.write(to: temporary, options: .withoutOverwriting)
        do { try FileManager.default.linkItem(at: temporary, to: url) } catch {
            if FileManager.default.fileExists(atPath: url.path) { return false }
            try bytes.write(to: url, options: .withoutOverwriting)
        }
        return true
    }
    static func template(_ kind: String) throws -> Data {
        var document = try RawDocument(bytes: []).settingFrontmatterValue(.text(kind), forKey: "type")
        let key = kind == "person" ? String(localized: "Tanışma") : String(localized: "Adres")
        document = try document.settingFrontmatterValue(.text(""), forKey: key)
        return Data(document.serialized())
    }
}
