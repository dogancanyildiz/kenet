import Foundation
import GRDB
import VaultFormat

enum IndexBuilder {
    static func insert(
        file: String, data: Data, document: RawDocument, modified: Double, db: Database, owners: inout Set<String>
    ) throws {
        let frontmatter: Frontmatter?
        if case .parsed(let parsed) = document.frontmatter { frontmatter = parsed } else { frontmatter = nil }
        func scalar(_ key: String) -> String? {
            guard case .scalar(let value) = frontmatter?.field(named: key)?.value else { return nil }
            return value.text
        }
        let stem = String(file.dropLast(3))
        let basename = (stem as NSString).lastPathComponent
        let date = file == "journal/" + basename + ".md" ? CalendarDate(basename)?.description : nil
        let type = scalar("type") ?? "note"
        let kind =
            !document.isValidUTF8
            ? "note" : (date != nil ? "day" : (["person", "place", "goal"].contains(type) ? type : "note"))
        try db.execute(
            sql: "INSERT INTO files VALUES (?,?,?,?,?,?,?)",
            arguments: [file, kind, date, modified, data.count, ByteDigest.hex(data), document.isValidUTF8])
        guard document.isValidUTF8 else { return }
        if ["person", "place", "goal"].contains(kind) {
            let sourceName = scalar("name")
            let name =
                sourceName.flatMap { $0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? nil : $0 } ?? basename
            try db.execute(
                sql: "INSERT INTO entities VALUES (?,?,?,?,?,?,?,?,?,?)",
                arguments: [
                    file, kind, name, scalar("qualifier"), comparisonKey(name),
                    kind == "goal" ? scalar("key") : nil, kind == "goal" ? scalar("period") : nil,
                    kind == "goal" ? scalar("kind") : nil, kind == "goal" ? scalar("target") : nil,
                    kind == "goal" ? scalar("unit") : nil,
                ])
            try search(file: file, block: nil, text: name, db: db)
            for (ordinal, alias) in (frontmatter?.field(named: "aliases")?.value.listItems ?? []).enumerated() {
                try db.execute(
                    sql: "INSERT INTO aliases VALUES (?,?,?,?)",
                    arguments: [file, ordinal, alias.text, comparisonKey(alias.text)])
                try search(file: file, block: nil, text: alias.text, db: db)
            }
        }
        if let date, case .mapping(let entries) = frontmatter?.field(named: "goals")?.value {
            for entry in entries {
                let kind: String
                let value: String
                switch entry.value.kind {
                case .boolean(let flag):
                    kind = "boolean"
                    value = flag ? "true" : "false"
                case .number:
                    kind = "number"
                    value = entry.value.raw
                default:
                    kind = "raw"
                    value = entry.value.raw
                }
                try db.execute(
                    sql: "INSERT INTO goal_logs VALUES (?,?,?,?,?)",
                    arguments: [file, entry.key, date, kind, value])
            }
        }
        try insertBlocks(document: document, file: file, db: db, owners: &owners)
    }

    private struct Block {
        let range: Range<Int>
        let kind: String
        let text: String
        var identifier: String? = nil
        var time: String? = nil
        var status: String? = nil
        var rawStatus: String? = nil
        var headingLevel: Int? = nil
    }

    private static func insertBlocks(document: RawDocument, file: String, db: Database, owners: inout Set<String>)
        throws
    {
        let body = document.bodyLines
        let sections = document.daySections.sections
        func section(_ line: Int) -> String {
            sections.first { $0.lineRange.contains(line) }?.kind?.rawValue ?? "other"
        }
        var blocks =
            body.events.map {
                Block(
                    range: $0.block.lineRange, kind: "event", text: $0.block.text,
                    identifier: $0.block.id, time: $0.time?.raw)
            }
            + body.tasks.map {
                Block(
                    range: $0.block.lineRange, kind: "task", text: $0.block.text,
                    identifier: $0.block.id, status: $0.status.rawValue, rawStatus: $0.rawStatus)
            }
        let occupied = Set(blocks.flatMap { Array($0.range) })
        let recognized = Set(sections.filter { $0.kind != nil }.map(\.headingLine))
        let sourceHeadings = document.bodyHeadings
        let headings = Set(sourceHeadings.map(\.line))
        for heading in sourceHeadings where !recognized.contains(heading.line) {
            let text = (document.lines[heading.line].text ?? "").trimmingCharacters(in: .whitespaces)
            let title = String(text.dropFirst(heading.level)).trimmingCharacters(in: .whitespaces)
            blocks.append(
                Block(
                    range: heading.line..<(heading.line + 1), kind: "heading", text: title,
                    headingLevel: heading.level))
        }
        var start: Int?
        func flush(_ end: Int) {
            if let first = start {
                blocks.append(
                    Block(
                        range: first..<end, kind: "paragraph",
                        text: document.lines[first..<end].map { $0.text ?? "" }.joined(separator: "\n")))
            }
            start = nil
        }
        for line in (document.frontmatterLineRange?.upperBound ?? 0)..<document.lines.count {
            let text = document.lines[line].text ?? ""
            if headings.contains(line) { flush(line) }
            if occupied.contains(line) || headings.contains(line)
                || text.trimmingCharacters(in: .whitespaces).isEmpty
            {
                flush(line)
            } else {
                if start == nil { start = line }
            }
        }
        flush(document.lines.count)
        blocks.sort { $0.range.lowerBound < $1.range.lowerBound }
        for (ordinal, block) in blocks.enumerated() {
            let owns = block.identifier.map { owners.insert($0).inserted } ?? false
            try db.execute(
                sql: "INSERT INTO blocks VALUES (?,?,?,?,?,?,?,?,?,?,?,?,?)",
                arguments: [
                    file, ordinal, block.kind, block.range.lowerBound + 1, block.range.upperBound,
                    block.text, section(block.range.lowerBound), block.time, block.status, block.rawStatus,
                    block.identifier, block.headingLevel, owns,
                ])
            try search(file: file, block: ordinal, text: block.text, db: db)
        }
    }

    private static func search(file: String, block: Int?, text: String, db: Database) throws {
        try db.execute(
            sql: "INSERT INTO search (file,block,text) VALUES (?,?,?)",
            arguments: [file, block, text.precomposedStringWithCanonicalMapping])
    }

    static func insertLinks(
        document: RawDocument, file: String, db: Database
    ) throws {
        for (ordinal, link) in document.links.enumerated() {
            let key: String?
            let entry: String?
            let block: Int?
            switch link.source {
            case .body:
                key = nil
                entry = nil
                // Nested blocks belong to the innermost source range.
                block = try Int.fetchOne(
                    db,
                    sql: """
                        SELECT ordinal FROM blocks WHERE file=? AND firstLine<=? AND lastLine>=?
                        ORDER BY firstLine DESC,ordinal DESC LIMIT 1
                        """, arguments: [file, link.line + 1, link.line + 1])
            case .frontmatter(let sourceKey, let sourceEntry):
                key = sourceKey
                entry = sourceEntry
                block = nil
            }
            let anchorKind: String?
            let anchor: String?
            switch link.anchor {
            case .heading(let text):
                anchorKind = "heading"
                anchor = text
            case .block(let text):
                anchorKind = "block"
                anchor = text
            case nil:
                anchorKind = nil
                anchor = nil
            }
            let targetKey = comparisonKey(normalizedLinkTarget(link.target))
            try db.execute(
                sql: "INSERT INTO links VALUES (?,?,?,?,?,?,?,?,?,?,?,?,?,?,?)",
                arguments: [
                    file, ordinal, block, link.line + 1, link.byteRange.lowerBound, link.byteRange.upperBound,
                    key, entry, link.target, targetKey, anchorKind, anchor, link.displayText, link.isEmbedded, nil,
                ])
        }
    }
}
