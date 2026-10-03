import GRDB

/// A full-text match with source information for navigation and a bounded excerpt.
public struct SearchResult: Codable, FetchableRecord, Sendable, Equatable {
    public let file: String
    public let block: Int?
    public let text: String
    public let fileKind: String
    public let blockKind: String?
    public let date: String?
}

extension VaultIndex {
    /// Uses the same literal-term query builder and tokenizer as `search(_:)`.
    public func searchResults(_ text: String) throws -> [SearchResult] {
        guard let expression = searchExpression(text) else { return [] }
        return try database.read {
            try SearchResult.fetchAll(
                $0,
                sql: """
                    SELECT search.file, search.block,
                        snippet(search, 2, '', '', '…', 32) AS text,
                        f.kind AS fileKind, b.kind AS blockKind, f.date
                    FROM search JOIN files f ON f.path = search.file
                    LEFT JOIN blocks b ON b.file = search.file AND b.ordinal = search.block
                    WHERE search MATCH ?
                    ORDER BY rank, search.file, search.block, search.text
                    """, arguments: [expression])
        }
    }
}
