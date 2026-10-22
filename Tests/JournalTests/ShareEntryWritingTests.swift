import Foundation
import Synchronization
import Testing
import VaultFormat
import VaultStore

@testable import Journal

/// Records every coordinated access Core asks for, then lets it through.
final class RecordingCoordination: FileCoordination, Sendable {
    private let recorded = Mutex<[FileCoordinationOperation]>([])
    var operations: [FileCoordinationOperation] { recorded.withLock { $0 } }

    func coordinate<T>(
        _ operation: FileCoordinationOperation, accessor: (FileCoordinationAccess) throws -> T
    ) throws -> T {
        recorded.withLock { $0.append(operation) }
        return try accessor(FileCoordinationAccess())
    }
}

/// The values a random source returns in turn, again from the start when they run out.
final class SequenceRandom: Sendable {
    private let values: [UInt64]
    private let next = Mutex(0)

    init(_ values: [UInt64]) { self.values = values }

    /// Draws `identifier` (Core's alphabet `a…z0…9`), as a `Fixtures/write` case names its new line.
    static func drawing(_ identifier: String) -> SequenceRandom {
        let alphabet = Array("abcdefghijklmnopqrstuvwxyz0123456789")
        return SequenceRandom(identifier.compactMap { alphabet.firstIndex(of: $0).map(UInt64.init) })
    }

    var source: @Sendable () -> UInt64 {
        {
            self.next.withLock { index in
                defer { index += 1 }
                return self.values[index % self.values.count]
            }
        }
    }
}

/// A fake iCloud container (a temporary folder, never the real one) with a vault in
/// `Documents/Kenet`, and a temporary folder standing in for the App Group.
struct ShareWritingContext {
    let directory: URL
    let container: URL
    let group: URL
    let coordination = RecordingCoordination()
    let random: SequenceRandom
    static let day = "2026-10-22"

    init(vault: Bool = true, identifier: String = "new123") throws {
        random = SequenceRandom.drawing(identifier)
        directory = try testDirectory()
        container = directory.appendingPathComponent("Cloud", isDirectory: true)
        group = directory.appendingPathComponent("Group", isDirectory: true)
        try FileManager.default.createDirectory(at: group, withIntermediateDirectories: true)
        if vault {
            let app = root.appendingPathComponent(".app", isDirectory: true)
            try FileManager.default.createDirectory(at: app, withIntermediateDirectories: true)
            try Data("{ \"formatVersion\": 1 }\n".utf8).write(to: app.appendingPathComponent("vault.json"))
        }
    }

    var root: URL { ShareVault.cloudRoot(in: container) }
    var dayFile: URL { root.appendingPathComponent("journal/\(Self.day).md") }
    var pending: ShareListFile { ShareListFile(url: ShareFiles.pending(in: group)) }
    var written: ShareListFile { ShareListFile(url: ShareFiles.written(in: group)) }

    func writer(cloud: Bool = true, group: Bool = true) -> ShareEntryWriter {
        let container = cloud ? container : nil
        return ShareEntryWriter(
            group: group ? self.group : nil, cloudContainer: { container }, coordination: coordination,
            randomValue: random.source)
    }

    func publish(_ vault: ShareTarget.Vault, appLock: Bool = false) throws {
        try ShareTargetFile.write(ShareTarget(vault: vault, appLock: appLock), to: ShareFiles.target(in: group))
    }

    func installDay(_ bytes: Data) throws {
        try FileManager.default.createDirectory(
            at: dayFile.deletingLastPathComponent(), withIntermediateDirectories: true)
        try bytes.write(to: dayFile)
    }

    func entry(_ text: String, time: String? = "14:00") -> ShareEntry {
        ShareEntry(
            id: UUID().uuidString, text: text, day: Self.day, time: time, sharedAt: Date(timeIntervalSince1970: 0))
    }

    /// Every file under the vault with its bytes.
    func vaultFiles() throws -> [String: Data] {
        var files: [String: Data] = [:]
        let base = root.resolvingSymlinksInPath().path + "/"
        let walker = FileManager.default.enumerator(at: root, includingPropertiesForKeys: [.isRegularFileKey])
        while let url = walker?.nextObject() as? URL {
            guard try url.resourceValues(forKeys: [.isRegularFileKey]).isRegularFile == true else { continue }
            files[url.resolvingSymlinksInPath().path.replacingOccurrences(of: base, with: "")] = try Data(
                contentsOf: url)
        }
        return files
    }

    func clean() { try? FileManager.default.removeItem(at: directory) }
}

/// An `add-event` case of `Fixtures/write` (docs/fixtures.md, "write/ kümesi").
struct EventLineFixture: CustomTestStringConvertible, Sendable {
    let name: String
    let input: Data
    let text: String
    let identifier: String
    let time: String?
    let expected: Data?

    var testDescription: String { name }

    static let all: [EventLineFixture] = {
        let folder = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
            .deletingLastPathComponent().appendingPathComponent("Fixtures/write")
        let names = (try? FileManager.default.contentsOfDirectory(atPath: folder.path)) ?? []
        return names.sorted().compactMap { name in
            let directory = folder.appendingPathComponent(name)
            guard let input = try? Data(contentsOf: directory.appendingPathComponent("input.md")),
                let operation = try? Data(contentsOf: directory.appendingPathComponent("operation.json")),
                let object = try? JSONSerialization.jsonObject(with: operation) as? [String: Any],
                let lines = object["lines"] as? [String: Any], lines["operation"] as? String == "add-event",
                let text = lines["text"] as? String, let identifier = lines["id"] as? String
            else { return nil }
            let time = (lines["time"] as? [String: Int]).map { clock in
                String(format: "%02d:%02d", clock["hour"] ?? 0, clock["minute"] ?? 0)
            }
            return EventLineFixture(
                name: name, input: input, text: text, identifier: identifier, time: time,
                expected: try? Data(contentsOf: directory.appendingPathComponent("expected.md")))
        }
    }()
}

/// The share extension's writer (docs/architecture.md, "Paylaşım uzantısı"): the iCloud vault of an
/// unlocked app gets the line itself, everything else waits in the App Group queue.
@Suite("Share entry writing")
struct ShareEntryWritingTests {
    // MARK: - Text

    @Test func prefillIsTitleAndLinkOrTheSharedText() throws {
        let link = try #require(URL(string: "https://example.com/yazi?a=1"))
        #expect(
            EntryWriting.prefill(title: "Uzun  bir\nbaşlık", url: link, text: nil)
                == "Uzun bir başlık https://example.com/yazi?a=1")
        #expect(EntryWriting.prefill(title: nil, url: link, text: "yok sayılır") == "https://example.com/yazi?a=1")
        #expect(
            EntryWriting.prefill(title: "https://example.com/yazi?a=1", url: link, text: nil) == link.absoluteString)
        #expect(EntryWriting.prefill(title: nil, url: nil, text: "  Seçili\n\nmetin\t") == "Seçili metin")
        // No link: the shared text, else the item's own text (an app that sends nothing else).
        #expect(EntryWriting.prefill(title: "Yalnız\nbaşlık", url: nil, text: nil) == "Yalnız başlık")
        #expect(EntryWriting.prefill(title: "Başlık", url: nil, text: "Metin") == "Metin")
        #expect(EntryWriting.prefill(title: "Başlık", url: nil, text: " \n") == "Başlık")
        #expect(EntryWriting.prefill(title: nil, url: nil, text: nil).isEmpty)
    }

    /// A page title is the page's words, not the user's: no tag, mention or link forms from it. The
    /// user's own text keeps its marks.
    @Test func aPageTitleIsPlainWords() throws {
        let link = try #require(URL(string: "https://example.com/a"))
        #expect(
            EntryWriting.prefill(title: "En iyi #10 @ekip [[Liste]] a#b", url: link, text: nil)
                == "En iyi ＃10 ＠ekip [Liste] a#b https://example.com/a")
        #expect(EntryWriting.prefill(title: "[[[x]]]", url: link, text: nil) == "[x] https://example.com/a")
        #expect(EntryWriting.prefill(title: nil, url: nil, text: "#etiket @Deniz [[Not]]") == "#etiket @Deniz [[Not]]")
        #expect(EntryWriting.prefill(title: "#etiket metni", url: nil, text: nil) == "#etiket metni")
    }

    /// What the extension receives, read as the extension reads it (`ShareInput`).
    @MainActor @Test func sharedItemsBecomeTheFormText() async throws {
        func item(title: String? = nil, content: String? = nil, _ objects: [any NSItemProviderWriting] = [])
            -> NSExtensionItem
        {
            let item = NSExtensionItem()
            item.attributedTitle = title.map { NSAttributedString(string: $0) }
            item.attributedContentText = content.map { NSAttributedString(string: $0) }
            item.attachments = objects.map { NSItemProvider(object: $0) }
            return item
        }
        let link = try #require(URL(string: "https://example.com/yazi"))
        // Text only as the item's content text, no attachment: it fills the form.
        #expect(await ShareInput.text(from: [item(content: "Notlardan\nbir metin")]) == "Notlardan bir metin")
        #expect(await ShareInput.text(from: [item(title: "Başlık alanı")]) == "Başlık alanı")
        // Safari: the page title and its link.
        #expect(
            await ShareInput.text(from: [item(content: "Sayfa #1", [link as NSURL])])
                == "Sayfa ＃1 https://example.com/yazi")
        // Selected text as an attachment comes before the content text.
        #expect(await ShareInput.text(from: [item(content: "Sayfa", ["Seçili #metin" as NSString])]) == "Seçili #metin")
        // A file is no link.
        #expect(
            await ShareInput.text(from: [item(content: "Dosya", [URL(fileURLWithPath: "/tmp/a.txt") as NSURL])])
                == "Dosya")
    }

    @Test func onlyTextCoreWritesAsOneEventLineCanBeAdded() {
        #expect(EntryWriting.canWrite("Kahve molası"))
        #expect(!EntryWriting.canWrite("   "))
        #expect(!EntryWriting.canWrite("Bir\nİki"))
        // After a time a checkbox is text; without one it would be read back as a task.
        #expect(EntryWriting.canWrite("[ ] x"))
        #expect(!EntryWriting.canWrite("[ ] x", timed: false))
    }

    @Test func entryCarriesTheLocalDayAndMinute() throws {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = .current
        let instant = try #require(
            calendar.date(from: DateComponents(year: 2026, month: 10, day: 22, hour: 9, minute: 5)))
        let entry = ShareEntry(text: "Kahve", at: instant)
        #expect(entry.day == "2026-10-22")
        #expect(entry.time == "09:05")
        #expect(entry.isWritable)
        #expect(ShareEntry(id: "x", text: "Kahve", day: "2026-10-22", time: nil, sharedAt: instant).isWritable == false)
        #expect(
            ShareEntry(id: UUID().uuidString, text: "Kahve", day: "2026-13-01", time: nil, sharedAt: instant).isWritable
                == false)
    }

    // MARK: - App Group lists

    @Test func listKeepsOrderAndRemovesByIdentifier() throws {
        let context = try ShareWritingContext(vault: false)
        defer { context.clean() }
        let first = context.entry("Bir")
        let second = context.entry("İki")
        #expect(context.pending.read().elements.isEmpty)
        try context.pending.append(first)
        try context.pending.append(second)
        #expect(context.pending.read().elements.compactMap(\.entry) == [first, second])
        try context.pending.remove(ids: [first.id])
        #expect(context.pending.read().elements.compactMap(\.entry) == [second])
        // The last record out removes the file: the queue is empty.
        try context.pending.remove(ids: [second.id])
        #expect(!FileManager.default.fileExists(atPath: ShareFiles.pending(in: context.group).path))
    }

    @Test func appendReplacesTheFileAtomically() throws {
        let context = try ShareWritingContext(vault: false)
        defer { context.clean() }
        let url = ShareFiles.pending(in: context.group)
        try context.pending.append(context.entry("Bir"))
        let reader = context.directory.appendingPathComponent("reader.json")
        try FileManager.default.linkItem(at: url, to: reader)
        try context.pending.append(context.entry("İki"))
        // A reader holding the old file still sees one whole list; the name points at the new one.
        #expect(ShareListFile(url: reader).read().elements.count == 1)
        #expect(context.pending.read().elements.count == 2)
    }

    @Test func recordsThisVersionCannotReadStayInTheList() throws {
        let context = try ShareWritingContext(vault: false)
        defer { context.clean() }
        let url = ShareFiles.pending(in: context.group)
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data(#"{"entries":[{"text":"eksik"},42],"format":1}"#.utf8).write(to: url)
        let entry = context.entry("Yeni")
        try context.pending.append(entry)
        let elements = context.pending.read().elements
        #expect(elements.count == 3)
        #expect(elements.map { $0.entry == nil } == [true, true, false])
        #expect(elements.last?.entry == entry)
    }

    @Test func aFileThatIsNotAListIsSetAsideNotDropped() throws {
        let context = try ShareWritingContext(vault: false)
        defer { context.clean() }
        let url = ShareFiles.pending(in: context.group)
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        let garbage = Data("{ bozuk".utf8)
        try garbage.write(to: url)
        guard case .unreadable = context.pending.read() else {
            Issue.record("expected unreadable")
            return
        }
        let entry = context.entry("Yeni")
        try context.pending.append(entry)
        #expect(context.pending.read().elements.compactMap(\.entry) == [entry])
        let kept = try FileManager.default.contentsOfDirectory(atPath: ShareFiles.directory(in: context.group).path)
            .filter { $0.hasPrefix("damaged-") }
        #expect(kept.count == 1)
        let aside = ShareFiles.directory(in: context.group).appendingPathComponent(try #require(kept.first))
        #expect(try Data(contentsOf: aside) == garbage)
    }

    /// A list file this process cannot read is moved aside whole, not taken for an empty list and
    /// written over.
    @Test func aListThatCannotBeReadIsSetAsideNotWrittenOver() throws {
        let context = try ShareWritingContext(vault: false)
        defer { context.clean() }
        let url = ShareFiles.pending(in: context.group)
        try context.pending.append(context.entry("Eski"))
        let old = try Data(contentsOf: url)
        try FileManager.default.setAttributes([.posixPermissions: 0o000], ofItemAtPath: url.path)
        guard case .unreadable = context.pending.read() else {
            Issue.record("expected unreadable")
            return
        }
        let entry = context.entry("Yeni")
        try context.pending.append(entry)
        #expect(context.pending.read().elements.compactMap(\.entry) == [entry])
        let directory = ShareFiles.directory(in: context.group)
        let kept = try FileManager.default.contentsOfDirectory(atPath: directory.path).filter {
            $0.hasPrefix("damaged-")
        }
        let aside = directory.appendingPathComponent(try #require(kept.first))
        #expect(kept.count == 1)
        try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: aside.path)
        #expect(try Data(contentsOf: aside) == old)
    }

    // MARK: - Writing

    /// Every `add-event` case of `Fixtures/write`, written by the extension into an iCloud vault:
    /// the day file is the case's expected bytes (only the new line added). A case Core refuses
    /// leaves its input bytes: the text is queued, or, when it is no event line at all (a bad
    /// clock, an untimed checkbox), refused before anything is written. No other vault file changes.
    @Test(arguments: EventLineFixture.all)
    func cloudWriteAddsOnlyTheLine(_ fixture: EventLineFixture) async throws {
        let context = try ShareWritingContext(identifier: fixture.identifier)
        defer { context.clean() }
        try context.publish(.icloud)
        try context.installDay(fixture.input)
        let before = try context.vaultFiles()
        let entry = context.entry(fixture.text, time: fixture.time)

        let outcome = try? await context.writer().add(entry)

        var after = try context.vaultFiles()
        let day = "journal/\(ShareWritingContext.day).md"
        if let expected = fixture.expected {
            #expect(outcome == .written)
            #expect(after[day] == expected)
            #expect(context.written.read().elements.compactMap(\.entry) == [entry])
            #expect(context.pending.read().elements.isEmpty)
        } else if entry.isWritable {
            #expect(outcome == .queued)
            #expect(after[day] == fixture.input)
            #expect(context.pending.read().elements.compactMap(\.entry) == [entry])
            #expect(context.written.read().elements.isEmpty)
        } else {
            #expect(outcome == nil)
            #expect(after[day] == fixture.input)
            #expect(context.pending.read().elements.isEmpty && context.written.read().elements.isEmpty)
        }
        after[day] = before[day]
        #expect(after == before)
    }

    @Test func cloudWriteHoldsTheCoordinatorOnTheDayFile() async throws {
        let context = try ShareWritingContext()
        defer { context.clean() }
        try context.publish(.icloud)
        #expect(try await context.writer().add(context.entry("Kahve")) == .written)
        let modified = context.coordination.operations.compactMap { operation -> String? in
            guard case .modify(let url) = operation else { return nil }
            return url.path
        }
        #expect(modified.contains { $0.hasSuffix("/Documents/Kenet/journal/\(ShareWritingContext.day).md") })
        // A new day file starts with the vault's frontmatter, as the app writes it.
        let document = RawDocument(bytes: try Data(contentsOf: context.dayFile))
        #expect(document.bodyLines.events.map(\.block.text) == ["Kahve"])
    }

    /// Without an index the writer checks the new identifier against the day file: one taken there
    /// is drawn again, the other line keeps its own.
    @Test func aNewLineDoesNotTakeAnIdentifierOfItsDay() async throws {
        let context = try ShareWritingContext(identifier: "new123new456")
        defer { context.clean() }
        try context.publish(.icloud)
        try context.installDay(Data("## Events\n- 09:00 Su ^new123\n".utf8))
        #expect(try await context.writer().add(context.entry("Kitap")) == .written)
        let text = String(decoding: try Data(contentsOf: context.dayFile), as: UTF8.self)
        #expect(text.hasPrefix("## Events\n- 09:00 Su ^new123\n- 14:00 Kitap ^new456"))
        #expect(text.components(separatedBy: "^new123").count == 2)
    }

    @Test func appLockQueuesEvenForTheCloudVault() async throws {
        let context = try ShareWritingContext()
        defer { context.clean() }
        try context.publish(.icloud, appLock: true)
        let entry = context.entry("Kilitliyken")
        #expect(try await context.writer().add(entry) == .queued)
        #expect(!FileManager.default.fileExists(atPath: context.dayFile.path))
        #expect(context.coordination.operations.isEmpty)
        #expect(context.pending.read().elements.compactMap(\.entry) == [entry])
    }

    @Test(arguments: [ShareTarget.Vault.local, .selected, .none])
    func otherVaultsQueue(_ vault: ShareTarget.Vault) async throws {
        let context = try ShareWritingContext()
        defer { context.clean() }
        try context.publish(vault)
        #expect(try await context.writer().add(context.entry("Bekler")) == .queued)
        #expect(!FileManager.default.fileExists(atPath: context.dayFile.path))
        #expect(context.pending.read().elements.count == 1)
    }

    @Test func withoutWordFromTheAppItQueues() async throws {
        let context = try ShareWritingContext()
        defer { context.clean() }
        #expect(try await context.writer().add(context.entry("Bekler")) == .queued)
        try FileManager.default.createDirectory(
            at: ShareFiles.directory(in: context.group), withIntermediateDirectories: true)
        try Data(#"{"appLock":false,"vault":"başka"}"#.utf8).write(to: ShareFiles.target(in: context.group))
        #expect(try await context.writer().add(context.entry("Bekler")) == .queued)
        #expect(!FileManager.default.fileExists(atPath: context.dayFile.path))
        #expect(context.pending.read().elements.count == 2)
    }

    @Test func noCloudOrNoVaultThereQueues() async throws {
        let context = try ShareWritingContext(vault: false)
        defer { context.clean() }
        try context.publish(.icloud)
        #expect(try await context.writer(cloud: false).add(context.entry("Bir")) == .queued)
        #expect(try await context.writer().add(context.entry("İki")) == .queued)
        #expect(!FileManager.default.fileExists(atPath: context.root.path))
        #expect(context.pending.read().elements.count == 2)
    }

    /// The day exists only as iCloud's placeholder: nothing is created beside it.
    @Test func aDayStillInICloudQueues() async throws {
        let context = try ShareWritingContext()
        defer { context.clean() }
        try context.publish(.icloud)
        let journal = context.dayFile.deletingLastPathComponent()
        try FileManager.default.createDirectory(at: journal, withIntermediateDirectories: true)
        let placeholder = journal.appendingPathComponent(".\(ShareWritingContext.day).md.icloud")
        try Data().write(to: placeholder)
        #expect(try await context.writer().add(context.entry("Bekler")) == .queued)
        #expect(!FileManager.default.fileExists(atPath: context.dayFile.path))
        #expect(try FileManager.default.contentsOfDirectory(atPath: journal.path) == [placeholder.lastPathComponent])
    }

    @Test func noGroupIsAFailureTheFormShows() async throws {
        let context = try ShareWritingContext()
        defer { context.clean() }
        await #expect(throws: ShareEntryWriter.Failure.groupUnavailable) {
            try await context.writer(group: false).add(context.entry("Kahve"))
        }
        #expect(!FileManager.default.fileExists(atPath: context.dayFile.path))
    }

    /// The extension writes where the app opens its iCloud vault.
    @MainActor @Test func cloudRootIsTheVaultTheAppOpens() async throws {
        let context = try CloudVaultContext()
        defer { context.clean() }
        await context.store.createCloudVault()
        let opened = try #require(context.store.vaultURL)
        #expect(
            opened.resolvingSymlinksInPath().standardizedFileURL
                == ShareVault.cloudRoot(in: context.container).resolvingSymlinksInPath().standardizedFileURL)
        #expect(context.store.shareVault == .icloud)
    }
}
