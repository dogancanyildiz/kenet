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
        let requested = paths.map { notified in
            Set(notified.compactMap { notificationPath($0, root: vaultRoot) })
        }
        func includes(_ path: String) -> Bool {
            let key = comparisonKey(path)
            return requested.map { prefixes in
                prefixes.contains { $0.isEmpty || key == $0 || key.hasPrefix($0 + "/") }
            } ?? true
        }
        return try database.write { db in
            let scan = try VaultScanner.scan(vaultRoot)
            let old = try IndexedFile.fetchAll(db, sql: "SELECT * FROM files ORDER BY path")
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
                if let before = previous[file.path], before.modified == modified, before.size == metadata.fileSize {
                    continue
                }
                let data = try Data(contentsOf: file.url)
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
                    file: file.path, data: data, document: document, modified: modified, db: db, owners: &owners)
                if document.isValidUTF8 {
                    try IndexBuilder.insertLinks(document: document, file: file.path, db: db)
                }
            }
            try repairOwnership(identifiers, db: db)
            try repairLinks(keys: keys, sources: added + updated, db: db)
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

private func notificationPath(_ path: String, root: URL) -> String? {
    let base = root.standardizedFileURL.path.precomposedStringWithCanonicalMapping
    let url = path.hasPrefix("/") ? URL(fileURLWithPath: path) : root.appendingPathComponent(path)
    let absolute = url.standardizedFileURL.path.precomposedStringWithCanonicalMapping
    guard
        comparisonKey(absolute) == comparisonKey(base)
            || comparisonKey(absolute).hasPrefix(comparisonKey(base) + "/")
    else { return nil }
    let relative = comparisonKey(absolute) == comparisonKey(base) ? "" : String(absolute.dropFirst(base.count + 1))
    let components = relative.split(separator: "/").map(String.init)
    guard !components.dropLast().contains(where: { $0.hasPrefix(".") }),
        components.first != "templates", components.first != "conflicts",
        !(components.last?.hasPrefix(".") == true && !relative.hasSuffix(".md"))
    else { return nil }
    return comparisonKey(relative)
}
