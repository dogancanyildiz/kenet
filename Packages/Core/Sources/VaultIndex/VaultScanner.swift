import Foundation

/// Index-specific failures; filesystem and database failures retain their underlying errors.
public enum VaultIndexError: Error, Sendable {
    /// A persistent index must live outside the vault.
    case databaseInsideVault
}

/// The outcome of an atomic index operation, including normalized changed paths.
public struct RebuildResult: Sendable, Equatable {
    public let addedPaths: [String]
    public let updatedPaths: [String]
    public let deletedPaths: [String]
    public let skippedPaths: [SkippedPath]

    init(
        addedPaths: [String] = [], updatedPaths: [String] = [], deletedPaths: [String] = [],
        skippedPaths: [SkippedPath]
    ) {
        self.addedPaths = addedPaths
        self.updatedPaths = updatedPaths
        self.deletedPaths = deletedPaths
        self.skippedPaths = skippedPaths
    }
}

/// A physical vault-relative path that was skipped without aborting the rebuild.
public struct SkippedPath: Sendable, Equatable {
    /// Why the physical path was excluded.
    public enum Reason: String, Sendable {
        case symbolicLink
        case duplicateNormalizedPath
    }
    public let path: String
    public let reason: Reason
}

struct ScannedFile: Sendable {
    let url: URL
    let path: String
    let physicalPath: String
}

enum VaultScanner {
    static func scan(_ root: URL) throws -> (files: [ScannedFile], result: RebuildResult) {
        var files: [ScannedFile] = []
        var skipped: [SkippedPath] = []
        func visit(_ directory: URL, prefix: String) throws {
            for url in try FileManager.default.contentsOfDirectory(
                at: directory, includingPropertiesForKeys: [.isDirectoryKey, .isSymbolicLinkKey])
            {
                let values = try url.resourceValues(forKeys: [.isDirectoryKey, .isSymbolicLinkKey])
                let name = url.lastPathComponent
                let path = prefix + name
                var directory = values.isDirectory == true
                if values.isSymbolicLink == true {
                    var isDirectory: ObjCBool = false
                    _ = FileManager.default.fileExists(atPath: url.path, isDirectory: &isDirectory)
                    directory = isDirectory.boolValue
                }
                if directory
                    && (name.hasPrefix(".") || (prefix.isEmpty && (name == "templates" || name == "conflicts")))
                {
                    continue
                }
                if values.isSymbolicLink == true {
                    guard directory || name.hasSuffix(".md") else { continue }
                    skipped.append(SkippedPath(path: path, reason: .symbolicLink))
                    continue
                }
                if values.isDirectory == true {
                    if name.hasPrefix(".") || (prefix.isEmpty && (name == "templates" || name == "conflicts")) {
                        continue
                    }
                    try visit(url, prefix: path + "/")
                } else if name.hasSuffix(".md") {
                    files.append(
                        ScannedFile(url: url, path: path.precomposedStringWithCanonicalMapping, physicalPath: path))
                }
            }
        }
        try visit(root, prefix: "")
        files = deduplicate(files, skipped: &skipped)
        skipped.sort { $0.path.utf8.lexicographicallyPrecedes($1.path.utf8) }
        return (files, RebuildResult(addedPaths: files.map(\.path), skippedPaths: skipped))
    }

    static func deduplicate(_ candidates: [ScannedFile], skipped: inout [SkippedPath]) -> [ScannedFile] {
        var files = candidates
        files.sort {
            if Array($0.path.utf8) != Array($1.path.utf8) { return codePointLess($0.path, $1.path) }
            return $0.physicalPath.utf8.lexicographicallyPrecedes($1.physicalPath.utf8)
        }
        var seen: Set<String> = []
        files = files.filter { file in
            if seen.insert(file.path).inserted { return true }
            skipped.append(SkippedPath(path: file.physicalPath, reason: .duplicateNormalizedPath))
            return false
        }
        return files
    }

}

func comparisonKey(_ text: String) -> String {
    text.precomposedStringWithCanonicalMapping.lowercased().precomposedStringWithCanonicalMapping
}

func codePointLess(_ lhs: String, _ rhs: String) -> Bool {
    lhs.unicodeScalars.lexicographicallyPrecedes(rhs.unicodeScalars) { $0.value < $1.value }
}

func normalizedLinkTarget(_ target: String) -> String {
    var path = target
    while path.hasPrefix("/") || path.hasPrefix("./") {
        path.removeFirst(path.hasPrefix("./") ? 2 : 1)
    }
    return path
}
