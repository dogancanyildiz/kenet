import Foundation
import VaultFormat
import VaultIndex

public enum RelationError: Error, Equatable, Sendable {
    case keyInUse
    case reservedLabel
    case invalidLabel
    case invalidSource
    case invalidTarget
    case unsafeRemoval
}

extension VaultStore {
    public func addRelation(from path: String, to targetName: String, label: String? = nil) async throws {
        try await changeRelation(from: path, to: targetName, label: label, removing: false)
    }

    public func removeRelation(from path: String, to targetName: String, label: String? = nil) async throws {
        try await changeRelation(from: path, to: targetName, label: label, removing: true)
    }

    private func changeRelation(from path: String, to targetName: String, label: String?, removing: Bool)
        async throws
    {
        _ = try await perform {
            try self.edit(path) { document in
                if case .unreadable = document.frontmatter { throw EditError.unreadableFrontmatter }
                // Resolution uses current disk contents, including newly created duplicate basenames.
                try self.index.refresh(vaultRoot: self.root)
                let catalog = EntityTypeReader.read(vaultRoot: self.root)
                let kinds: Set<String> = Set(["person", "place"] + catalog.types.map(\.id))
                let files = try self.index.files()
                guard let source = files.first(where: { $0.path == path }), kinds.contains(source.kind) else {
                    throw RelationError.invalidSource
                }
                func resolved(_ link: WikiLink) throws -> String? {
                    var target = link.target
                    while target.hasPrefix("/") || target.hasPrefix("./") {
                        target.removeFirst(target.hasPrefix("./") ? 2 : 1)
                    }
                    let isPath = link.target.contains("/")
                    let file =
                        link.target.isEmpty
                        ? path
                        : files.first {
                            let stem = String($0.path.dropLast(3))
                            let candidate = isPath ? stem : (stem as NSString).lastPathComponent
                            return nameComparisonKey(candidate) == nameComparisonKey(target)
                        }?.path
                    return file
                }
                let spelling = "[[" + targetName + "]]"
                let input = RawDocument(bytes: spelling.utf8).links
                guard input.count == 1, input[0].byteRange == 0..<spelling.utf8.count,
                    input[0].anchor == nil, input[0].displayText == nil, !input[0].target.isEmpty
                else { throw RelationError.invalidTarget }
                let targetPath = try resolved(input[0])
                let validTarget =
                    files.contains { $0.path == targetPath && kinds.contains($0.kind) }
                    && targetPath != path
                if !removing && !validTarget { throw RelationError.invalidTarget }

                let trimmed = label?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
                let key = trimmed.isEmpty ? "related" : trimmed
                if !trimmed.isEmpty {
                    guard trimmed != "<<",
                        (label ?? "").unicodeScalars.allSatisfy({
                            !CharacterSet.controlCharacters.contains($0) && $0.value != 0x2028 && $0.value != 0x2029
                        })
                    else { throw RelationError.invalidLabel }
                    var reserved = ["type", "name", "qualifier", "aliases", "related"]
                    if source.kind == "person" {
                        reserved += ["cadence_days", "cadence_snoozed_until", "cadence_paused"]
                    } else if source.kind == "place" {
                        reserved += ["coordinates", "radius"]
                    } else {
                        reserved += catalog.types.first { $0.id == source.kind }?.fields.map(\.key) ?? []
                    }
                    if reserved.contains(where: { $0.utf8.elementsEqual(trimmed.utf8) }) {
                        throw RelationError.reservedLabel
                    }
                }
                guard validTarget, let targetPath else { return document }
                let field: FrontmatterField?
                if case .parsed(let frontmatter) = document.frontmatter {
                    field = frontmatter.field(named: key)
                } else {
                    field = nil
                }
                // Raw fields and mappings cannot contain a relation; removing a missing relation is a no-op.
                guard field == nil || field?.value.listItems != nil else {
                    if removing { return document }
                    throw RelationError.keyInUse
                }
                let items = field?.value.listItems ?? []
                let links = items.map { value in
                    value.kind == .text ? RawDocument(bytes: value.text.utf8).links : []
                }
                let matches = try links.map { links in
                    try links.contains { try resolved($0) == targetPath }
                }
                if removing {
                    guard matches.contains(true) else { return document }
                    for (item, match) in zip(items, matches) where match {
                        let text = item.text.trimmingCharacters(in: .whitespacesAndNewlines)
                        let parsed = RawDocument(bytes: text.utf8).links
                        guard parsed.count == 1, parsed[0].byteRange == 0..<text.utf8.count else {
                            throw RelationError.unsafeRemoval
                        }
                    }
                    let kept = zip(items, matches).filter { !$0.1 }.map { Self.relationLiteral($0.0) }
                    if kept.isEmpty { return try document.removingFrontmatterField(forKey: key) }
                    return try document.settingFrontmatterList(kept, forKey: key)
                }
                // The no-op check precedes key-shape checks, as specified in the format.
                if matches.contains(true) { return document }
                if !trimmed.isEmpty && links.contains(where: \.isEmpty) {
                    throw RelationError.keyInUse
                }
                guard let target = try self.index.knownEntities(kinds: kinds).first(where: { $0.file == targetPath })
                else { throw RelationError.invalidTarget }
                let text = "[[" + target.linkTarget + "]]"
                let written = RawDocument(bytes: text.utf8).links
                guard written.count == 1, written[0].byteRange == 0..<text.utf8.count,
                    written[0].anchor == nil, written[0].displayText == nil,
                    try resolved(written[0]) == targetPath
                else { throw RelationError.invalidTarget }
                if items.isEmpty && !trimmed.isEmpty {
                    // Empty lists stay lists, unlike a missing field or empty scalar.
                    if case .list? = field?.value {
                    } else {
                        return try document.settingFrontmatterValue(.text(text), forKey: key)
                    }
                }
                return try document.settingFrontmatterList(
                    items.map(Self.relationLiteral) + [.text(text)], forKey: key)
            }
        }
    }

    private nonisolated static func relationLiteral(_ scalar: FrontmatterScalar) -> FrontmatterLiteral {
        switch scalar.kind {
        case .text: .text(scalar.text)
        case .empty: .null
        case .number: .number(scalar.raw)
        case .boolean(let value): .boolean(value)
        case .date(let value): .date(value)
        }
    }
}
