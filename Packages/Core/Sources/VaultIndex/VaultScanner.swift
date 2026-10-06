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

/// How much of the vault a scan should walk.
enum ScanScope: Hashable, Sendable {
    /// Walk the entire vault (same as today's `scan`).
    case full
    /// Recursively walk one vault-relative directory (empty string = vault root).
    case subtree(String)
    /// List one vault-relative directory without descending (empty string = vault root).
    case shallow(String)
}

enum VaultScanner {
    /// Test seam: when set, counts directories entered and directory entries examined.
    /// Prefer `@TaskLocal` so parallel tests do not share counters.
    @TaskLocal static var visitProbe: VisitProbe?

    final class VisitProbe: @unchecked Sendable {
        var directories = 0
        var entries = 0
    }

    static func scan(_ root: URL, scopes: Set<ScanScope> = [.full]) throws -> (
        files: [ScannedFile], result: RebuildResult
    ) {
        var files: [ScannedFile] = []
        var skipped: [SkippedPath] = []
        let resolved = normalizeScopes(scopes)
        if resolved.contains(.full) {
            try visit(root, prefix: "", recursive: true, files: &files, skipped: &skipped)
        } else {
            for scope in resolved.sorted(by: scopeOrder) {
                switch scope {
                case .full:
                    break
                case .subtree(let relative):
                    let directory = relative.isEmpty ? root : root.appendingPathComponent(relative)
                    try visit(
                        directory, prefix: relative.isEmpty ? "" : relative + "/", recursive: true, files: &files,
                        skipped: &skipped)
                case .shallow(let relative):
                    let directory = relative.isEmpty ? root : root.appendingPathComponent(relative)
                    var isDirectory: ObjCBool = false
                    guard FileManager.default.fileExists(atPath: directory.path, isDirectory: &isDirectory),
                        isDirectory.boolValue
                    else { continue }
                    try visit(
                        directory, prefix: relative.isEmpty ? "" : relative + "/", recursive: false, files: &files,
                        skipped: &skipped)
                }
            }
        }
        files = deduplicate(files, skipped: &skipped)
        skipped.sort { $0.path.utf8.lexicographicallyPrecedes($1.path.utf8) }
        return (files, RebuildResult(addedPaths: files.map(\.path), skippedPaths: skipped))
    }

    private static func visit(
        _ directory: URL, prefix: String, recursive: Bool, files: inout [ScannedFile], skipped: inout [SkippedPath]
    ) throws {
        visitProbe?.directories += 1
        for url in try FileManager.default.contentsOfDirectory(
            at: directory, includingPropertiesForKeys: [.isDirectoryKey, .isSymbolicLinkKey])
        {
            visitProbe?.entries += 1
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
                if recursive {
                    try visit(url, prefix: path + "/", recursive: true, files: &files, skipped: &skipped)
                }
            } else if name.hasSuffix(".md") {
                files.append(
                    ScannedFile(url: url, path: path.precomposedStringWithCanonicalMapping, physicalPath: path))
            }
        }
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

/// Collapse overlapping scopes: full wins; a subtree covers shallows and nested subtrees under it.
private func normalizeScopes(_ scopes: Set<ScanScope>) -> Set<ScanScope> {
    if scopes.contains(.full) { return [.full] }
    var subtrees: [String] = []
    var shallows: [String] = []
    for scope in scopes {
        switch scope {
        case .full:
            return [.full]
        case .subtree(let path):
            subtrees.append(path)
        case .shallow(let path):
            shallows.append(path)
        }
    }
    subtrees = minimalPrefixes(subtrees)
    let coveredShallows = shallows.filter { shallow in
        !subtrees.contains { subtree in
            subtree.isEmpty || shallow == subtree || shallow.hasPrefix(subtree + "/")
        }
    }
    var result: Set<ScanScope> = Set(subtrees.map { ScanScope.subtree($0) })
    result.formUnion(coveredShallows.map { ScanScope.shallow($0) })
    return result
}

private func minimalPrefixes(_ paths: [String]) -> [String] {
    let sorted = paths.sorted {
        if $0.count != $1.count { return $0.count < $1.count }
        return codePointLess($0, $1)
    }
    var kept: [String] = []
    for path in sorted {
        if kept.contains(where: { $0.isEmpty || path == $0 || path.hasPrefix($0 + "/") }) { continue }
        kept.append(path)
    }
    return kept
}

private func scopeOrder(_ lhs: ScanScope, _ rhs: ScanScope) -> Bool {
    func key(_ scope: ScanScope) -> (Int, String) {
        switch scope {
        case .full: return (0, "")
        case .subtree(let path): return (1, path)
        case .shallow(let path): return (2, path)
        }
    }
    let left = key(lhs)
    let right = key(rhs)
    if left.0 != right.0 { return left.0 < right.0 }
    return codePointLess(left.1, right.1)
}
