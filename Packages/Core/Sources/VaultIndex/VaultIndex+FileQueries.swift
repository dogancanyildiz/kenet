import GRDB
import VaultFormat

extension VaultIndex {
    /// Source-ordered blocks for one vault-relative Markdown path.
    public func blocks(inFile path: String) throws -> [IndexedBlock] {
        let path = path.precomposedStringWithCanonicalMapping
        return try database.read {
            try IndexedBlock.fetchAll(
                $0, sql: "SELECT * FROM blocks WHERE file=? ORDER BY ordinal", arguments: [path])
        }
    }

    /// Source-ordered links for one vault-relative Markdown path.
    public func links(inFile path: String) throws -> [IndexedLink] {
        let path = path.precomposedStringWithCanonicalMapping
        return try database.read {
            try IndexedLink.fetchAll(
                $0, sql: "SELECT * FROM links WHERE file=? ORDER BY ordinal", arguments: [path])
        }
    }

    /// All indexed rows for one file, or `nil` when the path is absent from `files`.
    public func contents(ofFile path: String) throws -> IndexedFileContents? {
        let path = path.precomposedStringWithCanonicalMapping
        return try database.read { db in
            guard
                let file = try IndexedFile.fetchOne(
                    db, sql: "SELECT * FROM files WHERE path=?", arguments: [path])
            else { return nil }
            return IndexedFileContents(
                file: IndexSnapshot.File(
                    path: file.path, kind: file.kind, date: file.date, readable: file.readable),
                entity: try IndexedEntity.fetchOne(
                    db, sql: "SELECT * FROM entities WHERE file=?", arguments: [path]),
                aliases: try IndexedAlias.fetchAll(
                    db, sql: "SELECT * FROM aliases WHERE file=? ORDER BY ordinal", arguments: [path]),
                blocks: try IndexedBlock.fetchAll(
                    db, sql: "SELECT * FROM blocks WHERE file=? ORDER BY ordinal", arguments: [path]),
                links: try IndexedLink.fetchAll(
                    db, sql: "SELECT * FROM links WHERE file=? ORDER BY ordinal", arguments: [path]),
                goalLogs: try IndexedGoalLog.fetchAll(
                    db, sql: "SELECT * FROM goal_logs WHERE file=? ORDER BY key", arguments: [path]))
        }
    }
}

/// Per-file slice of the portable index snapshot.
public struct IndexedFileContents: Sendable, Equatable {
    public let file: IndexSnapshot.File
    public let entity: IndexedEntity?
    public let aliases: [IndexedAlias]
    public let blocks: [IndexedBlock]
    public let links: [IndexedLink]
    public let goalLogs: [IndexedGoalLog]

    public init(
        file: IndexSnapshot.File, entity: IndexedEntity?, aliases: [IndexedAlias],
        blocks: [IndexedBlock], links: [IndexedLink], goalLogs: [IndexedGoalLog]
    ) {
        self.file = file
        self.entity = entity
        self.aliases = aliases
        self.blocks = blocks
        self.links = links
        self.goalLogs = goalLogs
    }
}
