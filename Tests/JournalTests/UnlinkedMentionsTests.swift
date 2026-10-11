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
        let beforeRows = Self.rows(on: mention.date, path: entity.file, store: context.store)

        let outcome = await model.link(mention, to: entity)
        #expect(outcome == .linked)
        #expect(model.showsStaleNotice == false)
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
        #expect(Self.rows(on: mention.date, path: entity.file, store: context.store) == beforeRows + 1)
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
        #expect(model.showsStaleNotice)
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

    @Test func byteRangesStayOnCharacterBoundaries() {
        let city = "İstanbul'da"
        let initial = "İ".utf8.count
        let cityRange = MentionByteRange.characterRange(in: city, utf8: 0..<("İstanbul".utf8.count))
        #expect(cityRange.map { String(city[$0]) } == "İstanbul")
        #expect(MentionByteRange.characterRange(in: city, utf8: 1..<initial) == nil)
        #expect(Self.emphasized(MentionByteRange.styled(city, utf8: 0..<initial)) == "İ")
        #expect(Self.emphasized(MentionByteRange.styled(city, utf8: 1..<initial)).isEmpty)

        let line = "a🎸b"
        let markStart = "a".utf8.count
        let markEnd = markStart + "🎸".utf8.count
        #expect(MentionByteRange.characterRange(in: line, utf8: markStart..<markEnd).map { String(line[$0]) } == "🎸")
        #expect(MentionByteRange.characterRange(in: line, utf8: (markStart + 1)..<markEnd) == nil)
        #expect(Self.emphasized(MentionByteRange.styled(line, utf8: markStart..<markEnd)) == "🎸")
        #expect(Self.emphasized(MentionByteRange.styled(line, utf8: (markStart + 1)..<(markStart + 2))).isEmpty)

        #expect(MentionByteRange.characterRange(in: line, utf8: 0..<0) == nil)
        #expect(MentionByteRange.characterRange(in: line, utf8: -1..<1) == nil)
        #expect(MentionByteRange.characterRange(in: line, utf8: line.utf8.count..<(line.utf8.count + 2)) == nil)
        #expect(Self.emphasized(MentionByteRange.styled(line, utf8: 50..<60)).isEmpty)

        #expect(UnlinkedMentionList.visibleCount(total: 12, expanded: false) == 5)
        #expect(UnlinkedMentionList.visibleCount(total: 12, expanded: true) == 12)
        #expect(UnlinkedMentionList.visibleCount(total: 5, expanded: false) == 5)
        #expect(UnlinkedMentionList.showsAll(total: 6, expanded: false))
        #expect(!UnlinkedMentionList.showsAll(total: 5, expanded: false))
        #expect(!UnlinkedMentionList.showsAll(total: 6, expanded: true))
    }

    private static func rows(on date: CalendarDate, path: String, store: IndexStore) -> Int {
        store.content.entityTimeline[path]?.first { $0.date == date }?.rows.count ?? 0
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
