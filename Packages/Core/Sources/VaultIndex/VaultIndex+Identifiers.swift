import GRDB

extension VaultIndex {
    /// Lists every occupied block identifier, including duplicates.
    public func blockIdentifiers() throws -> Set<String> {
        try database.read {
            Set(try String.fetchAll($0, sql: "SELECT DISTINCT identifier FROM blocks WHERE identifier IS NOT NULL"))
        }
    }

    /// Returns the source-order owner of an identifier, if indexed.
    public func owner(of identifier: String) throws -> IndexedBlock? {
        try database.read {
            try IndexedBlock.fetchOne(
                $0, sql: "SELECT * FROM blocks WHERE identifier=? AND ownsIdentifier=1", arguments: [identifier])
        }
    }
}
