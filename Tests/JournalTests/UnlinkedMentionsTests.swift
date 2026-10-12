import EntityRecognition
import Foundation
import Testing
import VaultFormat
import VaultIndex
import VaultStore

@testable import Journal

@MainActor
struct UnlinkedMentionsTestContext {
    let directory: URL
    let root: URL
    let defaults: TestDefaults
    let store: IndexStore
    let fixtures: URL

    init() throws {
        directory = try testDirectory()
        root = directory.appendingPathComponent("Vault")
        defaults = try TestDefaults()
        fixtures = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
            .deletingLastPathComponent().appendingPathComponent("Fixtures")
        try FileManager.default.copyItem(at: fixtures.appendingPathComponent("vaults/unlinked-mentions"), to: root)
        store = IndexStore(
            location: VaultLocation(defaults: defaults.defaults, documentsURL: directory, bookmarks: pathBookmarks()),
            supportURL: directory.appendingPathComponent("indexes"))
    }

    func start() async { await store.select(root) }

    func elif() throws -> KnownEntity {
        try #require(store.knownEntities.first { $0.file == "people/Elif.md" })
    }

    func model() -> UnlinkedMentionsModel { UnlinkedMentionsModel(store: store) }

    func clean() {
        defaults.clean()
        try? FileManager.default.removeItem(at: directory)
    }
}

@MainActor @Suite(.timeLimit(.minutes(1)))
struct UnlinkedMentionsTests {
    @Test func loadingMatchesTheFixtureAndAFailedQueryClearsTheList() async throws {
        let context = try UnlinkedMentionsTestContext()
        defer { context.clean() }
        let model = context.model()
        let placeholder = KnownEntity(file: "people/Elif.md", kind: .person, name: "Elif")
        await model.load(placeholder)
        #expect(model.hasLoaded && model.mentions.isEmpty)

        await context.start()
        let entity = try context.elif()
        await model.load(entity)
        let expected = try Self.expectedMentions(in: context.fixtures, entity: "people/Elif.md")
        #expect(model.hasLoaded)
        #expect(model.mentions.count == expected.count)
        #expect(model.mentions.map(Self.identity) == expected)

        model.testingQuery = { _ in throw VaultStoreError.staleTarget }
        await model.load(entity)
        #expect(model.hasLoaded && model.mentions.isEmpty)
    }

    @Test func linkingRewritesOnlyTheMentionAndRefreshesTheList() async throws {
        let context = try UnlinkedMentionsTestContext()
        defer { context.clean() }
        await context.start()
        let entity = try context.elif()
        let model = context.model()
        await model.load(entity)
        let mention = try #require(
            model.mentions.first {
                $0.file == "journal/2026-10-10.md" && $0.isExplicit && $0.spelling == "Elif"
            })
        let beforeCount = model.mentions.count
        let beforeFiles = try Self.vaultFiles(context.root)
        let beforeBytes = try #require(beforeFiles[mention.file])
        let beforeIncoming = try #require(context.store.content.entities.first { $0.id == entity.file }).incomingLinks
        let beforeRows = try await Self.rows(on: mention.date, path: entity.file, store: context.store)

        let outcome = await model.link(mention, to: entity)
        #expect(outcome == .linked)
        #expect(model.notice == nil)
        #expect(!model.mentions.contains { $0.position == mention.position && $0.file == mention.file })
        #expect(model.mentions.count == beforeCount - 1)

        let after = try Data(contentsOf: context.root.appendingPathComponent(mention.file))
        try Self.expectOnlySpanChanged(before: [UInt8](beforeBytes), after: [UInt8](after), mention: mention)
        let afterFiles = try Self.vaultFiles(context.root)
        for (path, bytes) in beforeFiles where path != mention.file {
            #expect(afterFiles[path] == bytes)
        }
        let summary = try #require(context.store.content.entities.first { $0.id == entity.file })
        #expect(summary.incomingLinks == beforeIncoming + 1)
        #expect(try await Self.rows(on: mention.date, path: entity.file, store: context.store) == beforeRows + 1)
    }

    @Test func linkingOneOfTwoOccurrencesKeepsTheOtherAtItsNewRange() async throws {
        let context = try UnlinkedMentionsTestContext()
        defer { context.clean() }
        await context.start()
        let entity = try context.elif()
        let model = context.model()
        await model.load(entity)
        let pair = model.mentions.filter {
            $0.file == "journal/2026-10-10.md" && $0.spelling == "Elif" && $0.lineText.contains("sonra")
        }
        #expect(pair.count == 2)
        let first = pair[0]
        let second = pair[1]
        #expect(first.position.byteRange.lowerBound < second.position.byteRange.lowerBound)
        let before = try Data(contentsOf: context.root.appendingPathComponent(first.file))

        #expect(await model.link(first, to: entity) == .linked)
        let remaining = model.mentions.filter {
            $0.file == first.file && $0.spelling == "Elif" && $0.lineText.contains("sonra")
        }
        let shifted = try #require(remaining.first)
        #expect(remaining.count == 1)
        #expect(shifted.position.byteRange != second.position.byteRange)
        let midway = try Data(contentsOf: context.root.appendingPathComponent(first.file))
        try Self.expectOnlySpanChanged(before: [UInt8](before), after: [UInt8](midway), mention: first)

        #expect(await model.link(shifted, to: entity) == .linked)
        #expect(
            !model.mentions.contains { $0.file == first.file && $0.spelling == "Elif" && $0.lineText.contains("sonra") }
        )
        let after = try Data(contentsOf: context.root.appendingPathComponent(first.file))
        try Self.expectOnlySpanChanged(before: [UInt8](midway), after: [UInt8](after), mention: shifted)
    }

    @Test func aStaleLineIsNotWrittenAndTheNoticeStaysUp() async throws {
        let context = try UnlinkedMentionsTestContext()
        defer { context.clean() }
        await context.start()
        let entity = try context.elif()
        let model = context.model()
        await model.load(entity)
        let mention = try #require(
            model.mentions.first { $0.file == "journal/2026-10-09.md" && $0.spelling == "Elif" })
        let url = context.root.appendingPathComponent(mention.file)
        var text = String(decoding: try Data(contentsOf: url), as: UTF8.self)
        #expect(text.components(separatedBy: mention.lineText).count == 2)
        text = text.replacingOccurrences(of: mention.lineText, with: "X" + mention.lineText)
        let mutated = Data(text.utf8)
        try mutated.write(to: url)

        let outcome = await model.link(mention, to: entity)
        #expect(outcome == .stale)
        #expect(model.notice == .stale)
        model.dismissNotice()
        #expect(model.notice == nil)
        #expect(try Data(contentsOf: url) == mutated)
        #expect(!model.mentions.contains { $0.file == mention.file && $0.position == mention.position })
    }

    @Test func anotherVaultDropsThePreviousList() async throws {
        let context = try UnlinkedMentionsTestContext()
        defer { context.clean() }
        await context.start()
        let entity = try context.elif()
        let model = context.model()
        await model.load(entity)
        #expect(!model.mentions.isEmpty)

        let other = context.directory.appendingPathComponent("Other")
        try FileManager.default.createDirectory(at: other, withIntermediateDirectories: true)
        await context.store.select(other)
        await model.load(entity)
        #expect(model.mentions.isEmpty && model.hasLoaded)
    }

    @Test func aSecondLinkWhileOneIsWritingIsRefused() async throws {
        let context = try UnlinkedMentionsTestContext()
        defer { context.clean() }
        await context.start()
        let entity = try context.elif()
        let model = context.model()
        await model.load(entity)
        let first = try #require(model.mentions.first { $0.file == "journal/2026-10-10.md" })
        let second = try #require(model.mentions.first { $0.file == "journal/2026-10-09.md" })
        let untouched = try Data(contentsOf: context.root.appendingPathComponent(second.file))
        let gate = ArrivalGate()
        model.testingHoldBeforeWrite = {
            _ = await gate.holdIfFirst()
        }

        let running = Task { await model.link(first, to: entity) }
        await gate.waitUntilFirst()
        let refused = await model.link(second, to: entity)
        #expect(refused == .busy)
        #expect(try Data(contentsOf: context.root.appendingPathComponent(second.file)) == untouched)
        await gate.open()
        #expect(await running.value == .linked)
        #expect(try Data(contentsOf: context.root.appendingPathComponent(second.file)) == untouched)
    }

    @Test func aReloadRacingTheLinkKeepsRowsLockedUntilTheListIsFresh() async throws {
        let context = try UnlinkedMentionsTestContext()
        defer { context.clean() }
        await context.start()
        let entity = try context.elif()
        let model = context.model()
        await model.load(entity)
        let pair = model.mentions.filter { $0.file == "journal/2026-10-10.md" && $0.lineText.contains("sonra") }
        #expect(pair.count == 2)
        let store = context.store
        let gate = QueryGate()
        model.testingQuery = { entity in
            await gate.enter()
            return try await store.computeUnlinkedMentions(of: entity)
        }

        // The link's own re-read starts, then the page's reload for the published index overtakes it.
        let running = Task { await model.link(pair[0], to: entity) }
        await gate.waitForArrival(1)
        let reload = Task { await model.load(entity) }
        await gate.waitForArrival(2)
        gate.release(1)
        #expect(await running.value == .linked)
        let written = try Data(contentsOf: context.root.appendingPathComponent(pair[0].file))

        // The rows on screen are still the old ones: a tap now must not reach the writer.
        #expect(!model.canLink)
        #expect(await model.link(pair[1], to: entity) == .busy)
        #expect(model.notice == nil)
        #expect(try Data(contentsOf: context.root.appendingPathComponent(pair[0].file)) == written)

        gate.release(2)
        await reload.value
        #expect(model.canLink)
        let remaining = model.mentions.filter { $0.file == pair[0].file && $0.lineText.contains("sonra") }
        #expect(remaining.count == 1)
        #expect(remaining.first?.position.byteRange != pair[1].position.byteRange)
    }

    @Test func aLinkThatEndsOnAnotherEntitysPageLeavesThatPageAlone() async throws {
        let context = try UnlinkedMentionsTestContext()
        defer { context.clean() }
        await context.start()
        let entity = try context.elif()
        let ece = try #require(context.store.knownEntities.first { $0.file == "people/Ece.md" })
        let model = context.model()
        await model.load(ece)
        let eceRows = model.mentions.map(\.rowIdentity)
        #expect(!eceRows.isEmpty)
        await model.load(entity)
        let mention = try #require(model.mentions.first { $0.file == "journal/2026-10-09.md" })
        let gate = ArrivalGate()
        model.testingHoldBeforeWrite = { _ = await gate.holdIfFirst() }

        let running = Task { await model.link(mention, to: entity) }
        await gate.waitUntilFirst()
        await model.load(ece)
        await gate.open()
        #expect(await running.value == .linked)
        #expect(model.entity?.file == ece.file)
        #expect(model.mentions.map(\.rowIdentity) == eceRows)
        #expect(model.notice == nil && model.canLink)

        // A refusal that arrives on the other page is not that page's news either.
        await model.load(entity)
        let older = try #require(model.mentions.first { $0.file == "journal/2026-10-08.md" })
        try Data("## Events\n".utf8).write(to: context.root.appendingPathComponent(older.file))
        let second = ArrivalGate()
        model.testingHoldBeforeWrite = { _ = await second.holdIfFirst() }
        let refused = Task { await model.link(older, to: entity) }
        await second.waitUntilFirst()
        await model.load(ece)
        await second.open()
        #expect(await refused.value == .stale)
        #expect(model.entity?.file == ece.file)
        #expect(model.notice == nil && model.canLink)
    }

    @Test func aVaultSelectedWhileTheWriteWaitsIsNotWritten() async throws {
        let context = try UnlinkedMentionsTestContext()
        defer { context.clean() }
        await context.start()
        let entity = try context.elif()
        let model = context.model()
        await model.load(entity)
        let mention = try #require(model.mentions.first { $0.file == "journal/2026-10-09.md" })
        // The other vault holds the very same line, so only the vault check can refuse the write.
        let other = context.directory.appendingPathComponent("Other")
        try FileManager.default.copyItem(at: context.root, to: other)
        let before = try Self.vaultFiles(context.root)
        let store = context.store
        model.testingHoldBeforeWrite = { await store.select(other) }

        #expect(await model.link(mention, to: entity) == .stale)
        #expect(try Self.vaultFiles(other) == before)
        #expect(try Self.vaultFiles(context.root) == before)
        #expect(model.notice == nil)
    }

    @Test func anAmbiguousSpellingIsLinkedToThisPagesEntityOnly() async throws {
        let context = try UnlinkedMentionsTestContext()
        defer { context.clean() }
        await context.start()
        let entity = try context.elif()
        let model = context.model()
        await model.load(entity)
        let mention = try #require(model.mentions.first { $0.isAmbiguous && $0.spelling == "Ortak" })
        let url = context.root.appendingPathComponent(mention.file)
        let before = [UInt8](try Data(contentsOf: url))

        #expect(await model.link(mention, to: entity) == .linked)
        let after = [UInt8](try Data(contentsOf: url))
        try Self.expectOnlySpanChanged(before: before, after: after, mention: mention)
        let origin = try Self.lineStart(in: before, line: mention.position.line)
        let start = origin + mention.position.byteRange.lowerBound
        let link = Array("[[Elif|Ortak]]".utf8)
        #expect(Array(after[start..<(start + link.count)]) == link)
    }

    @Test func aSavedLinkTheIndexCouldNotFollowIsNotOfferedAgain() async throws {
        let context = try UnlinkedMentionsTestContext()
        defer { context.clean() }
        await context.start()
        let entity = try context.elif()
        let model = context.model()
        await model.load(entity)
        let mention = try #require(model.mentions.first { $0.file == "journal/2026-10-09.md" })
        let count = model.mentions.count
        let store = context.store
        model.testingWrite = { mention, entity in
            try await store.linkUnlinkedMention(mention, to: entity, readFrom: store.vaultURL)
            throw VaultStoreError.indexUpdateFailed(path: mention.file, underlying: CocoaError(.fileWriteUnknown))
        }

        #expect(await model.link(mention, to: entity) == .savedNotIndexed)
        #expect(model.notice == .savedNotIndexed)
        #expect(model.mentions.count == count - 1)
        #expect(!model.mentions.contains { $0.file == mention.file })
        #expect(model.canLink)
    }

    @Test func aRefusedLinkSaysSoAndKeepsTheRows() async throws {
        let context = try UnlinkedMentionsTestContext()
        defer { context.clean() }
        await context.start()
        let entity = try context.elif()
        let model = context.model()
        await model.load(entity)
        let rows = model.mentions.map(\.rowIdentity)
        let mention = try #require(model.mentions.first)
        let before = try Self.vaultFiles(context.root)
        model.testingWrite = { _, _ in throw EntityLinkError.unrepresentableMention }

        #expect(await model.link(mention, to: entity) == .failed)
        #expect(model.notice == .failed)
        #expect(model.mentions.map(\.rowIdentity) == rows)
        #expect(model.canLink)
        #expect(try Self.vaultFiles(context.root) == before)
    }

    @Test func aRowKeepsItsIdentityWhenItsFileChangesElsewhere() async throws {
        let context = try UnlinkedMentionsTestContext()
        defer { context.clean() }
        await context.start()
        let entity = try context.elif()
        let model = context.model()
        await model.load(entity)
        let explicit = try #require(model.mentions.first { $0.file == "journal/2026-10-10.md" && $0.isExplicit })
        let earlier = try #require(
            model.mentions.first { $0.file == explicit.file && $0.position.line < explicit.position.line })

        #expect(await model.link(explicit, to: entity) == .linked)
        let same = try #require(model.mentions.first { $0.rowIdentity == earlier.rowIdentity })
        // The value itself is new (it carries the file's digest), so it cannot identify the row.
        #expect(same != earlier)
        #expect(same.lineText == earlier.lineText)
    }

    @Test func rowsShowTheUsersTextWithTheReplacedBytesMarked() async throws {
        let context = try UnlinkedMentionsTestContext()
        defer { context.clean() }
        await context.start()
        let model = context.model()
        await model.load(try context.elif())
        let clocked = try #require(model.mentions.first { $0.file == "journal/2026-10-08.md" && $0.spelling == "Elif" })
        #expect(Self.shown(UnlinkedMentionLine.styled(clocked)) == "🎸 çaldı, Çağrı’yla şöyle: Elif geldi.")
        #expect(Self.emphasized(UnlinkedMentionLine.styled(clocked)) == "Elif")
        // Linking removes the at sign too, so the row marks it.
        let explicit = try #require(model.mentions.first { $0.isExplicit })
        #expect(Self.shown(UnlinkedMentionLine.styled(explicit)) == "@Elif'e yazdım.")
        #expect(Self.emphasized(UnlinkedMentionLine.styled(explicit)) == "@Elif")
        for mention in model.mentions {
            let styled = UnlinkedMentionLine.styled(mention)
            #expect(Self.emphasized(styled) == (mention.isExplicit ? "@" : "") + mention.spelling)
            #expect(!Self.shown(styled).contains("^"))
        }
    }

    @Test func aRangeThatDoesNotFitTheLineLeavesItPlain() {
        func styled(_ line: String, _ text: String, _ bytes: Range<Int>, _ spelling: String, explicit: Bool = false)
            -> AttributedString
        {
            UnlinkedMentionLine.styled(
                line: Array(line.utf8), text: text, bytes: bytes, spelling: spelling, isExplicit: explicit)
        }
        let city = "- 09:05 İstanbul'da [[Ece|bizim Ece]] 🎸 çaldı. ^abc123"
        let text = "İstanbul'da [[Ece|bizim Ece]] 🎸 çaldı."
        let lower = "- 09:05 ".utf8.count
        let upper = lower + "İstanbul".utf8.count
        let good = styled(city, text, lower..<upper, "İstanbul")
        #expect(Self.shown(good) == "İstanbul'da bizim Ece 🎸 çaldı.")
        #expect(Self.emphasized(good) == "İstanbul")

        let linkedFirst = styled(
            "- [[Ece|bizim Ece]] ile Elif geldi.", "[[Ece|bizim Ece]] ile Elif geldi.", 24..<28, "Elif")
        #expect(Self.shown(linkedFirst) == "bizim Ece ile Elif geldi.")
        #expect(Self.emphasized(linkedFirst) == "Elif")

        // Inside a two-byte letter, inside the emoji, off either end, empty, or not the spelling.
        let emoji = lower + "İstanbul'da [[Ece|bizim Ece]] ".utf8.count
        let unusable: [(Range<Int>, String)] = [
            ((lower + 1)..<upper, "İstanbul"), (lower..<(upper - 3), "İstanbul"), ((emoji + 1)..<(emoji + 3), "🎸"),
            (-1..<3, "- 0"), (city.utf8.count..<(city.utf8.count + 4), "İstanbul"), (5000..<5008, "İstanbul"),
            (lower..<lower, ""), (lower..<upper, "Istanbul."), (0..<1, "-"),
        ]
        for (bytes, spelling) in unusable {
            let plain = styled(city, text, bytes, spelling)
            #expect(Self.shown(plain) == "İstanbul'da bizim Ece 🎸 çaldı.")
            #expect(Self.emphasized(plain).isEmpty)
        }
        // A line that is not valid UTF-8 around the spelling, and a text the line does not hold.
        let broken = Array("- ".utf8) + [0xFF] + Array("Elif geldi.".utf8)
        let invalid = UnlinkedMentionLine.styled(
            line: broken, text: "\u{FFFD}Elif geldi.", bytes: 3..<7, spelling: "Elif", isExplicit: false)
        #expect(Self.emphasized(invalid).isEmpty)
        #expect(Self.emphasized(styled("- Elif geldi.", "Lale geldi.", 2..<6, "Elif")).isEmpty)

        // A combining mark right after the spelling, and an at sign that is only marked when explicit.
        let combined = styled("- Elif\u{301} geldi.", "Elif\u{301} geldi.", 2..<6, "Elif")
        #expect(String(Self.shown(combined).unicodeScalars.prefix(5)) == "Elif\u{301}")
        #expect(Self.emphasized(styled("- @Elif geldi.", "@Elif geldi.", 3..<7, "Elif", explicit: true)) == "@Elif")
        #expect(Self.emphasized(styled("- @Elif geldi.", "@Elif geldi.", 3..<7, "Elif")) == "Elif")
        #expect(Self.emphasized(styled("- Elif geldi.", "Elif geldi.", 2..<6, "Elif", explicit: true)) == "Elif")

        #expect(UnlinkedMentionList.visibleCount(total: 12, expanded: false) == 5)
        #expect(UnlinkedMentionList.visibleCount(total: 12, expanded: true) == 12)
        #expect(UnlinkedMentionList.visibleCount(total: 5, expanded: false) == 5)
        #expect(UnlinkedMentionList.showsAll(total: 6, expanded: false))
        #expect(!UnlinkedMentionList.showsAll(total: 5, expanded: false))
        #expect(!UnlinkedMentionList.showsAll(total: 6, expanded: true))
    }

    private static func shown(_ text: AttributedString) -> String { String(text.characters) }

    private static func rows(on date: CalendarDate, path: String, store: IndexStore) async throws -> Int {
        try await store.computeEntityTimeline(for: path).first { $0.date == date }?.rows.count ?? 0
    }

    private static func emphasized(_ text: AttributedString) -> String {
        text.runs.compactMap { run -> String? in
            guard run.inlinePresentationIntent == .stronglyEmphasized else { return nil }
            return String(text[run.range].characters)
        }.joined()
    }

    private static func identity(_ mention: UnlinkedMention) -> String {
        let range = mention.position.byteRange
        return [
            mention.file, mention.date.description, String(mention.position.line),
            "\(range.lowerBound)-\(range.upperBound)", mention.spelling,
            mention.isExplicit ? "1" : "0", mention.isAmbiguous ? "1" : "0", mention.isCaseMismatch ? "1" : "0",
        ].joined(separator: "|")
    }

    private static func expectedMentions(in fixtures: URL, entity: String) throws -> [String] {
        let url = fixtures.appendingPathComponent("recognition/unlinked-mentions/expected.json")
        let decoded = try JSONDecoder().decode(ExpectedQueries.self, from: Data(contentsOf: url))
        let query = try #require(decoded.queries.first { $0.entity == entity })
        return query.mentions.map {
            [
                $0.file, $0.date, String($0.line), "\($0.byteRange[0])-\($0.byteRange[1])", $0.spelling,
                $0.isExplicit ? "1" : "0", $0.isAmbiguous ? "1" : "0", $0.isCaseMismatch ? "1" : "0",
            ].joined(separator: "|")
        }
    }

    private static func vaultFiles(_ root: URL) throws -> [String: Data] {
        var result: [String: Data] = [:]
        guard let enumerator = FileManager.default.enumerator(at: root, includingPropertiesForKeys: [.isRegularFileKey])
        else { return result }
        let prefix = root.resolvingSymlinksInPath().standardizedFileURL.path + "/"
        for case let url as URL in enumerator {
            guard try url.resourceValues(forKeys: [.isRegularFileKey]).isRegularFile == true else { continue }
            let path = url.resolvingSymlinksInPath().standardizedFileURL.path
            result[String(path.dropFirst(prefix.count))] = try Data(contentsOf: url)
        }
        return result
    }

    /// The file differs only inside the spelling, plus a preceding `@` when the mention is explicit.
    private static func expectOnlySpanChanged(before: [UInt8], after: [UInt8], mention: UnlinkedMention) throws {
        let origin = try lineStart(in: before, line: mention.position.line)
        let start = origin + mention.position.byteRange.lowerBound - (mention.isExplicit ? 1 : 0)
        let end = origin + mention.position.byteRange.upperBound
        #expect(start >= origin && end <= before.count && start < end)
        let delta = after.count - before.count
        let insertedEnd = start + (end - start) + delta
        #expect(insertedEnd >= start && insertedEnd <= after.count)
        #expect(Array(before[..<start]) == Array(after[..<start]))
        #expect(Array(before[end...]) == Array(after[insertedEnd...]))
        let link = String(decoding: after[start..<insertedEnd], as: UTF8.self)
        #expect(link.hasPrefix("[[") && link.hasSuffix("]]") && link.contains(mention.spelling))
    }

    private static func lineStart(in bytes: [UInt8], line: Int) throws -> Int {
        var index = bytes.starts(with: [0xEF, 0xBB, 0xBF]) ? 3 : 0
        var current = 0
        while current < line {
            guard let newline = bytes[index...].firstIndex(of: 10) else {
                Issue.record("Satır bulunamadı")
                return bytes.count
            }
            current += 1
            index = newline + 1
        }
        return index
    }
}

private struct ExpectedQueries: Decodable {
    struct Query: Decodable {
        struct Mention: Decodable {
            var file: String
            var date: String
            var line: Int
            var byteRange: [Int]
            var spelling: String
            var isExplicit: Bool
            var isAmbiguous: Bool
            var isCaseMismatch: Bool
        }
        var entity: String
        var mentions: [Mention]
    }
    var queries: [Query]
}

/// Signals once the first link holds the write lock, then waits until the test opens the gate.
private actor ArrivalGate {
    private var entries = 0
    private var arrivedFlag = false
    private var arrived: CheckedContinuation<Void, Never>?
    private var release: CheckedContinuation<Void, Never>?
    private var released = false

    func holdIfFirst() async -> Int {
        entries += 1
        let count = entries
        if count == 1 {
            arrivedFlag = true
            arrived?.resume()
            arrived = nil
            if !released {
                await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
                    if released {
                        continuation.resume()
                    } else {
                        release = continuation
                    }
                }
            }
        }
        return count
    }

    func waitUntilFirst() async {
        if arrivedFlag { return }
        await withCheckedContinuation { arrived = $0 }
    }

    func open() {
        released = true
        release?.resume()
        release = nil
    }
}

/// Holds each query at its start until the test lets that one through.
@MainActor private final class QueryGate {
    private var calls = 0
    private var arrived: Set<Int> = []
    private var arrivals: [Int: CheckedContinuation<Void, Never>] = [:]
    private var holds: [Int: CheckedContinuation<Void, Never>] = [:]

    func enter() async {
        calls += 1
        let call = calls
        arrived.insert(call)
        arrivals.removeValue(forKey: call)?.resume()
        await withCheckedContinuation { holds[call] = $0 }
    }

    func waitForArrival(_ call: Int) async {
        if arrived.contains(call) { return }
        await withCheckedContinuation { arrivals[call] = $0 }
    }

    func release(_ call: Int) {
        holds.removeValue(forKey: call)?.resume()
    }
}
