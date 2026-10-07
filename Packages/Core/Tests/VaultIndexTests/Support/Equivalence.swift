import Foundation
import GRDB
import Testing

@testable import VaultIndex

func equivalent(_ index: VaultIndex, _ root: URL) throws {
    let rebuilt = try VaultIndex()
    try rebuilt.rebuild(vaultRoot: root)
    #expect(try index.snapshot() == rebuilt.snapshot())
    let sql = "SELECT file,block,text FROM search ORDER BY file,block,text"
    let actualSearch = try index.database.read { try SearchMatch.fetchAll($0, sql: sql) }
    let expectedSearch = try rebuilt.database.read { try SearchMatch.fetchAll($0, sql: sql) }
    #expect(actualSearch == expectedSearch)
    // FTS is deliberately absent from the portable snapshot; compare its actual results too.
    for query in ["Su", "Kitap", "Deniz", "Selin", "Spor", "devam"] {
        #expect(try index.search(query) == rebuilt.search(query))
    }
}
