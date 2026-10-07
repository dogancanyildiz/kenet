import Foundation
import GRDB
import VaultFormat

extension VaultIndex {
    /// Scans the vault and atomically replaces only files whose content changed.
    @discardableResult
    public func refresh(vaultRoot: URL) throws -> RebuildResult {
        try incrementallyUpdate(vaultRoot: vaultRoot, paths: nil)
    }

    /// Updates notified vault-relative or absolute paths, including directory descendants.
    @discardableResult
    public func update(paths: Set<String>, vaultRoot: URL) throws -> RebuildResult {
        try incrementallyUpdate(vaultRoot: vaultRoot, paths: paths)
    }

    private func incrementallyUpdate(vaultRoot: URL, paths: Set<String>?) throws -> RebuildResult {
        try validate(vaultRoot: vaultRoot)
        let customKinds = Set(EntityTypeReader.read(vaultRoot: vaultRoot).types.map(\.id))
        let signature = customKinds.sorted().joined(separator: "\n")
        let resolvedRoot = vaultRoot.resolvingSymlinksInPath()
        let notifications = paths.map { notified in
            notified.compactMap { notification(for: $0, root: resolvedRoot) }
        }
        let requested = notifications.map { notes in Set(notes.map(\.includeKey)) }
        func includes(_ path: String) -> Bool {
            let key = comparisonKey(path)
            return requested.map { prefixes in
                prefixes.contains { $0.isEmpty || key == $0 || key.hasPrefix($0 + "/") }
            } ?? true
        }
        return try database.write { db in
            let typeChanged =
                (try String.fetchOne(db, sql: "SELECT signature FROM entity_type_state") ?? "") != signature
            let isEmpty = try Bool.fetchOne(db, sql: "SELECT EXISTS(SELECT 1 FROM files)") == false
            if typeChanged || (paths == nil && isEmpty) {
                return try rebuild(vaultRoot: vaultRoot, customKinds: customKinds, db: db)
            }
            let old = try IndexedFile.fetchAll(db, sql: "SELECT * FROM files ORDER BY path")
            let scopes: Set<ScanScope> = {
                guard let notes = notifications else { return [.full] }
                // Case-/normalization-insensitive includes can match indexed paths whose
                // on-disk parents were not opened by the notification spelling. Add those
                // parents (and any sibling spellings that share the comparison key) so
                // deleted ⊆ actually scanned.
                return scopesCoveringIndexedPaths(
                    base: Set(notes.map(\.scope)),
                    indexedPaths: old.map(\.path),
                    includes: includes,
                    directorySpellings: { physicalDirectorySpellings(of: $0, root: resolvedRoot) })
            }()
            let scan = try VaultScanner.scan(vaultRoot, scopes: scopes)
            let previous = Dictionary(uniqueKeysWithValues: old.map { ($0.path, $0) })
            let present = Set(scan.files.map(\.path))
            let deleted = old.map(\.path).filter { includes($0) && !present.contains($0) }
            var added: [String] = []
            var updated: [String] = []
            var keys: Set<String> = []
            var identifiers: Set<String> = []
            for path in deleted {
                try remove(path, db: db, keys: &keys, identifiers: &identifiers)
            }
            for file in scan.files where includes(file.path) {
                let metadata = try file.url.resourceValues(forKeys: [.contentModificationDateKey, .fileSizeKey])
                let modified = metadata.contentModificationDate?.timeIntervalSince1970 ?? 0
                if let before = previous[file.path], before.modified == modified,
                    before.size == metadata.fileSize
                {
                    continue
                }
                let data = try readFile(file.url)
                if let before = previous[file.path], before.digest == ByteDigest.hex(data) {
                    // Cache the observed metadata without rewriting any source-derived rows.
                    try db.execute(
                        sql: "UPDATE files SET modified=?,size=? WHERE path=?",
                        arguments: [modified, data.count, file.path])
                    continue
                }
                if previous[file.path] != nil {
                    try remove(file.path, db: db, keys: &keys, identifiers: &identifiers)
                    updated.append(file.path)
                } else {
                    added.append(file.path)
                }
                keys.formUnion(targetKeys(file.path))
                let document = RawDocument(bytes: data)
                var owners = Set(document.bodyLines.tasks.compactMap { $0.block.id })
                owners.formUnion(document.bodyLines.events.compactMap { $0.block.id })
                identifiers.formUnion(owners)
                // Ownership is assigned after all removals and inserts, in global source order.
                try IndexBuilder.insert(
                    file: file.path, data: data, document: document, modified: modified, db: db, owners: &owners,
                    customKinds: customKinds)
                if document.isValidUTF8 {
                    try IndexBuilder.insertLinks(document: document, file: file.path, db: db)
                }
            }
            try repairOwnership(identifiers, db: db)
            try repairLinks(keys: keys, sources: added + updated, db: db)
            try db.execute(sql: "DELETE FROM entity_type_state")
            try db.execute(sql: "INSERT INTO entity_type_state VALUES (?)", arguments: [signature])
            return RebuildResult(
                addedPaths: added, updatedPaths: updated, deletedPaths: deleted,
                skippedPaths: scan.result.skippedPaths.filter {
                    includes($0.path.precomposedStringWithCanonicalMapping)
                })
        }
    }
}

private func targetKeys(_ path: String) -> Set<String> {
    let stem = String(path.dropLast(3))
    return [comparisonKey(stem), comparisonKey((stem as NSString).lastPathComponent)]
}

private func remove(_ path: String, db: Database, keys: inout Set<String>, identifiers: inout Set<String>) throws {
    keys.formUnion(targetKeys(path))
    identifiers.formUnion(
        try String.fetchAll(
            db, sql: "SELECT identifier FROM blocks WHERE file=? AND identifier IS NOT NULL", arguments: [path]))
    try db.execute(sql: "UPDATE links SET resolvedFile=NULL WHERE resolvedFile=?", arguments: [path])
    for table in ["search", "links", "goal_logs", "aliases", "entities", "blocks"] {
        try db.execute(sql: "DELETE FROM " + table + " WHERE file=?", arguments: [path])
    }
    try db.execute(sql: "DELETE FROM files WHERE path=?", arguments: [path])
}

private func repairOwnership(_ identifiers: Set<String>, db: Database) throws {
    for identifier in identifiers.sorted(by: codePointLess) {
        try db.execute(
            sql: "UPDATE blocks SET ownsIdentifier=0 WHERE identifier=? AND ownsIdentifier=1", arguments: [identifier])
        try db.execute(
            sql: """
                UPDATE blocks SET ownsIdentifier=1 WHERE (file,ordinal) =
                (SELECT file,ordinal FROM blocks WHERE identifier=? ORDER BY file,ordinal LIMIT 1)
                """, arguments: [identifier])
    }
}

private func repairLinks(keys: Set<String>, sources: [String], db: Database) throws {
    guard !keys.isEmpty || !sources.isEmpty else { return }
    var names: [String: String] = [:]
    var paths: [String: String] = [:]
    for file in try String.fetchAll(db, sql: "SELECT path FROM files ORDER BY path") {
        let stem = String(file.dropLast(3))
        let key = comparisonKey((stem as NSString).lastPathComponent)
        if names[key] == nil { names[key] = file }
        if paths[comparisonKey(stem)] == nil { paths[comparisonKey(stem)] = file }
    }
    // targetKey also includes already-resolved links: a new duplicate can become the first candidate.
    // Bound each insert to one parameter, regardless of the number of changed files.
    // Temporary tables are created and removed inside the caller's transaction.
    try db.execute(
        sql: """
            CREATE TEMP TABLE affected_link_keys (key TEXT PRIMARY KEY);
            CREATE TEMP TABLE affected_link_sources (file TEXT PRIMARY KEY);
            """)
    for key in keys.sorted(by: codePointLess) {
        try db.execute(sql: "INSERT INTO affected_link_keys VALUES (?)", arguments: [key])
    }
    for source in sources {
        try db.execute(sql: "INSERT INTO affected_link_sources VALUES (?)", arguments: [source])
    }
    let links = try IndexedLink.fetchAll(
        db,
        sql: """
            SELECT * FROM links WHERE targetKey IN (SELECT key FROM affected_link_keys)
            OR file IN (SELECT file FROM affected_link_sources)
            """)
    for link in links {
        let resolved = link.target.isEmpty ? link.file : (link.target.contains("/") ? paths : names)[link.targetKey]
        if resolved != link.resolvedFile {
            try db.execute(
                sql: "UPDATE links SET resolvedFile=? WHERE file=? AND ordinal=?",
                arguments: [resolved, link.file, link.ordinal])
        }
    }
    try db.execute(sql: "DROP TABLE temp.affected_link_keys; DROP TABLE temp.affected_link_sources")
}

private struct Notification {
    /// Comparison key used by `includes` (may widen to a missing ancestor directory).
    let includeKey: String
    let scope: ScanScope
}

private func notification(for path: String, root: URL) -> Notification? {
    let base = root.path.precomposedStringWithCanonicalMapping
    let url = path.hasPrefix("/") ? URL(fileURLWithPath: path) : root.appendingPathComponent(path)
    let absolute = resolvedNotificationPath(url).precomposedStringWithCanonicalMapping
    guard
        comparisonKey(absolute) == comparisonKey(base)
            || comparisonKey(absolute).hasPrefix(comparisonKey(base) + "/")
    else { return nil }
    let relative =
        comparisonKey(absolute) == comparisonKey(base) ? "" : String(absolute.dropFirst(base.count + 1))
    let components = relative.split(separator: "/").map(String.init)
    guard !components.dropLast().contains(where: { $0.hasPrefix(".") }),
        components.first != "templates", components.first != "conflicts",
        !(components.last?.hasPrefix(".") == true && !relative.hasSuffix(".md"))
    else { return nil }
    let nfc = relative.precomposedStringWithCanonicalMapping
    // Hidden directories are skipped by the scanner even when the name ends in `.md`.
    if let last = components.last, last.hasPrefix(".") {
        var isDirectory: ObjCBool = false
        if FileManager.default.fileExists(
            atPath: root.appendingPathComponent(nfc).path, isDirectory: &isDirectory),
            isDirectory.boolValue
        {
            return nil
        }
    }
    return Notification(includeKey: includeKey(for: nfc, root: root), scope: scanScope(for: nfc, root: root))
}

/// Adds shallow scopes for exact-cased (and comparison-key sibling) parents of matching
/// indexed paths so a case-/NFC-insensitive include cannot delete files that were never scanned.
func scopesCoveringIndexedPaths(
    base: Set<ScanScope>,
    indexedPaths: [String],
    includes: (String) -> Bool,
    directorySpellings: (String) -> [String]
) -> Set<ScanScope> {
    var scopes = base
    var parents: Set<String> = []
    for path in indexedPaths where includes(path) {
        let parent = (path as NSString).deletingLastPathComponent
        parents.insert(parent == "." ? "" : parent)
    }
    for parent in parents {
        for spelling in directorySpellings(parent) {
            scopes.insert(.shallow(spelling))
        }
    }
    return scopes
}

/// Every on-disk directory spelling whose components match `relative` by comparison key.
func physicalDirectorySpellings(of relative: String, root: URL) -> [String] {
    if relative.isEmpty { return [""] }
    var candidates = [""]
    for component in relative.split(separator: "/").map(String.init) {
        let key = comparisonKey(component)
        var next: [String] = []
        for parent in candidates {
            next.append(contentsOf: matchingDirectoryChildren(parentRelative: parent, nameKey: key, root: root))
        }
        if next.isEmpty { return [] }
        candidates = next
    }
    return candidates
}

private func matchingDirectoryChildren(parentRelative: String, nameKey: String, root: URL) -> [String] {
    let parentURL = parentRelative.isEmpty ? root : root.appendingPathComponent(parentRelative)
    var isDirectory: ObjCBool = false
    guard FileManager.default.fileExists(atPath: parentURL.path, isDirectory: &isDirectory),
        isDirectory.boolValue
    else { return [] }
    guard
        let urls = try? FileManager.default.contentsOfDirectory(
            at: parentURL, includingPropertiesForKeys: [.isDirectoryKey, .isSymbolicLinkKey])
    else { return [] }
    var matches: [String] = []
    for url in urls {
        guard comparisonKey(url.lastPathComponent) == nameKey else { continue }
        let values = try? url.resourceValues(forKeys: [.isDirectoryKey, .isSymbolicLinkKey])
        var directory = values?.isDirectory == true
        if values?.isSymbolicLink == true {
            var linkedDirectory: ObjCBool = false
            _ = FileManager.default.fileExists(atPath: url.path, isDirectory: &linkedDirectory)
            directory = linkedDirectory.boolValue
        }
        guard directory, values?.isSymbolicLink != true else { continue }
        let relative =
            parentRelative.isEmpty ? url.lastPathComponent : parentRelative + "/" + url.lastPathComponent
        matches.append(relative)
    }
    return matches
}

/// Widens a missing intermediate directory so its indexed subtree can be dropped.
private func includeKey(for relative: String, root: URL) -> String {
    let key = comparisonKey(relative)
    if relative.isEmpty { return key }
    var prefix = ""
    for component in relative.split(separator: "/").map(String.init) {
        let next = prefix.isEmpty ? component : prefix + "/" + component
        var isDirectory: ObjCBool = false
        if !FileManager.default.fileExists(atPath: root.appendingPathComponent(next).path, isDirectory: &isDirectory) {
            // Intermediate directory gone: drop the whole missing prefix from the index.
            if next != relative { return comparisonKey(next) }
            return key
        }
        prefix = next
    }
    return key
}

private func scanScope(for relative: String, root: URL) -> ScanScope {
    if relative.isEmpty { return .full }
    let url = root.appendingPathComponent(relative)
    var isDirectory: ObjCBool = false
    if FileManager.default.fileExists(atPath: url.path, isDirectory: &isDirectory) {
        if isDirectory.boolValue { return .subtree(relative) }
        let parent = (relative as NSString).deletingLastPathComponent
        return .shallow(parent == "." ? "" : parent)
    }
    // Missing path: scan the nearest existing ancestor one level so siblings remain visible.
    var prefix = ""
    for component in relative.split(separator: "/").map(String.init) {
        let next = prefix.isEmpty ? component : prefix + "/" + component
        var isDirectory: ObjCBool = false
        if !FileManager.default.fileExists(atPath: root.appendingPathComponent(next).path, isDirectory: &isDirectory) {
            return .shallow(prefix)
        }
        if !isDirectory.boolValue {
            return .shallow(prefix)
        }
        prefix = next
    }
    let parent = (relative as NSString).deletingLastPathComponent
    return .shallow(parent == "." ? "" : parent)
}

// Resolve only an existing directory: Foundation standardization treats missing /private paths differently.
private func resolvedNotificationPath(_ url: URL) -> String {
    var components: [String] = []
    for component in url.pathComponents where component != "/" && component != "." {
        if component == ".." {
            if !components.isEmpty { components.removeLast() }
        } else {
            components.append(component)
        }
    }
    var ancestor = URL(fileURLWithPath: "/" + components.joined(separator: "/"))
    var tail: [String] = []
    while true {
        var isDirectory: ObjCBool = false
        if FileManager.default.fileExists(atPath: ancestor.path, isDirectory: &isDirectory), isDirectory.boolValue {
            break
        }
        let parent = ancestor.deletingLastPathComponent()
        guard parent.path != ancestor.path else { break }
        tail.append(ancestor.lastPathComponent)
        ancestor = parent
    }
    var resolved = ancestor.resolvingSymlinksInPath()
    for component in tail.reversed() { resolved.appendPathComponent(component) }
    return resolved.path
}
