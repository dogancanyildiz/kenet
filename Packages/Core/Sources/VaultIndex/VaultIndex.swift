import Foundation
import GRDB
import VaultFormat

/// A disposable SQLite index rebuilt atomically from Markdown files.
public struct VaultIndex: Sendable {
    private let database: DatabaseQueue
    private let databaseURL: URL?

    /// Opens an in-memory index, or a caller-supplied database outside the vault.
    public init(databaseURL: URL? = nil) throws {
        self.databaseURL = databaseURL
        database = try IndexDatabase.open(databaseURL)
    }

    /// Replaces all indexed content in one transaction. A failure leaves the previous content intact.
    @discardableResult
    public func rebuild(vaultRoot: URL) throws -> RebuildResult {
        if let databaseURL {
            let root = vaultRoot.resolvingSymlinksInPath().standardizedFileURL.path
            let path = databaseURL.resolvingSymlinksInPath().standardizedFileURL.path
            guard path != root && !path.hasPrefix(root + "/") else { throw VaultIndexError.databaseInsideVault }
        }
        return try database.write { db in
            for table in ["search", "links", "goal_logs", "aliases", "entities", "blocks", "files"] {
                try db.execute(sql: "DELETE FROM " + table)
            }
            let scan = try VaultScanner.scan(vaultRoot)
            let files = scan.files
            var owners: Set<String> = []
            var names: [String: String] = [:]
            var paths: [String: String] = [:]
            for file in files {
                let stem = String(file.path.dropLast(3))
                let basename = (stem as NSString).lastPathComponent
                if names[comparisonKey(basename)] == nil { names[comparisonKey(basename)] = file.path }
                if paths[comparisonKey(stem)] == nil { paths[comparisonKey(stem)] = file.path }
                let data = try Data(contentsOf: file.url)
                let document = RawDocument(bytes: data)
                let metadata = try file.url.resourceValues(forKeys: [.contentModificationDateKey])
                try IndexBuilder.insert(
                    file: file.path, data: data, document: document,
                    modified: metadata.contentModificationDate?.timeIntervalSince1970 ?? 0,
                    db: db, owners: &owners)
                if document.isValidUTF8 {
                    try IndexBuilder.insertLinks(document: document, file: file.path, db: db)
                }
            }
            let links = try Row.fetchCursor(
                db, sql: "SELECT file,ordinal,target,targetKey FROM links ORDER BY file,ordinal")
            while let link = try links.next() {
                let file: String = link["file"]
                let ordinal: Int = link["ordinal"]
                let target: String = link["target"]
                let targetKey: String = link["targetKey"]
                let resolved = target.isEmpty ? file : (target.contains("/") ? paths : names)[targetKey]
                try db.execute(
                    sql: "UPDATE links SET resolvedFile=? WHERE file=? AND ordinal=?",
                    arguments: [resolved, file, ordinal])
            }
            return scan.result
        }
    }

    /// Lists files in Unicode code point path order.
    public func files() throws -> [IndexedFile] {
        try database.read { try IndexedFile.fetchAll($0, sql: "SELECT * FROM files ORDER BY path") }
    }

    /// Reads a day's blocks in source order.
    public func blocks(on date: CalendarDate) throws -> [IndexedBlock] {
        try database.read {
            try IndexedBlock.fetchAll(
                $0,
                sql: "SELECT b.* FROM blocks b JOIN files f ON f.path=b.file WHERE f.date=? ORDER BY b.file,b.ordinal",
                arguments: [date.description])
        }
    }

    /// Finds all entities whose name or alias matches the locale-independent comparison key.
    public func entities(named name: String) throws -> [IndexedEntity] {
        try database.read {
            try IndexedEntity.fetchAll(
                $0,
                sql: """
                    SELECT * FROM entities WHERE comparisonKey=? OR file IN
                    (SELECT file FROM aliases WHERE comparisonKey=?) ORDER BY file
                    """, arguments: [comparisonKey(name), comparisonKey(name)])
        }
    }

    /// Lists incoming links to a normalized vault-relative file path.
    public func links(to path: String) throws -> [IndexedLink] {
        try database.read {
            try IndexedLink.fetchAll(
                $0, sql: "SELECT * FROM links WHERE resolvedFile=? ORDER BY file,ordinal",
                arguments: [path.precomposedStringWithCanonicalMapping])
        }
    }

    /// Lists links whose target is absent from the scanned vault.
    public func unresolvedLinks() throws -> [IndexedLink] {
        try database.read {
            try IndexedLink.fetchAll($0, sql: "SELECT * FROM links WHERE resolvedFile IS NULL ORDER BY file,ordinal")
        }
    }

    /// Searches user text as quoted terms, allowing a prefix match on the final term.
    public func search(_ text: String) throws -> [SearchMatch] {
        guard let expression = searchExpression(text) else { return [] }
        return try database.read {
            try SearchMatch.fetchAll(
                $0, sql: "SELECT file,block,text FROM search WHERE search MATCH ? ORDER BY rank,file,block,text",
                arguments: [expression])
        }
    }

    /// Lists source goal values, optionally restricted to a goal key.
    public func goalLogs(key: String? = nil) throws -> [IndexedGoalLog] {
        try database.read {
            try IndexedGoalLog.fetchAll(
                $0, sql: "SELECT * FROM goal_logs WHERE ? IS NULL OR key=? ORDER BY file,key", arguments: [key, key])
        }
    }

    /// Exports the deterministic, source-derived index for cross-platform verification.
    public func snapshot() throws -> IndexSnapshot {
        try database.read { db in
            IndexSnapshot(
                files: try IndexedFile.fetchAll(db, sql: "SELECT * FROM files ORDER BY path").map {
                    IndexSnapshot.File(path: $0.path, kind: $0.kind, date: $0.date, readable: $0.readable)
                },
                entities: try IndexedEntity.fetchAll(db, sql: "SELECT * FROM entities ORDER BY file"),
                aliases: try IndexedAlias.fetchAll(db, sql: "SELECT * FROM aliases ORDER BY file,ordinal"),
                blocks: try IndexedBlock.fetchAll(db, sql: "SELECT * FROM blocks ORDER BY file,ordinal"),
                links: try IndexedLink.fetchAll(db, sql: "SELECT * FROM links ORDER BY file,ordinal"),
                goalLogs: try IndexedGoalLog.fetchAll(db, sql: "SELECT * FROM goal_logs ORDER BY file,key"))
        }
    }
}
