import Foundation

extension VaultStore {
    nonisolated func checkedURL(_ path: String, writing: Bool = false) throws -> URL {
        let parts = path.split(separator: "/", omittingEmptySubsequences: false)
        guard !parts.isEmpty, path.hasSuffix(".md"),
            parts.allSatisfy({ !$0.isEmpty && !$0.hasPrefix(".") })
        else { throw VaultStoreError.invalidPath }
        if writing, ["templates", "conflicts"].contains(String(parts[0])) {
            throw VaultStoreError.invalidPath
        }
        var url = root
        for part in parts {
            url.appendPathComponent(String(part))
            if (try? url.resourceValues(forKeys: [.isSymbolicLinkKey]).isSymbolicLink) == true {
                throw VaultStoreError.invalidPath
            }
        }
        return url
    }

    /// Current disk identities, using the same hidden/reserved/symlink exclusions as indexing.
    nonisolated func markdownPaths() throws -> [String] {
        var paths: [String] = []
        func visit(_ directory: URL, prefix: String) throws {
            for url in try FileManager.default.contentsOfDirectory(
                at: directory, includingPropertiesForKeys: [.isDirectoryKey, .isSymbolicLinkKey])
            {
                let name = url.lastPathComponent
                let values = try url.resourceValues(forKeys: [.isDirectoryKey, .isSymbolicLinkKey])
                guard !name.hasPrefix("."), values.isSymbolicLink != true,
                    !(prefix.isEmpty && ["templates", "conflicts"].contains(name))
                else { continue }
                let path = prefix + name
                if values.isDirectory == true {
                    try visit(url, prefix: path + "/")
                } else if name.hasSuffix(".md") {
                    paths.append(path.precomposedStringWithCanonicalMapping)
                }
            }
        }
        try visit(root, prefix: "")
        return paths.sorted { $0.unicodeScalars.lexicographicallyPrecedes($1.unicodeScalars) { $0.value < $1.value } }
    }

    nonisolated func filenameIsTaken(_ name: String, excluding path: String? = nil) throws -> Bool {
        let key = storeComparisonKey(name)
        if try index.files().contains(where: {
            $0.path != path
                && storeComparisonKey(String(URL(fileURLWithPath: $0.path).lastPathComponent.dropLast(3))).utf8
                    .elementsEqual(
                        key.utf8)
        }) {
            return true
        }
        nonisolated func visit(_ directory: URL, isRoot: Bool) throws -> Bool {
            for url in try FileManager.default.contentsOfDirectory(
                at: directory, includingPropertiesForKeys: [.isDirectoryKey, .isSymbolicLinkKey])
            {
                let name = url.lastPathComponent
                let values = try url.resourceValues(forKeys: [.isDirectoryKey, .isSymbolicLinkKey])
                if name.hasPrefix(".") || (isRoot && ["templates", "conflicts"].contains(name)) { continue }
                if url.resolvingSymlinksInPath().standardizedFileURL.path.precomposedStringWithCanonicalMapping
                    != path.map({
                        root.appendingPathComponent($0).resolvingSymlinksInPath().standardizedFileURL.path
                            .precomposedStringWithCanonicalMapping
                    }),
                    name.hasSuffix(".md"), storeComparisonKey(String(name.dropLast(3))).utf8.elementsEqual(key.utf8)
                {
                    return true
                }
                if values.isSymbolicLink != true, values.isDirectory == true, try visit(url, isRoot: false) {
                    return true
                }
            }
            return false
        }
        return try visit(root, isRoot: true)
    }
}

func storeComparisonKey(_ text: String) -> String {
    text.precomposedStringWithCanonicalMapping.lowercased().precomposedStringWithCanonicalMapping
}
