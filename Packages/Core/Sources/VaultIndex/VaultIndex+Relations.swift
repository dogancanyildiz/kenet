import GRDB

/// A resolved, directed frontmatter relation. Paths are vault-relative.
public struct Relation: Codable, FetchableRecord, Hashable, Sendable {
    public let source: String
    public let target: String
    public let label: String?
    public let sourceName: String
    public let targetName: String
    public let targetKind: String
}

extension VaultIndex {
    public func relations(of path: String) throws -> (outgoing: [Relation], incoming: [Relation]) {
        let all = try relationRows(path: path)
        return (all.filter { $0.source == path }, all.filter { $0.target == path })
    }

    /// One edge per unordered pair, regardless of direction or label.
    /// The first row in source/target/label order supplies its display metadata.
    public func explicitRelations(kinds: Set<String>) throws -> [Relation] {
        guard !kinds.isEmpty else { return [] }
        let rows = try relationRows(kinds: kinds)
        var seen: Set<[String]> = []
        return rows.filter {
            seen.insert([$0.source, $0.target].sorted()).inserted
        }
    }

    /// Every explicit relation label in the vault, unique and sorted by `<`; `related` is unlabeled.
    /// Unlike `explicitRelations(kinds:)`, no label is dropped when a pair has several.
    public func relationLabels() throws -> [String] {
        Array(Set(try relationRows().compactMap(\.label))).sorted()
    }

    private func relationRows(path: String? = nil, kinds: Set<String>? = nil) throws -> [Relation] {
        let sorted = kinds?.sorted() ?? []
        let marks = Array(repeating: "?", count: sorted.count).joined(separator: ",")
        let filter =
            (kinds == nil ? "" : " AND s.kind IN (" + marks + ") AND f.kind IN (" + marks + ")")
            + (path == nil ? "" : " AND (l.file=? OR l.resolvedFile=?)")
        let arguments = sorted + sorted + (path.map { [$0, $0] } ?? [])
        return try database.read { db in
            try Relation.fetchAll(
                db,
                sql: """
                    SELECT DISTINCT l.file AS source, l.resolvedFile AS target,
                        CASE WHEN l.key='related' THEN NULL ELSE l.key END AS label,
                        s.name AS sourceName, t.name AS targetName, f.kind AS targetKind
                    FROM links l JOIN entities s ON s.file=l.file
                    JOIN files f ON f.path=l.resolvedFile
                    JOIN entities t ON t.file=l.resolvedFile
                    WHERE s.kind <> 'goal' AND t.kind <> 'goal' AND l.file <> l.resolvedFile
                      AND l.block IS NULL AND l.key IS NOT NULL AND l.entry IS NULL
                      AND l.key NOT IN ('type','name','qualifier','aliases')
                    \(filter)
                    ORDER BY source,target,label
                    """, arguments: StatementArguments(arguments))
        }
    }
}
