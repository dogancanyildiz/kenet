import GRDB
import Summaries

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

    /// The cadence scalars of person files, in file/key order. Text and other kinds are not indexed.
    /// The key names live in `PersonCadence.keys` only.
    public func cadenceFields() throws -> [IndexedEntityField] {
        try database.read { db in
            try IndexedEntityField.fetchAll(
                db,
                sql: """
                    SELECT entity_fields.file, entity_fields.key, entity_fields.kind, entity_fields.value
                    FROM entity_fields JOIN entities ON entities.file = entity_fields.file
                    WHERE entities.kind = 'person' AND entity_fields.key IN (\(Self.cadenceKeyMarks))
                    ORDER BY entity_fields.file, entity_fields.key
                    """, arguments: StatementArguments(PersonCadence.keys))
        }
    }

    /// Date scalars on people and custom types, in file/key order. Place files are not anniversaries.
    /// The cadence keys never are, in any file: `cadence_snoozed_until` is a date but not an occasion.
    public func anniversaryFields() throws -> [IndexedEntityField] {
        try database.read { db in
            try IndexedEntityField.fetchAll(
                db,
                sql: """
                    SELECT entity_fields.file, entity_fields.key, entity_fields.kind, entity_fields.value
                    FROM entity_fields JOIN files ON files.path = entity_fields.file
                    WHERE entity_fields.kind = 'date' AND files.kind <> 'place'
                      AND entity_fields.key NOT IN (\(Self.cadenceKeyMarks))
                    ORDER BY entity_fields.file, entity_fields.key
                    """, arguments: StatementArguments(PersonCadence.keys))
        }
    }

    private static var cadenceKeyMarks: String {
        Array(repeating: "?", count: PersonCadence.keys.count).joined(separator: ",")
    }
}
