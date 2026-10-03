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

    nonisolated func filenameIsTaken(_ name: String) throws -> Bool {
        let key = storeComparisonKey(name)
        if try index.files().contains(where: {
            storeComparisonKey(String(URL(fileURLWithPath: $0.path).lastPathComponent.dropLast(3))).utf8.elementsEqual(
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
                if name.hasSuffix(".md"), storeComparisonKey(String(name.dropLast(3))).utf8.elementsEqual(key.utf8) {
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
