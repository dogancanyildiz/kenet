import Foundation
import GRDB
import VaultFormat

/// A body wikilink in another file resolving to a target day.
public struct DayBacklink: Codable, FetchableRecord, Sendable, Equatable, Identifiable, Hashable {
    public let file: String
    public let kind: String
    public let name: String
    public let text: String
    public let line: Int

    public var id: String { "\(file):\(line)" }

    public init(file: String, kind: String, name: String, text: String, line: Int) {
        self.file = file
        self.kind = kind
        self.name = name
        self.text = text
        self.line = line
    }
}

extension VaultIndex {
    /// Lists incoming body wikilinks resolving to `day`, excluding `day`'s own file.
    public func dayBacklinks(for day: CalendarDate) throws -> [DayBacklink] {
        try database.read { db in
            let rows = try Row.fetchAll(
                db,
                sql: """
                    SELECT DISTINCT l.file, l.line, f.kind AS fileKind, f.date AS fileDate,
                           e.name AS entityName, e.qualifier AS entityQualifier,
                           b.firstLine, b.lastLine, b.text AS blockText
                    FROM links l
                    JOIN files f ON f.path = l.file
                    JOIN files target ON target.path = l.resolvedFile
                    LEFT JOIN entities e ON e.file = l.file
                    LEFT JOIN blocks b ON b.file = l.file AND b.ordinal = l.block
                    WHERE target.kind = 'day' AND target.date = ? AND target.readable = 1
                      AND f.readable = 1
                      AND l.key IS NULL
                      AND l.file != target.path
                    ORDER BY l.file, l.line
                    """, arguments: [day.description])

            return rows.map { row in
                let file: String = row["file"]
                let line: Int = row["line"]
                let fileKind: String = row["fileKind"]

                let name: String
                if let entityName = row["entityName"] as String? {
                    let qualifier = row["entityQualifier"] as String?
                    name = entityName + (qualifier.map { " (" + $0 + ")" } ?? "")
                } else if fileKind == "day", let fileDate = row["fileDate"] as String? {
                    name = fileDate
                } else {
                    let basename = file.split(separator: "/").last.map(String.init) ?? file
                    name = basename.hasSuffix(".md") ? String(basename.dropLast(3)) : basename
                }

                let text: String
                if let blockText = row["blockText"] as String?,
                    let firstLine = row["firstLine"] as Int?
                {
                    let lines = blockText.split(separator: "\n", omittingEmptySubsequences: false)
                    let offset = line - firstLine
                    if offset >= 0 && offset < lines.count {
                        text = String(lines[offset])
                    } else {
                        text = blockText
                    }
                } else {
                    text = (row["blockText"] as String?) ?? ""
                }

                return DayBacklink(
                    file: file,
                    kind: fileKind,
                    name: name,
                    text: text,
                    line: line
                )
            }
        }
    }
}
