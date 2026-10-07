import Foundation
import GRDB

/// A scanned Markdown file; invalid UTF-8 is recorded without content rows.
public struct IndexedFile: Codable, FetchableRecord, Sendable, Equatable {
    public let path: String
    public let kind: String
    public let date: String?
    public let modified: Double
    public let size: Int
    public let digest: String
    public let readable: Bool
}

/// A named person, place or goal, with its source fields.
public struct IndexedEntity: Codable, FetchableRecord, Sendable, Equatable {
    public let file: String
    public let kind: String
    public let name: String
    public let qualifier: String?
    public let comparisonKey: String
    public let goalKey: String?
    public let period: String?
    public let goalKind: String?
    public let target: String?
    public let unit: String?
}

/// A source alias, in frontmatter order.
public struct IndexedAlias: Codable, FetchableRecord, Sendable, Equatable {
    public let file: String
    public let ordinal: Int
    public let name: String
    public let comparisonKey: String
}

/// A source block; line numbers are one-based and inclusive.
public struct IndexedBlock: Codable, FetchableRecord, Sendable, Equatable {
    public let file: String
    public let ordinal: Int
    public let kind: String
    public let firstLine: Int
    public let lastLine: Int
    public let text: String
    public let section: String
    public let time: String?
    public let status: String?
    public let rawStatus: String?
    public let identifier: String?
    public let headingLevel: Int?
    public let ownsIdentifier: Bool
    public let dueDate: String?
    public let startDate: String?
    public let doneDate: String?
    public let priority: String?
    public let project: String?
    public let recurrence: String?
}

/// A wikilink with its physical source and optional resolved file.
public struct IndexedLink: Codable, FetchableRecord, Sendable, Equatable {
    public let file: String
    public let ordinal: Int
    public let block: Int?
    public let line: Int
    public let byteStart: Int
    public let byteEnd: Int
    public let key: String?
    public let entry: String?
    public let target: String
    public let targetKey: String
    public let anchorKind: String?
    public let anchor: String?
    public let displayText: String?
    public let embedded: Bool
    public let resolvedFile: String?
}

/// A day frontmatter goal value, preserving its source spelling.
public struct IndexedGoalLog: Codable, FetchableRecord, Sendable, Equatable {
    public let file: String
    public let key: String
    public let date: String
    public let kind: String
    public let value: String
}

/// A full-text match in a block, entity name or alias.
public struct SearchMatch: Codable, FetchableRecord, Sendable, Equatable {
    public let file: String
    public let block: Int?
    public let text: String
}

/// A portable, ordered snapshot, excluding filesystem metadata and digests.
public struct IndexSnapshot: Codable, Sendable, Equatable {
    /// The source-derived file identity and classification.
    public struct File: Codable, Sendable, Equatable {
        public let path: String
        public let kind: String
        public let date: String?
        public let readable: Bool

        public init(path: String, kind: String, date: String?, readable: Bool) {
            self.path = path
            self.kind = kind
            self.date = date
            self.readable = readable
        }
    }
    public let files: [File]
    public let entities: [IndexedEntity]
    public let aliases: [IndexedAlias]
    public let blocks: [IndexedBlock]
    public let links: [IndexedLink]
    public let goalLogs: [IndexedGoalLog]

    public init(
        files: [File], entities: [IndexedEntity], aliases: [IndexedAlias], blocks: [IndexedBlock],
        links: [IndexedLink], goalLogs: [IndexedGoalLog]
    ) {
        self.files = files
        self.entities = entities
        self.aliases = aliases
        self.blocks = blocks
        self.links = links
        self.goalLogs = goalLogs
    }
}
