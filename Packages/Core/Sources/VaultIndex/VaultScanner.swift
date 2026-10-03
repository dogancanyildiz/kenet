import Foundation

/// Index-specific failures; filesystem and database failures retain their underlying errors.
public enum VaultIndexError: Error, Sendable {
    /// Two physical files normalize to the same vault path.
    case duplicateNormalizedPath(String)
    /// Symbolic links are rejected so traversal cannot escape the vault or cycle.
    case symbolicLink(String)
    /// A persistent index must live outside the vault.
    case databaseInsideVault
}

struct ScannedFile: Sendable {
    let url: URL
    let path: String
}

enum VaultScanner {
    static func scan(_ root: URL) throws -> [ScannedFile] {
        var files: [ScannedFile] = []
        func visit(_ directory: URL, prefix: String) throws {
            for url in try FileManager.default.contentsOfDirectory(
                at: directory, includingPropertiesForKeys: [.isDirectoryKey, .isSymbolicLinkKey])
            {
                let values = try url.resourceValues(forKeys: [.isDirectoryKey, .isSymbolicLinkKey])
                let name = url.lastPathComponent
                let path = prefix + name
                if values.isDirectory == true {
                    if name.hasPrefix(".") || name == "templates" || name == "conflicts" { continue }
                    guard values.isSymbolicLink != true else { throw VaultIndexError.symbolicLink(path) }
                    try visit(url, prefix: path + "/")
                } else if name.hasSuffix(".md") {
                    guard values.isSymbolicLink != true else { throw VaultIndexError.symbolicLink(path) }
                    files.append(ScannedFile(url: url, path: path.precomposedStringWithCanonicalMapping))
                }
            }
        }
        try visit(root, prefix: "")
        files.sort { codePointLess($0.path, $1.path) }
        var seen: Set<String> = []
        for file in files {
            guard seen.insert(file.path).inserted else { throw VaultIndexError.duplicateNormalizedPath(file.path) }
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
