import GRDB

/// The disposable index schema. Any incompatible version is erased, never migrated.
enum IndexSchema {
    static let version = 4
    static func prepare(_ database: DatabaseQueue) throws {
        let actual = try database.read { try Int.fetchOne($0, sql: "PRAGMA user_version") ?? 0 }
        guard actual != version else { return }
        try database.erase()
        try database.write { try create($0) }
    }

    private static func create(_ db: Database) throws {
        try db.execute(
            sql: """
                CREATE TABLE files (
                    path TEXT PRIMARY KEY, kind TEXT NOT NULL, date TEXT, modified REAL NOT NULL,
                    size INTEGER NOT NULL, digest TEXT NOT NULL, readable BOOLEAN NOT NULL);
                CREATE INDEX file_dates ON files(date);
                CREATE TABLE entities (
                    file TEXT PRIMARY KEY REFERENCES files(path), kind TEXT NOT NULL, name TEXT NOT NULL,
                    qualifier TEXT, comparisonKey TEXT NOT NULL, goalKey TEXT, period TEXT,
                    goalKind TEXT, target TEXT, unit TEXT);
                CREATE INDEX entity_names ON entities(comparisonKey);
                CREATE TABLE aliases (
                    file TEXT NOT NULL REFERENCES entities(file), ordinal INTEGER NOT NULL,
                    name TEXT NOT NULL, comparisonKey TEXT NOT NULL, PRIMARY KEY(file, ordinal));
                CREATE INDEX alias_names ON aliases(comparisonKey);
                CREATE TABLE blocks (
                    file TEXT NOT NULL REFERENCES files(path), ordinal INTEGER NOT NULL,
                    kind TEXT NOT NULL, firstLine INTEGER NOT NULL, lastLine INTEGER NOT NULL,
                    text TEXT NOT NULL, section TEXT NOT NULL, time TEXT, status TEXT, rawStatus TEXT,
                    identifier TEXT, headingLevel INTEGER, ownsIdentifier BOOLEAN NOT NULL,
                    dueDate TEXT, startDate TEXT, doneDate TEXT, priority TEXT, project TEXT, recurrence TEXT, PRIMARY KEY(file, ordinal));
                CREATE INDEX task_due_dates ON blocks(dueDate);
                CREATE INDEX task_done_dates ON blocks(doneDate);
                CREATE UNIQUE INDEX identifier_owners ON blocks(identifier) WHERE ownsIdentifier = 1;
                CREATE TABLE links (
                    file TEXT NOT NULL REFERENCES files(path), ordinal INTEGER NOT NULL, block INTEGER,
                    line INTEGER NOT NULL, byteStart INTEGER NOT NULL, byteEnd INTEGER NOT NULL,
                    key TEXT, entry TEXT, target TEXT NOT NULL, targetKey TEXT NOT NULL, anchorKind TEXT, anchor TEXT,
                    displayText TEXT, embedded BOOLEAN NOT NULL, resolvedFile TEXT REFERENCES files(path),
                    PRIMARY KEY(file, ordinal), FOREIGN KEY(file, block) REFERENCES blocks(file, ordinal));
                CREATE INDEX link_targets ON links(targetKey);
                CREATE INDEX incoming_links ON links(resolvedFile);
                CREATE TABLE goal_logs (
                    file TEXT NOT NULL REFERENCES files(path), key TEXT NOT NULL, date TEXT NOT NULL,
                    kind TEXT NOT NULL, value TEXT NOT NULL, PRIMARY KEY(file, key));
                CREATE INDEX goal_keys ON goal_logs(key);
                CREATE VIRTUAL TABLE search USING fts5(file UNINDEXED, block UNINDEXED, text,
                    tokenize = 'unicode61 remove_diacritics 0');
                PRAGMA user_version = \(version);
                """)
    }
}
