import GRDB

extension VaultIndex {
    /// Lists entity scalars in file/key order, optionally restricted to scalar kinds.
    /// A nil filter returns every kind; an empty filter returns no rows.
    public func entityFields(kinds: Set<String>? = nil) throws -> [IndexedEntityField] {
        if let kinds, kinds.isEmpty { return [] }
        return try database.read { db in
            let sorted = kinds?.sorted()
            let clause =
                sorted.map {
                    " WHERE kind IN (" + Array(repeating: "?", count: $0.count).joined(separator: ",") + ")"
                } ?? ""
            return try IndexedEntityField.fetchAll(
                db, sql: "SELECT * FROM entity_fields" + clause + " ORDER BY file,key",
                arguments: StatementArguments(sorted ?? []))
        }
    }
}
