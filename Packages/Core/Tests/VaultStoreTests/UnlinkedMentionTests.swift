import Foundation
import Testing
import VaultFormat

@testable import EntityRecognition
@testable import VaultIndex
@testable import VaultStore

/// `recognition/unlinked-mentions/expected.json` lists what the query returns for each entity of
/// `vaults/unlinked-mentions`; every `write/mention-*` case links one of those mentions.
struct UnlinkedMentionTests {
    struct Expected: Codable, Equatable {
        let file: String
        let date: String
        let line: Int
        let byteRange: [Int]
        let spelling: String
        let isExplicit: Bool
        let isAmbiguous: Bool
        let isCaseMismatch: Bool

        init(_ value: UnlinkedMention) {
            file = value.file
            date = value.date.description
            line = value.position.line
            byteRange = [value.position.byteRange.lowerBound, value.position.byteRange.upperBound]
            spelling = value.spelling
            isExplicit = value.isExplicit
            isAmbiguous = value.isAmbiguous
            isCaseMismatch = value.isCaseMismatch
        }
    }

    struct Query: Decodable {
        let entity: String
        let mentions: [Expected]
    }

    struct QueryFixture: Decodable {
        let vault: String
        let queries: [Query]
    }

    struct Operation: Decodable {
        struct Mention: Decodable {
            let vault: String
            let file: String
            let entity: String
            let line: Int
            let byteRange: [Int]
            let spelling: String
        }
        let mention: Mention
    }

    static let elif = "people/Elif.md"
    static let day = "journal/2026-10-10.md"

    static func writeCases() throws -> [String] {
        let directory = try Fixtures.root().appendingPathComponent("write")
        return try FileManager.default.contentsOfDirectory(atPath: directory.path)
            .filter { $0.hasPrefix("mention-") }.sorted()
    }

    static func queries() throws -> QueryFixture {
        let url = try Fixtures.root().appendingPathComponent("recognition/unlinked-mentions/expected.json")
        return try JSONDecoder().decode(QueryFixture.self, from: Data(contentsOf: url))
    }

    func setup(_ name: String = "unlinked-mentions") throws -> StoreVault {
        let vault = try StoreVault()
        do {
            let fixture = try Fixtures.root().appendingPathComponent("vaults/" + name)
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

    func entity(_ file: String, in vault: StoreVault) throws -> KnownEntity {
        try #require(vault.index.unlinkedMentionEntities().first { $0.file == file })
    }

    func mention(
        _ vault: StoreVault, entity file: String = elif, in path: String = day, line: Int, nth: Int = 0
    ) throws -> UnlinkedMention {
        let all = try vault.index.unlinkedMentions(of: entity(file, in: vault), vaultRoot: vault.root)
        return try #require(all.filter { $0.file == path && $0.position.line == line }.dropFirst(nth).first)
    }

    // MARK: - Query

    @Test func queryMatchesPortableFixture() throws {
        let fixture = try Self.queries()
        let vault = try setup(fixture.vault)
        defer { vault.remove() }
        #expect(try Set(fixture.queries.map(\.entity)) == Set(vault.index.unlinkedMentionEntities().map(\.file)))
        for query in fixture.queries {
            let actual = try vault.index.unlinkedMentions(of: entity(query.entity, in: vault), vaultRoot: vault.root)
            #expect(actual.map(Expected.init) == query.mentions, "\(query.entity)")
            for (mention, expected) in zip(actual, query.mentions) {
                let document = RawDocument(bytes: try vault.bytes(mention.file))
                let content = document.lines[mention.position.line].content
                // String equality is canonical; the spelling must also be the source's exact bytes.
                #expect(Array(mention.spelling.utf8) == Array(expected.spelling.utf8))
                #expect(content.elementsEqual(mention.lineText.utf8))
                #expect(content[mention.position.byteRange].elementsEqual(mention.spelling.utf8))
                #expect(mention.target.line == mention.position.line)
                #expect(mention.target.firstLineContent == content)
            }
        }
    }

    /// The search stage only narrows which files are read; it must never hide a recognized mention.
    @Test func searchCandidatesLoseNothingAgainstReadingEveryDay() throws {
        let vault = try setup()
        defer { vault.remove() }
        let entities = try vault.index.unlinkedMentionEntities()
        let everyDay = try vault.index.unlinkedMentionDays(naming: nil)
        #expect(everyDay.count == 3)
        for entity in entities {
            let exhaustive = try vault.index.unlinkedMentions(
                of: entity, entities: entities, days: everyDay, vaultRoot: vault.root)
            #expect(try vault.index.unlinkedMentions(of: entity, vaultRoot: vault.root) == exhaustive)
            #expect(!exhaustive.isEmpty)
        }
        // A name with a searchable word reads only the days that hold it.
        let place = try #require(entities.first { $0.file == "places/İstanbul.md" })
        #expect(try vault.index.unlinkedMentionDays(naming: place).map(\.path) == ["journal/2026-10-08.md"])
    }

    /// Spellings the recognizer accepts must reach it whatever the tokenizer makes of them.
    @Test func turkishAndPunctuatedSpellingsAreSearchCandidates() throws {
        let vault = try StoreVault()
        defer { vault.remove() }
        try vault.write(
            "places/İstanbul.md",
            "---\ntype: place\nname: İstanbul\naliases: [Işık, Ali-Can, O'Neil, Ünal Şen, \"%\"]\n---\n")
        // Turkish capitals fold first (`İ` → `i`, `I` → `ı`); the index tokenizer lowercases only `I`.
        let recognized = [
            "i\u{0307}stanbul yolu", "İstanbul'da", "İSTANBUL’dan", "istanbul", "Işık'ın", "ışık geldi", "IŞIK", "IşIk",
            "ali-can", "o'neil", "ÜNAL  ŞEN", "u\u{0308}nal s\u{0327}en", "(İstanbul)", "\"Işık\"", "x_Işık",
            "İstanbul.", "İstanbul/Ankara", "yüzde % elli",
        ]
        let unrecognized = ["ISTANBUL", "işık", "Ali–Can", "O’Neil", "İstanbullu"]
        for (number, line) in (recognized + unrecognized).enumerated() {
            try vault.write(String(format: "journal/2026-01-%02d.md", number + 1), "## Events\n- \(line)\n")
        }
        try vault.index.rebuild(vaultRoot: vault.root)
        let entities = try vault.index.unlinkedMentionEntities()
        let place = try #require(entities.first)
        let found = try vault.index.unlinkedMentions(of: place, vaultRoot: vault.root)
        let expected = recognized.indices.map { String(format: "journal/2026-01-%02d.md", $0 + 1) }
        #expect(found.map(\.file).sorted() == expected)
        #expect(
            try vault.index.unlinkedMentions(
                of: place, entities: entities, days: vault.index.unlinkedMentionDays(naming: nil),
                vaultRoot: vault.root) == found)

        // Without the symbol-only alias the search narrows, and still loses none of the worded spellings.
        try vault.write(
            "places/İstanbul.md", "---\ntype: place\nname: İstanbul\naliases: [Işık, Ali-Can, O'Neil, Ünal Şen]\n---\n")
        try vault.index.update(paths: ["places/İstanbul.md"], vaultRoot: vault.root)
        let worded = try #require(vault.index.unlinkedMentionEntities().first)
        let candidates = try vault.index.unlinkedMentionDays(naming: worded).map(\.path)
        #expect(Set(candidates).isSuperset(of: expected.dropLast()))
        #expect(candidates.count < recognized.count + unrecognized.count)
        #expect(
            try vault.index.unlinkedMentions(of: worded, vaultRoot: vault.root).map(\.file).sorted()
                == Array(expected.dropLast()))
    }

    @Test func queryReadsOnlyCandidateDays() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let manifest = try SyntheticVault.generate(at: root, configuration: .compact)
        let reader = CountingReader()
        let index = try VaultIndex(readFile: reader.read)
        try index.rebuild(vaultRoot: root)
        let day = "journal/" + manifest.endDate.description + ".md"
        let person = "people/Quillon Vexmoor.md"
        let url = root.appendingPathComponent(day)
        var text = String(decoding: try Data(contentsOf: url), as: UTF8.self)
        text += "\n## Tasks\n- [ ] Quillon Vexmoor ile konuş\n"
        try Data(text.utf8).write(to: url)
        try Data("---\ntype: person\nname: Quillon Vexmoor\n---\n".utf8).write(to: root.appendingPathComponent(person))
        try index.update(paths: [day, person], vaultRoot: root)
        let entity = try #require(index.unlinkedMentionEntities().first { $0.file == person })
        #expect(try index.unlinkedMentionDays(naming: nil).count == SyntheticVault.Configuration.compact.days)
        #expect(try index.unlinkedMentionDays(naming: entity).map(\.path) == [day])
        reader.reset()
        let mentions = try index.unlinkedMentions(of: entity, vaultRoot: root)
        #expect(mentions.map(\.file) == [day])
        #expect(mentions.map(\.spelling) == ["Quillon Vexmoor"])
        #expect(reader.markdownPaths(under: root) == [day])
    }

    @Test func unknownEntityAndUnindexedDayListNothing() throws {
        let vault = try setup()
        defer { vault.remove() }
        let stranger = KnownEntity(file: "people/Yok.md", kind: .person, name: "Elif")
        #expect(try vault.index.unlinkedMentions(of: stranger, vaultRoot: vault.root).isEmpty)
        // A day that vanished after indexing is skipped rather than failing the whole list.
        try FileManager.default.removeItem(at: vault.root.appendingPathComponent("journal/2026-10-09.md"))
        let remaining = try vault.index.unlinkedMentions(of: entity(Self.elif, in: vault), vaultRoot: vault.root)
        #expect(Set(remaining.map(\.file)) == ["journal/2026-10-10.md", "journal/2026-10-08.md"])
    }

    // MARK: - Writer

    @Test(arguments: try writeCases())
    func linkingWritesOnlyTheMention(name: String) async throws {
        let directory = try Fixtures.root().appendingPathComponent("write/" + name)
        let operation = try JSONDecoder().decode(
            Operation.self, from: Data(contentsOf: directory.appendingPathComponent("operation.json"))
        ).mention
        let input = try Data(contentsOf: directory.appendingPathComponent("input.md"))
        let expected = try Data(contentsOf: directory.appendingPathComponent("expected.md"))
        let vault = try setup(operation.vault)
        defer { vault.remove() }
        try input.write(to: vault.root.appendingPathComponent(operation.file))
        try vault.index.update(paths: [operation.file], vaultRoot: vault.root)

        let entity = try entity(operation.entity, in: vault)
        let range = operation.byteRange[0]..<operation.byteRange[1]
        let mentions = try vault.index.unlinkedMentions(of: entity, vaultRoot: vault.root)
        let selected = try #require(
            mentions.first {
                $0.file == operation.file && $0.position == MentionPosition(line: operation.line, byteRange: range)
            })
        #expect(Array(selected.spelling.utf8) == Array(operation.spelling.utf8))
        let untouched = try snapshot(vault, except: operation.file)

        let before = RawDocument(bytes: input)
        let after = try await vault.store.linkingMention(selected, to: entity)
        #expect(try vault.bytes(operation.file) == expected)
        #expect(after.serialized() == Array(expected))
        #expect(try snapshot(vault, except: operation.file) == untouched)

        // Reading the written file again shows one more link, on that line, to that entity, and nothing else.
        let reread = RawDocument(bytes: expected)
        #expect(reread == after)
        #expect(reread.lines.count == before.lines.count)
        for index in before.lines.indices where index != operation.line {
            #expect(reread.lines[index] == before.lines[index])
        }
        #expect(reread.lines[operation.line].ending == before.lines[operation.line].ending)
        let added = reread.links.filter { !before.links.contains($0) }
        #expect(added.count == 1)
        #expect(reread.links.count == before.links.count + 1)
        #expect(added.first?.line == operation.line)
        #expect(added.first?.target == entity.linkTarget)
        #expect(
            try vault.index.links(to: operation.entity).filter { $0.file == operation.file }.count
                == before.links.filter { $0.target == entity.linkTarget }.count + 1)
        #expect(reread.bodyLines.events.map(\.time) == before.bodyLines.events.map(\.time))
        #expect(reread.bodyLines.events.map(\.block.id) == before.bodyLines.events.map(\.block.id))
        #expect(reread.bodyLines.tasks.map(\.block.lineRange) == before.bodyLines.tasks.map(\.block.lineRange))
        #expect(reread.bodyLines.tasks.map(\.dueDate) == before.bodyLines.tasks.map(\.dueDate))
        #expect(reread.bodyLines.tasks.map(\.doneDate) == before.bodyLines.tasks.map(\.doneDate))
        #expect(reread.bodyLines.tasks.map(\.project) == before.bodyLines.tasks.map(\.project))

        // The linked mention leaves the list; every other one stays, at its new place on that line.
        let remaining = try vault.index.unlinkedMentions(of: entity, vaultRoot: vault.root)
        #expect(remaining.count == mentions.count - 1)
        let growth = expected.count - input.count
        let shifted = mentions.filter { $0 != selected }.map { mention -> Expected in
            var value = Expected(mention)
            if mention.file == operation.file, mention.position.line == operation.line,
                mention.position.byteRange.lowerBound > range.lowerBound
            {
                value = Expected(value, shiftedBy: growth)
            }
            return value
        }
        #expect(remaining.map(Expected.init) == shifted)

        // Incremental index after the write equals a full rebuild, including this query.
        try vault.check()
        let rebuilt = try VaultIndex()
        try rebuilt.rebuild(vaultRoot: vault.root)
        #expect(try rebuilt.unlinkedMentions(of: entity, vaultRoot: vault.root) == remaining)

        // The stale value of the mention just linked can never be applied twice.
        await #expect(throws: VaultStoreError.staleTarget) {
            try await vault.store.linkingMention(selected, to: entity)
        }
        #expect(try vault.bytes(operation.file) == expected)
    }

    @Test func bothOccurrencesOnALineLinkOneAfterTheOther() async throws {
        let vault = try setup()
        defer { vault.remove() }
        let entity = try entity(Self.elif, in: vault)
        let second = try mention(vault, line: 13, nth: 1)
        #expect(second.position.byteRange == 13..<17)
        try await vault.store.linkingMention(second, to: entity)
        let first = try mention(vault, line: 13)
        #expect(first.position.byteRange == 2..<6)
        try await vault.store.linkingMention(first, to: entity)
        let line = RawDocument(bytes: try vault.bytes(Self.day)).lines[13]
        #expect(String(decoding: line.content, as: UTF8.self) == "- [[Elif]] sonra [[Elif]]. ^double")
        let left = try vault.index.unlinkedMentions(of: entity, vaultRoot: vault.root)
        #expect(!left.contains { $0.file == Self.day && $0.position.line == 13 })
        try vault.check()
    }

    @Test(arguments: [
        "lineChanged", "spellingChanged", "alreadyLinked", "otherOccurrenceLinked", "lineShifted", "lineDeleted",
        "fileDeleted", "entityDeleted", "aliasRemoved", "sharedAliasRemoved",
    ])
    func staleTargetNeverWrites(change: String) async throws {
        let vault = try setup()
        defer { vault.remove() }
        let entity = try entity(Self.elif, in: vault)
        let selected: UnlinkedMention
        switch change {
        case "otherOccurrenceLinked": selected = try mention(vault, line: 13, nth: 1)
        case "aliasRemoved": selected = try mention(vault, line: 8)
        case "sharedAliasRemoved": selected = try mention(vault, line: 9)
        default: selected = try mention(vault, line: 7)
        }
        let url = vault.root.appendingPathComponent(selected.file)
        let original = try vault.bytes(selected.file)
        var text = String(decoding: original, as: UTF8.self)
        var changedPaths: [String] = []
        switch change {
        case "lineChanged": text = text.replacingOccurrences(of: "konuştum.", with: "konuştuk.")
        case "spellingChanged": text = text.replacingOccurrences(of: "Elif'le", with: "Lale'le")
        case "alreadyLinked": text = text.replacingOccurrences(of: "Elif'le", with: "[[Elif]]'le")
        case "otherOccurrenceLinked":
            text = text.replacingOccurrences(of: "- Elif sonra Elif.", with: "- [[Elif]] sonra Elif.")
        case "lineShifted": text = text.replacingOccurrences(of: "## Events\n", with: "## Events\n- Yeni olay.\n")
        case "lineDeleted": text = text.replacingOccurrences(of: selected.lineText + "\n", with: "")
        case "fileDeleted": try FileManager.default.removeItem(at: url)
        case "entityDeleted":
            try FileManager.default.removeItem(at: vault.root.appendingPathComponent(Self.elif))
            changedPaths = [Self.elif]
        default:
            try vault.write(Self.elif, "---\ntype: person\nname: Elif\n---\n")
            changedPaths = [Self.elif]
        }
        #expect(change == "fileDeleted" || !changedPaths.isEmpty || Data(text.utf8) != original)
        if change != "fileDeleted" { try Data(text.utf8).write(to: url) }
        // The index learns about entity changes; it deliberately does not learn about the day's change.
        try vault.index.update(paths: Set(changedPaths), vaultRoot: vault.root)
        let index = try vault.index.snapshot()
        let files = try snapshot(vault, except: "")
        await #expect(throws: VaultStoreError.staleTarget) {
            try await vault.store.linkingMention(selected, to: entity)
        }
        #expect(try snapshot(vault, except: "") == files)
        #expect(FileManager.default.fileExists(atPath: url.path) == (change != "fileDeleted"))
        #expect(try vault.index.snapshot() == index)
    }

    /// Every spelling of the entity's name on a line, wherever it stands, as a mention the recognizer might hand over.
    static func plainMentions(of entity: KnownEntity, onLine line: Int, of document: RawDocument) -> [Mention] {
        let content = Array(document.lines[line].content)
        let name = Array(entity.name.utf8)
        return content.indices.filter { content[$0...].starts(with: name) }.map {
            Mention(
                position: MentionPosition(line: line, byteRange: $0..<($0 + name.count)), spelling: entity.name,
                candidates: [entity], isCaseMismatch: false, isExplicit: false, isAlias: false)
        }
    }

    /// The last gate before a write: one link over the mention, and the same events, tasks and bytes otherwise.
    @Test(arguments: [
        ["- 12:30 Öğle arası\n", "12", "false"], ["- [ ] Ara 📅 2026-10-12\n", "2026", "false"],
        ["- [ ] 7 gün 🔁 every 7 days\n", "7", "true"], ["- 12:30 Elif'le Öğle\n", "Elif", "true"],
        ["\u{FEFF}- [x] Elif ✅ 2026-10-08 ^t1\r\n  alt satır", "Elif", "true"],
    ])
    func gateAcceptsOnlyAStructurePreservingLink(arguments: [String]) throws {
        let text = "## Events\n" + arguments[0]
        let entity = KnownEntity(file: "people/\(arguments[1]).md", kind: .person, name: arguments[1])
        let source = RawDocument(bytes: text.utf8)
        // The recognizer reads neither a clock, nor a field, nor a plainly written digit-only name, so
        // the gate is handed the name's first spelling on the line: it must hold whoever calls it.
        let mention = try #require(Self.plainMentions(of: entity, onLine: 1, of: source).first)
        let linked = RawDocument(bytes: try EntityRecognizer.linking(text, mentions: [mention]).utf8)
        #expect(linked != source)
        #expect(VaultStore.isSingleLink(linked, replacing: mention, in: source, to: entity) == (arguments[2] == "true"))
        if arguments[2] == "true" {
            // Any other difference, however small, is refused.
            let extra = RawDocument(bytes: linked.serialized() + Array(" ".utf8))
            #expect(!VaultStore.isSingleLink(extra, replacing: mention, in: source, to: entity))
            let heading = RawDocument(bytes: Array(linked.serialized().dropFirst(text.hasPrefix("\u{FEFF}") ? 4 : 1)))
            #expect(!VaultStore.isSingleLink(heading, replacing: mention, in: source, to: entity))
            #expect(!VaultStore.isSingleLink(source, replacing: mention, in: source, to: entity))
        }
    }

    @Test func unrepresentableLinkTargetListsNothing() throws {
        let vault = try setup()
        defer { vault.remove() }
        try vault.write("people/Kod#1.md", "---\ntype: person\nname: Kodcu\n---\n")
        try vault.write("journal/2026-10-07.md", "## Events\n- Kodcu geldi.\n")
        try vault.index.update(paths: ["people/Kod#1.md", "journal/2026-10-07.md"], vaultRoot: vault.root)
        let coder = try entity("people/Kod#1.md", in: vault)
        #expect(coder.linkTarget == "Kod#1")
        #expect(try vault.index.unlinkedMentionDays(naming: coder).map(\.path) == ["journal/2026-10-07.md"])
        #expect(try vault.index.unlinkedMentions(of: coder, vaultRoot: vault.root).isEmpty)
    }

    /// A digit-only name or alias is listed where the user wrote it with an at sign and nowhere else.
    @Test func digitOnlyNameIsListedOnlyWhereItIsExplicit() async throws {
        let vault = try setup()
        defer { vault.remove() }
        let day = "journal/2026-10-07.md"
        let text =
            "## Events\n- 12:30 @12 kişi geldi, 12 kişi kaldı, 34 plakalı araç ^e1\n- 12 Ekim 2026, Otoyol ve @34\n"
            + "## Tasks\n- [ ] 12 kişiyi ara, @12 📅 2026-10-12\n"
        try vault.write("places/12.md", "---\ntype: place\nname: 12\n---\n")
        try vault.write("places/Otoyol.md", "---\ntype: place\nname: Otoyol\naliases: [\"34\", \"2026\"]\n---\n")
        try vault.write(day, text)
        try vault.index.update(paths: ["places/12.md", "places/Otoyol.md", day], vaultRoot: vault.root)
        let twelve = try entity("places/12.md", in: vault)
        let road = try entity("places/Otoyol.md", in: vault)
        let listed = try vault.index.unlinkedMentions(of: twelve, vaultRoot: vault.root)
        #expect(listed.map(\.position) == [.init(line: 1, byteRange: 9..<11), .init(line: 4, byteRange: 23..<25)])
        #expect(listed.allSatisfy { $0.isExplicit && $0.spelling == "12" })
        let roads = try vault.index.unlinkedMentions(of: road, vaultRoot: vault.root)
        #expect(roads.map(\.spelling) == ["Otoyol", "34"])
        #expect(roads.map(\.isExplicit) == [false, true])
        try await vault.store.linkingMention(try #require(listed.first), to: twelve)
        #expect(
            String(decoding: try vault.bytes(day), as: UTF8.self)
                == text.replacingOccurrences(of: "12:30 @12 kişi", with: "12:30 [[12]] kişi"))
    }

    /// The writer works on the bytes it reads under the write queue, not on what the query saw.
    @Test func externalEditsElsewhereInTheFileSurvive() async throws {
        let vault = try setup()
        defer { vault.remove() }
        let selected = try mention(vault, line: 7)
        let url = vault.root.appendingPathComponent(selected.file)
        let edited = String(decoding: try vault.bytes(selected.file), as: UTF8.self)
            .replacingOccurrences(of: "- Lale geldi.", with: "- Lale gitti; dışarıda yazıldı.")
            .replacingOccurrences(of: "Elif burada paragrafta.", with: "Paragraf dışarıda değişti.  ")
        try Data(edited.utf8).write(to: url)
        try await vault.store.linkingMention(selected, to: entity(Self.elif, in: vault))
        let expected = edited.replacingOccurrences(of: "- 09:05 Elif'le", with: "- 09:05 [[Elif]]'le")
        #expect(try vault.bytes(selected.file) == Data(expected.utf8))
        try vault.check()
    }

    @Test func invalidUTF8DayIsNeitherListedNorWritten() async throws {
        let vault = try setup()
        defer { vault.remove() }
        let selected = try mention(vault, line: 7)
        let broken = try vault.bytes(selected.file) + Data([0xFF, 0x0A])
        try broken.write(to: vault.root.appendingPathComponent(selected.file))
        await #expect(throws: EditError.readOnlyDocument) {
            try await vault.store.linkingMention(selected, to: entity(Self.elif, in: vault))
        }
        #expect(try vault.bytes(selected.file) == broken)
        let listed = try vault.index.unlinkedMentions(of: entity(Self.elif, in: vault), vaultRoot: vault.root)
        #expect(!listed.contains { $0.file == selected.file })
    }

    private func snapshot(_ vault: StoreVault, except path: String) throws -> [String: Data] {
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
}

extension UnlinkedMentionTests.Expected {
    init(_ value: Self, shiftedBy bytes: Int) {
        self.init(
            file: value.file, date: value.date, line: value.line,
            byteRange: value.byteRange.map { $0 + bytes }, spelling: value.spelling, isExplicit: value.isExplicit,
            isAmbiguous: value.isAmbiguous, isCaseMismatch: value.isCaseMismatch)
    }

    init(
        file: String, date: String, line: Int, byteRange: [Int], spelling: String, isExplicit: Bool,
        isAmbiguous: Bool, isCaseMismatch: Bool
    ) {
        self.file = file
        self.date = date
        self.line = line
        self.byteRange = byteRange
        self.spelling = spelling
        self.isExplicit = isExplicit
        self.isAmbiguous = isAmbiguous
        self.isCaseMismatch = isCaseMismatch
    }
}
