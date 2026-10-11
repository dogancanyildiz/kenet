import EntityRecognition
import Foundation
import GRDB
import Testing
import VaultFormat

@testable import VaultIndex
@testable import VaultStore

/// Hostile input for the unlinked mention query and its writer: `vaults/unlinked-mentions-hostile`
/// and seeded random lines. Every listed mention must link to exactly one wikilink, or be refused
/// without a write.
struct UnlinkedMentionAdversarialTests {
    static let vaultName = "unlinked-mentions-hostile"

    /// What one attempt to link a listed mention did.
    enum Outcome: Equatable {
        case linked
        case refused(String)
    }

    /// Where a mention is, apart from the bytes a link on its line adds.
    struct Place: Equatable {
        let file: String
        let line: Int
        var start: Int
        let spelling: [UInt8]

        init(file: String, line: Int, start: Int, spelling: [UInt8]) {
            self.file = file
            self.line = line
            self.start = start
            self.spelling = spelling
        }

        init(_ mention: UnlinkedMention) {
            self.init(
                file: mention.file, line: mention.position.line, start: mention.position.byteRange.lowerBound,
                spelling: Array(mention.spelling.utf8))
        }
    }

    func setup() throws -> StoreVault {
        let vault = try StoreVault()
        do {
            let fixture = try Fixtures.root().appendingPathComponent("vaults/" + Self.vaultName)
            for directory in try FileManager.default.contentsOfDirectory(atPath: fixture.path)
            where !directory.hasPrefix(".") {
                try FileManager.default.copyItem(
                    at: fixture.appendingPathComponent(directory), to: vault.root.appendingPathComponent(directory))
            }
            try vault.index.rebuild(vaultRoot: vault.root)
            return vault
        } catch {
            vault.remove()
            throw error
        }
    }

    func snapshot(_ vault: StoreVault, except path: String) throws -> [String: Data] {
        var result: [String: Data] = [:]
        for file in try FileManager.default.subpathsOfDirectory(atPath: vault.root.path) where file != path {
            var isDirectory: ObjCBool = false
            let url = vault.root.appendingPathComponent(file)
            guard FileManager.default.fileExists(atPath: url.path, isDirectory: &isDirectory), !isDirectory.boolValue
            else { continue }
            result[file] = try Data(contentsOf: url)
        }
        return result
    }

    /// The only bytes a link may produce, built without the recognizer's own writer.
    static func splice(_ mention: UnlinkedMention, to entity: KnownEntity, in source: Data) throws -> [Data] {
        let document = RawDocument(bytes: source)
        var offset = document.hasByteOrderMark ? 3 : 0
        for line in document.lines.prefix(mention.position.line) { offset += line.bytes.count }
        let bytes = Array(source)
        let content = Array(mention.lineText.utf8)
        try #require(Array(bytes[offset..<(offset + content.count)]) == content)
        let range = mention.position.byteRange
        try #require(Array(content[range]) == Array(mention.spelling.utf8))
        let start = offset + range.lowerBound - (mention.isExplicit ? 1 : 0)
        try #require(!mention.isExplicit || bytes[start] == 64)
        let links = ["[[" + entity.linkTarget + "]]", "[[" + entity.linkTarget + "|" + mention.spelling + "]]"]
        return links.map { Data(bytes[..<start] + Array($0.utf8) + bytes[(offset + range.upperBound)...]) }
    }

    /// Links one listed mention, checks everything a link may and may not change, and restores the file.
    func attempt(
        _ mention: UnlinkedMention, to entity: KnownEntity, in vault: StoreVault, listed: [UnlinkedMention]? = nil
    ) async throws -> Outcome {
        let thorough = listed != nil
        let listed = listed ?? []
        let source = try vault.bytes(mention.file)
        let others = thorough ? try snapshot(vault, except: mention.file) : [:]
        let incoming = try vault.index.links(to: entity.file).filter { $0.file == mention.file }.count
        let label = "\(mention.file):\(mention.position.line) \(mention.position.byteRange) \(mention.lineText)"
        do {
            try await vault.store.linkingMention(mention, to: entity)
        } catch let error as EntityLinkError {
            #expect(error == .unrepresentableMention, "\(label)")
            #expect(try vault.bytes(mention.file) == source, "\(label)")
            return .refused(label)
        }
        defer {
            try? source.write(to: vault.root.appendingPathComponent(mention.file))
            _ = try? vault.index.update(paths: [mention.file], vaultRoot: vault.root)
        }
        let written = try vault.bytes(mention.file)
        let allowed = try Self.splice(mention, to: entity, in: source)
        #expect(allowed.contains(written), "\(label) -> \(String(decoding: written, as: UTF8.self))")
        // The plain form is only for a spelling that is the target itself.
        if written == allowed[0], allowed[0] != allowed[1] {
            #expect(
                Array(mention.spelling.utf8) == Array(entity.linkTarget.utf8) && entity.qualifier == nil, "\(label)")
        }
        if thorough { #expect(try snapshot(vault, except: mention.file) == others, "\(label)") }

        let before = RawDocument(bytes: source)
        let after = RawDocument(bytes: written)
        #expect(after.links.count == before.links.count + 1, "\(label)")
        let added = after.links.filter { !before.links.contains($0) }
        #expect(added.contains { $0.line == mention.position.line && $0.target == entity.linkTarget }, "\(label)")
        #expect(after.bodyLines.events.map(\.time) == before.bodyLines.events.map(\.time), "\(label)")
        #expect(
            after.bodyLines.events.map { [$0.block.lineRange.lowerBound, $0.block.lineRange.upperBound] }
                == before.bodyLines.events.map { [$0.block.lineRange.lowerBound, $0.block.lineRange.upperBound] },
            "\(label)")
        #expect(after.bodyLines.events.map(\.block.id) == before.bodyLines.events.map(\.block.id), "\(label)")
        #expect(after.bodyLines.tasks.map(\.block.id) == before.bodyLines.tasks.map(\.block.id), "\(label)")
        #expect(after.bodyLines.tasks.map(\.block.lineRange) == before.bodyLines.tasks.map(\.block.lineRange))
        #expect(after.bodyLines.tasks.map(\.rawStatus) == before.bodyLines.tasks.map(\.rawStatus), "\(label)")
        #expect(after.bodyLines.tasks.map(\.dueDate) == before.bodyLines.tasks.map(\.dueDate), "\(label)")
        #expect(after.bodyLines.tasks.map(\.startDate) == before.bodyLines.tasks.map(\.startDate), "\(label)")
        #expect(after.bodyLines.tasks.map(\.doneDate) == before.bodyLines.tasks.map(\.doneDate), "\(label)")
        #expect(after.bodyLines.tasks.map(\.priority) == before.bodyLines.tasks.map(\.priority), "\(label)")
        #expect(after.bodyLines.tasks.map(\.project) == before.bodyLines.tasks.map(\.project), "\(label)")
        #expect(
            after.bodyLines.tasks.map(\.recurrenceSource) == before.bodyLines.tasks.map(\.recurrenceSource), "\(label)")
        #expect(after.daySections == before.daySections, "\(label)")

        // The index resolves the new link to the chosen entity, and the mention leaves the list.
        #expect(
            try vault.index.links(to: entity.file).filter { $0.file == mention.file }.count == incoming + 1, "\(label)")
        guard thorough else { return .linked }
        // Every other mention stays, at its new place on that line. A neighbour the link uncovers may join.
        let remaining = try vault.index.unlinkedMentions(of: entity, vaultRoot: vault.root).map(Place.init)
        let growth = written.count - source.count
        for other in listed where other != mention {
            var place = Place(other)
            if other.file == mention.file, other.position.line == mention.position.line,
                other.position.byteRange.lowerBound > mention.position.byteRange.lowerBound
            {
                place.start += growth
            }
            #expect(remaining.contains(place), "\(label) lost \(other.position)")
        }
        #expect(!remaining.contains(Place(mention)), "\(label)")
        return .linked
    }

    func entity(_ file: String, in vault: StoreVault) throws -> KnownEntity {
        try #require(vault.index.unlinkedMentionEntities().first { $0.file == file })
    }

    /// Links every mention the query lists, one at a time, and returns the refused ones.
    func linkEverything(in vault: StoreVault, thorough: Bool) async throws -> (linked: Int, refused: [String]) {
        var linked = 0
        var refused: [String] = []
        for entity in try vault.index.unlinkedMentionEntities().sorted(by: { $0.file < $1.file }) {
            let listed = try vault.index.unlinkedMentions(of: entity, vaultRoot: vault.root)
            for mention in listed {
                switch try await attempt(mention, to: entity, in: vault, listed: thorough ? listed : nil) {
                case .linked: linked += 1
                case .refused(let label): refused.append(entity.file + " " + label)
                }
            }
        }
        return (linked, refused)
    }

    // MARK: - Query

    @Test func hostileQueryMatchesPortableFixture() throws {
        let url = try Fixtures.root().appendingPathComponent("recognition/" + Self.vaultName + "/expected.json")
        let fixture = try JSONDecoder().decode(UnlinkedMentionTests.QueryFixture.self, from: Data(contentsOf: url))
        #expect(fixture.vault == Self.vaultName)
        let vault = try setup()
        defer { vault.remove() }
        #expect(try Set(fixture.queries.map(\.entity)) == Set(vault.index.unlinkedMentionEntities().map(\.file)))
        for query in fixture.queries {
            let actual = try vault.index.unlinkedMentions(of: entity(query.entity, in: vault), vaultRoot: vault.root)
            #expect(actual.map(UnlinkedMentionTests.Expected.init) == query.mentions, "\(query.entity)")
            for (mention, expected) in zip(actual, query.mentions) {
                #expect(Array(mention.spelling.utf8) == Array(expected.spelling.utf8))
            }
        }
    }

    /// The query recognizes first lines alone; reading each file whole, as the writer does, must agree.
    static func wholeFileMentions(of entity: KnownEntity, in vault: StoreVault) throws -> [Place] {
        let entities = try vault.index.unlinkedMentionEntities()
        var result: [Place] = []
        for day in try vault.index.unlinkedMentionDays(naming: nil) {
            let document = RawDocument(bytes: try vault.bytes(day.path))
            guard !document.isReadOnly else { continue }
            var scopes: [Int: UnlinkedMentionScope] = [:]
            for event in document.bodyLines.events { scopes[event.block.line] = UnlinkedMentionScope(event.block) }
            for task in document.bodyLines.tasks { scopes[task.block.line] = UnlinkedMentionScope(task) }
            let text = String(decoding: document.serialized(), as: UTF8.self)
            for mention in EntityRecognizer.recognize(text, entities: entities) {
                guard mention.candidates.contains(where: { $0.file == entity.file }),
                    let scope = scopes[mention.line], scope.contains(mention.byteRange),
                    scope.keepsFields(linking: mention.byteRange, isExplicit: mention.isExplicit, to: entity)
                else { continue }
                result.append(
                    Place(
                        file: day.path, line: mention.line, start: mention.byteRange.lowerBound,
                        spelling: Array(mention.spelling.utf8)))
            }
        }
        return result
    }

    static func agreesWithWholeFiles(_ vault: StoreVault) throws -> Int {
        var total = 0
        for entity in try vault.index.unlinkedMentionEntities() {
            let listed = try vault.index.unlinkedMentions(of: entity, vaultRoot: vault.root).map(Place.init)
            let whole = try wholeFileMentions(of: entity, in: vault)
            let order: (Place, Place) -> Bool = { ($0.file, $0.line, $0.start) < ($1.file, $1.line, $1.start) }
            #expect(listed.sorted(by: order) == whole.sorted(by: order), "\(entity.file)")
            total += whole.count
        }
        return total
    }

    @Test func firstLinesReadAloneAgreeWithWholeFiles() throws {
        let vault = try setup()
        defer { vault.remove() }
        #expect(try Self.agreesWithWholeFiles(vault) > 150)
    }

    /// The search stage must not hide a mention, whatever the name and the line look like.
    @Test func searchNarrowingLosesNothing() throws {
        let vault = try setup()
        defer { vault.remove() }
        let names = [
            "Ёлка", "Άννα", "Straße", "Ǆon", "x²", "½", "①", "R2-D2", "3. Kat", "Ali & Can", "e\u{0301}cole", "山田",
            "ʻOkina", "İİ", "I", "ıI", "Kaya Su",
        ]
        for (number, name) in names.enumerated() {
            let quoted = name.replacingOccurrences(of: "\"", with: "\\\"")
            try vault.write("people/Ad \(number).md", "---\ntype: person\nname: \"\(quoted)\"\n---\n")
            let spellings = [name, name.uppercased(), name.lowercased(), name.decomposedStringWithCanonicalMapping]
            let lines = spellings.flatMap {
                ["- \($0) geldi.", "- x_\($0)'in; (\($0))", "- [ ] \($0)-\($0) 📅 2026-05-01"]
            }
            try vault.write(
                String(format: "journal/2026-05-%02d.md", number + 1),
                "## Events\n" + lines.joined(separator: "\n") + "\n- Kaya\u{00A0}\u{00A0}Su ve Kaya\tSu\n")
        }
        try vault.index.rebuild(vaultRoot: vault.root)
        let entities = try vault.index.unlinkedMentionEntities()
        let everyDay = try vault.index.unlinkedMentionDays(naming: nil)
        var total = 0
        for entity in entities {
            let exhaustive = try vault.index.unlinkedMentions(
                of: entity, entities: entities, days: everyDay, vaultRoot: vault.root)
            let narrowed = try vault.index.unlinkedMentions(of: entity, vaultRoot: vault.root)
            #expect(narrowed == exhaustive, "\(entity.file) \(entity.name)")
            total += exhaustive.count
        }
        #expect(total > 250)
    }

    /// A file name that cannot be written inside a wikilink offers nothing, so nothing can be refused later.
    @Test(arguments: ["A#B", "A^B", "A[B]", "A|B", "A:B"])
    func unrepresentableFileNameListsNothing(stem: String) throws {
        let vault = try setup()
        defer { vault.remove() }
        try vault.write("people/\(stem).md", "---\ntype: person\nname: Yabancı\n---\n")
        try vault.write("journal/2026-05-01.md", "## Events\n- Yabancı geldi, Elif de.\n")
        try vault.index.rebuild(vaultRoot: vault.root)
        let stranger = try entity("people/\(stem).md", in: vault)
        #expect(try vault.index.unlinkedMentions(of: stranger, vaultRoot: vault.root).isEmpty)
        let elif = try entity("people/Elif.md", in: vault)
        #expect(
            try vault.index.unlinkedMentions(of: elif, vaultRoot: vault.root).contains {
                $0.file == "journal/2026-05-01.md"
            })
    }

    // MARK: - Every listed mention links

    @Test func everyListedMentionLinksToExactlyOneLink() async throws {
        let vault = try setup()
        defer { vault.remove() }
        let result = try await linkEverything(in: vault, thorough: true)
        #expect(result.refused == [])
        #expect(result.linked > 140)
    }

    /// The same lines list and link the same mentions under every terminator the format reads.
    @Test(arguments: ["crlf", "bom-crlf-no-final-newline", "cr", "no-final-newline"])
    func lineEndingsDoNotChangeWhatLinks(variant: String) async throws {
        let vault = try setup()
        defer { vault.remove() }
        // This day mixes terminators already and cannot be rewritten with one.
        try FileManager.default.removeItem(at: vault.root.appendingPathComponent("journal/2026-03-06.md"))
        try vault.index.rebuild(vaultRoot: vault.root)
        let plain = try linkable(in: vault)
        for day in 1...5 {
            let path = String(format: "journal/2026-03-%02d.md", day)
            var lines = String(decoding: try vault.bytes(path), as: UTF8.self).components(separatedBy: "\n")
            #expect(lines.removeLast().isEmpty)
            let ending = variant == "cr" ? "\r" : variant.contains("crlf") ? "\r\n" : "\n"
            let text =
                (variant.hasPrefix("bom") ? "\u{FEFF}" : "") + lines.joined(separator: ending)
                + (variant.hasSuffix("no-final-newline") ? "" : ending)
            try vault.write(path, text)
        }
        try vault.index.rebuild(vaultRoot: vault.root)
        #expect(try linkable(in: vault) == plain)
        let result = try await linkEverything(in: vault, thorough: false)
        #expect(result.refused == [])
        #expect(result.linked == plain.count)
    }

    func linkable(in vault: StoreVault) throws -> [String] {
        try vault.index.unlinkedMentionEntities().sorted(by: { $0.file < $1.file }).flatMap { entity in
            try vault.index.unlinkedMentions(of: entity, vaultRoot: vault.root)
                .map { "\(entity.file) \($0.file) \($0.position.line) \($0.position.byteRange) \($0.lineText)" }
        }
    }

    @Test(arguments: [UInt64(20_261_011), 7, 1_234_567])
    func randomLinesLinkOrAreNotListed(seed: UInt64) async throws {
        let vault = try setup()
        defer { vault.remove() }
        for file in try FileManager.default.contentsOfDirectory(
            atPath: vault.root.appendingPathComponent("journal").path)
        {
            try FileManager.default.removeItem(at: vault.root.appendingPathComponent("journal/" + file))
        }
        var generator = Generator(state: seed)
        for day in 1...20 {
            try vault.write(String(format: "journal/2026-04-%02d.md", day), Self.randomDay(&generator, lines: 10))
        }
        try vault.index.rebuild(vaultRoot: vault.root)
        let entities = try vault.index.unlinkedMentionEntities()
        let everyDay = try vault.index.unlinkedMentionDays(naming: nil)
        for entity in entities {
            #expect(
                try vault.index.unlinkedMentions(of: entity, vaultRoot: vault.root)
                    == vault.index.unlinkedMentions(
                        of: entity, entities: entities, days: everyDay, vaultRoot: vault.root),
                "\(entity.file)")
        }
        #expect(try Self.agreesWithWholeFiles(vault) > 100)
        let result = try await linkEverything(in: vault, thorough: false)
        #expect(result.refused == [])
        #expect(result.linked > 100)
    }

    @Test(.timeLimit(.minutes(2))) func veryLongLineLinksAtEitherEnd() async throws {
        let vault = try setup()
        defer { vault.remove() }
        let path = "journal/2026-05-02.md"
        let words = (0..<3000).map { $0.isMultiple(of: 10) ? "Elif" : "kelime\($0) 🎸 çağrı" }
        try vault.write(path, "## Events\n- 23:59 " + words.joined(separator: " ") + " ^uzun\n- Ece\n")
        try vault.index.update(paths: [path], vaultRoot: vault.root)
        let elif = try entity("people/Elif.md", in: vault)
        let mentions = try vault.index.unlinkedMentions(of: elif, vaultRoot: vault.root).filter { $0.file == path }
        #expect(mentions.count == 300)
        for mention in [mentions[0], mentions[150], mentions[299]] {
            #expect(try await attempt(mention, to: elif, in: vault) == .linked)
        }
    }

    // MARK: - Stale targets

    /// `2026-03-01` holds `- Elif` on lines 7 and 8. Once the file changes, neither twin can be told from the
    /// other, and a line that gained a twin is refused as well rather than guessed at.
    @Test(arguments: [
        "twinSlidIntoPlace", "twinLeftAlone", "twinAddedBelow", "twinAddedInPlace", "linkedToAnotherEntity",
        "lineMoved", "sectionRenamed", "entityRenamed", "fenced",
    ])
    func changedFileNeverLinksAnotherLine(change: String) async throws {
        let vault = try setup()
        defer { vault.remove() }
        let path = "journal/2026-03-01.md"
        let elif = try entity("people/Elif.md", in: vault)
        let all = try vault.index.unlinkedMentions(of: elif, vaultRoot: vault.root).filter { $0.file == path }
        let twin = try #require(all.first { $0.position.line == 7 })
        #expect(all.contains { $0.position.line == 8 && $0.lineText == twin.lineText })
        let single = try #require(all.first { $0.position.line == 6 })
        var lines = String(decoding: try vault.bytes(path), as: UTF8.self).components(separatedBy: "\n")
        var selected = twin
        var paths: Set<String> = []
        switch change {
        case "twinSlidIntoPlace": lines.remove(at: 6)
        case "twinLeftAlone":
            // The chosen twin is deleted and a new line pushes the other one into its place.
            lines.remove(at: 7)
            lines.insert("- Yeni olay.", at: 1)
            selected = try #require(all.first { $0.position.line == 8 })
        case "twinAddedBelow":
            selected = single
            lines.insert(single.lineText, at: 9)
        case "twinAddedInPlace":
            // A copy takes the line's place and the original moves down.
            selected = single
            lines.remove(at: 1)
            lines.insert(single.lineText, at: 6)
        case "linkedToAnotherEntity": lines[7] = "- [[Ece|Elif]]"
        case "lineMoved":
            selected = single
            lines.swapAt(5, 6)
        case "sectionRenamed": lines[0] = "## Notlar"
        case "entityRenamed":
            try FileManager.default.moveItem(
                at: vault.root.appendingPathComponent("people/Elif.md"),
                to: vault.root.appendingPathComponent("people/Elif Y.md"))
            paths = ["people/Elif.md", "people/Elif Y.md"]
        default:
            lines.insert("```", at: 1)
            lines.remove(at: 2)
        }
        try vault.write(path, lines.joined(separator: "\n"))
        try vault.index.update(paths: paths, vaultRoot: vault.root)
        let files = try snapshot(vault, except: "")
        let index = try vault.index.snapshot()
        await #expect(throws: VaultStoreError.staleTarget) {
            try await vault.store.linkingMention(selected, to: elif)
        }
        #expect(try snapshot(vault, except: "") == files)
        #expect(try vault.index.snapshot() == index)
    }

    /// Twins in an unchanged file are still two separate choices, and each links its own line.
    @Test(arguments: [7, 8]) func twinLinksItsOwnLineWhileTheFileIsUnchanged(line: Int) async throws {
        let vault = try setup()
        defer { vault.remove() }
        let path = "journal/2026-03-01.md"
        let elif = try entity("people/Elif.md", in: vault)
        let twin = try #require(
            vault.index.unlinkedMentions(of: elif, vaultRoot: vault.root).first {
                $0.file == path && $0.position.line == line
            })
        var lines = String(decoding: try vault.bytes(path), as: UTF8.self).components(separatedBy: "\n")
        try await vault.store.linkingMention(twin, to: elif)
        lines[line] = "- [[Elif]]"
        #expect(try vault.bytes(path) == Data(lines.joined(separator: "\n").utf8))
        try vault.check()
    }

    /// The link names the indexed file even when the caller's value carries another link target.
    @Test func callerEntityWithAnotherLinkTargetStillLinksTheIndexedFile() async throws {
        let vault = try setup()
        defer { vault.remove() }
        let indexed = try entity("places/Kaya.md", in: vault)
        #expect(indexed.linkTarget == "places/Kaya")
        let mention = try #require(vault.index.unlinkedMentions(of: indexed, vaultRoot: vault.root).first)
        let source = try vault.bytes(mention.file)
        // The default target of this value is the bare name, which resolves to `people/Kaya.md`.
        let loose = KnownEntity(file: "places/Kaya.md", kind: .place, name: "Kaya")
        #expect(loose.linkTarget == "Kaya")
        try await vault.store.linkingMention(mention, to: loose)
        #expect(try vault.bytes(mention.file) == Self.splice(mention, to: indexed, in: source)[1])
        #expect(try vault.index.links(to: "places/Kaya.md").map(\.file) == [mention.file])
        #expect(try vault.index.links(to: "people/Kaya.md").isEmpty)
    }

    // MARK: - Last gate

    /// The gate accepts the link the user chose and nothing that merely looks like a link.
    @Test(arguments: [
        ["[[Elif]]", "true"], ["[[Ece|Elif]]", "false"], ["[[Elif|Ece]]", "false"], ["[[Elif#Başlık]]", "false"],
        ["[[Elif|Elif]]", "false"], ["[[Elif]] [[Elif]]", "false"], ["[[Elif]]]]", "false"], ["[[ Elif ]]", "false"],
        ["[[Elif.md]]", "false"], ["[[elif]]", "false"], ["[[Elif^b1]]", "false"],
    ])
    func gateAcceptsOnlyTheChosenLink(arguments: [String]) throws {
        let entity = KnownEntity(file: "people/Elif.md", kind: .person, name: "Elif")
        for (prefix, suffix) in [("- 09:05 ", "'le konuştum. ^e1"), ("- [ ] ", " 📅 2026-10-12"), ("- @", "")] {
            let text = "## Events\n" + prefix + "Elif" + suffix + "\n- Ece\n"
            let source = RawDocument(bytes: text.utf8)
            let mention = try #require(EntityRecognizer.recognize(text, entities: [entity]).first)
            let start = prefix.hasSuffix("@") ? String(prefix.dropLast()) : prefix
            let forged = RawDocument(bytes: ("## Events\n" + start + arguments[0] + suffix + "\n- Ece\n").utf8)
            #expect(
                VaultStore.isSingleLink(forged, replacing: mention, in: source, to: entity) == (arguments[1] == "true"),
                "\(prefix)\(arguments[0])")
        }
    }

    /// A spelling that is not the target keeps itself as the display text; nothing else may be shown.
    @Test func gateRequiresTheSpellingAsDisplayText() throws {
        let entity = KnownEntity(file: "people/Deniz (iş).md", kind: .person, name: "Deniz", qualifier: "iş")
        let text = "## Events\n- Deniz geldi.\n"
        let source = RawDocument(bytes: text.utf8)
        let mention = try #require(EntityRecognizer.recognize(text, entities: [entity]).first)
        for (link, accepted) in [
            ("[[Deniz (iş)|Deniz]]", true), ("[[Deniz (iş)]]", false), ("[[Deniz (iş)|deniz]]", false),
            ("[[Deniz|Deniz]]", false), ("[[Deniz (iş)|Deniz|Deniz]]", false),
        ] {
            let forged = RawDocument(bytes: "## Events\n- \(link) geldi.\n".utf8)
            #expect(VaultStore.isSingleLink(forged, replacing: mention, in: source, to: entity) == accepted, "\(link)")
        }
    }

    /// A repeated field does not set the task's value, yet it is still a field and not the user's text.
    @Test func gateRefusesALinkInsideARepeatedField() throws {
        let entity = KnownEntity(file: "people/Sayı.md", kind: .person, name: "2026")
        let text = "## Tasks\n- [ ] 2026 ara 📅 2026-10-12 📅 2026-10-13 ⏫ ⏫\n"
        let source = RawDocument(bytes: text.utf8)
        let mentions = EntityRecognizer.recognize(text, entities: [entity])
        #expect(mentions.count == 3)
        for (mention, accepted) in zip(mentions, [true, false, false]) {
            let linked = RawDocument(bytes: try EntityRecognizer.linking(text, mentions: [mention]).utf8)
            #expect(VaultStore.isSingleLink(linked, replacing: mention, in: source, to: entity) == accepted)
        }
    }

    // MARK: - File first, index second

    @Test func indexFailureLeavesTheLinkedFileAndRefreshRepairsIt() async throws {
        let vault = try setup()
        defer { vault.remove() }
        let path = "journal/2026-03-01.md"
        let elif = try entity("people/Elif.md", in: vault)
        let mention = try #require(
            vault.index.unlinkedMentions(of: elif, vaultRoot: vault.root).first {
                $0.file == path && $0.position.line == 6
            })
        let source = try vault.bytes(path)
        let before = try vault.index.snapshot()
        let incoming = try vault.index.links(to: elif.file).count
        try await vault.index.database.write {
            try $0.execute(sql: "CREATE TRIGGER fail_link BEFORE INSERT ON links BEGIN SELECT RAISE(FAIL, 'test'); END")
        }
        await #expect {
            try await vault.store.linkingMention(mention, to: elif)
        } throws: { error in
            guard case VaultStoreError.indexUpdateFailed(let failed, let underlying) = error else { return false }
            return failed == path && underlying is DatabaseError
        }
        // The file holds the link although the index does not know it yet.
        let written = try vault.bytes(path)
        #expect(try Self.splice(mention, to: elif, in: source).contains(written))
        #expect(try vault.index.snapshot() == before)
        #expect(try vault.index.links(to: elif.file).count == incoming)
        // The query reads the file, so the mention is already gone, and the stale value cannot be applied again.
        let listed = try vault.index.unlinkedMentions(of: elif, vaultRoot: vault.root)
        #expect(!listed.contains { $0.file == path && $0.position.line == 6 })
        await #expect(throws: VaultStoreError.staleTarget) { try await vault.store.linkingMention(mention, to: elif) }
        #expect(try vault.bytes(path) == written)

        try await vault.index.database.write { try $0.execute(sql: "DROP TRIGGER fail_link") }
        try vault.index.refresh(vaultRoot: vault.root)
        #expect(try vault.index.links(to: elif.file).count == incoming + 1)
        try vault.check()
    }

    // A read-only directory does not stop root (the Linux CI container), so the test needs a real user.
    @Test(.enabled(if: geteuid() != 0)) func failedWriteLeavesTheFileAndTheIndex() async throws {
        let vault = try setup()
        defer { vault.remove() }
        let path = "journal/2026-03-01.md"
        let elif = try entity("people/Elif.md", in: vault)
        let mention = try #require(
            vault.index.unlinkedMentions(of: elif, vaultRoot: vault.root).first { $0.file == path })
        let source = try vault.bytes(path)
        let index = try vault.index.snapshot()
        let directory = vault.root.appendingPathComponent("journal")
        let siblings = try FileManager.default.contentsOfDirectory(atPath: directory.path).sorted()
        try FileManager.default.setAttributes([.posixPermissions: 0o555], ofItemAtPath: directory.path)
        defer { try? FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: directory.path) }
        await #expect(throws: (any Error).self) { try await vault.store.linkingMention(mention, to: elif) }
        #expect(try vault.bytes(path) == source)
        #expect(try FileManager.default.contentsOfDirectory(atPath: directory.path).sorted() == siblings)
        #expect(try vault.index.snapshot() == index)
    }

    // MARK: - Random lines

    static let fragments = [
        "Elif", "Elif", "Ece", "Ece Yalın", "Ece  Yalın", "Ada Nur Su", "Deniz", "Kaya", "12", "2026", "7", "30",
        "09:05", "📅", "⏫", "🔁", "✅", "x", "every", "🎸", "C#", "A|B", "x^y", "AT&T", "O'Neil", "Ali-Can", "C\\",
        "100%", "(X)", "!bang", "*yıldız*", "<b>", "a`b", "a]b", "a[b", "A", "İ", "ı", "Çağrı", "C\u{0327}ag\u{0306}rı",
        "Şule", "Umut", "elif", "ECE", "Elifler", "'in", "’le", "'", "’", "@", "@", "#", "^", "!", "\\", "|", "[", "]",
        "[[", "]]",
        "[[Ece|", "[[Elif]]", "](https://example.invalid)", "(", ")", "`", "``", "<!--", "-->", "<", ">", "*", "_",
        "~~", "==", "$", "%", ".", ",", ":", ";", "-", "—", "/", "https://example.invalid/", "www.", ".com", "📅",
        "📅 2026-10-12", "⏳ 2026-10-11", "🛫 2026-10-10", "✅ 2026-10-08", "🔁 every week", "🔁 every 7 days", "⏫",
        "🔼", "🔽", "#project/gezi", "#project/Elif", "^abc123", "^Elif", "12:30", "7:05", "2026-10-12", "ve", "geldi",
        "👍", "🇹🇷", "\u{200D}", "\u{0301}", "\u{FE0F}", "\u{00A0}", "\u{2028}", "\t",
    ]
    static let prefixes = [
        "- ", "- ", "- 12:30 ", "- 7:05 ", "- 09:05 ", "* ", "+ ", "- [ ] ", "- [ ] ", "- [x] ", "- [/] ", "  - [ ] ",
        "> - [ ] ", "1. [ ] ", "- > ", "-  ", "- \t",
    ]

    /// SplitMix64, so that a failing line can be reproduced from its seed.
    struct Generator {
        var state: UInt64
        mutating func next() -> UInt64 {
            state &+= 0x9E37_79B9_7F4A_7C15
            var z = state
            z = (z ^ (z >> 30)) &* 0xBF58_476D_1CE4_E5B9
            z = (z ^ (z >> 27)) &* 0x94D0_49BB_1331_11EB
            return z ^ (z >> 31)
        }
        mutating func pick(_ values: [String]) -> String { values[Int(next() % UInt64(values.count))] }
    }

    static func randomDay(_ generator: inout Generator, lines: Int) -> String {
        var events: [String] = []
        var tasks: [String] = []
        for number in 0..<lines {
            var line = generator.pick(prefixes)
            for _ in 0..<(1 + generator.next() % 7) {
                line += generator.pick(fragments) + generator.pick(["", " ", " ", " ", "  "])
            }
            if generator.next() % 3 == 0 { line += " ^r\(number)" }
            // Only a top-level bullet without a checkbox is an event.
            if line.hasPrefix("- [") || !"-*+".contains(line.prefix(1)) {
                tasks.append(line)
            } else {
                events.append(line)
            }
        }
        return "## Events\n" + events.joined(separator: "\n") + "\n\n## Tasks\n" + tasks.joined(separator: "\n") + "\n"
    }
}
