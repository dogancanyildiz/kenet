import Foundation
import Testing
import VaultFormat
import VaultStore

@testable import Journal

/// The app's side of the share extension (docs/architecture.md, "Paylaşım uzantısı"): queued
/// texts become events once the vault is open and the app unlocked, each exactly once; what the
/// extension wrote into the iCloud vault itself reaches the index. The vault is the sample vault
/// (people "Deniz Arıkan", places "Çınaraltı Kafe"); the App Group is a temporary folder.
@MainActor @Suite("Share queue")
struct ShareQueueTests {
    final class Lock {
        var isLocked = false
        var isEnabled = false
    }

    @MainActor struct Harness {
        let context: TaskTestContext
        let group: URL
        let lock = Lock()
        let processor: ShareQueueProcessor
        static let day = "2026-10-20"

        init() throws {
            context = try TaskTestContext(sample: true)
            group = context.directory.appendingPathComponent("Group", isDirectory: true)
            try FileManager.default.createDirectory(at: group, withIntermediateDirectories: true)
            processor = Self.processor(context: context, group: group, lock: lock)
        }

        static func processor(context: TaskTestContext, group: URL, lock: Lock) -> ShareQueueProcessor {
            ShareQueueProcessor(
                store: context.store, group: FolderAppGroupStore(containerURL: group),
                isLocked: { lock.isLocked }, appLockEnabled: { lock.isEnabled })
        }

        var pending: ShareListFile { ShareListFile(url: ShareFiles.pending(in: group)) }
        var dayFile: URL { context.root.appendingPathComponent("journal/\(Self.day).md") }

        func entry(_ text: String, time: String? = "09:30") -> ShareEntry {
            // Whole seconds: the lists keep ISO 8601 dates.
            ShareEntry(
                id: UUID().uuidString, text: text, day: Self.day, time: time,
                sharedAt: Date(timeIntervalSince1970: 1_792_000_000))
        }

        /// The events of the shared day, as text, from the disk.
        func events() throws -> [String] {
            guard FileManager.default.fileExists(atPath: dayFile.path) else { return [] }
            return RawDocument(bytes: try Data(contentsOf: dayFile)).bodyLines.events.map(\.block.text)
        }

        func run(_ processor: ShareQueueProcessor? = nil) async {
            let processor = processor ?? self.processor
            processor.process()
            await processor.settle()
        }

        func damagedFiles() throws -> [URL] {
            let directory = ShareFiles.directory(in: group)
            return try FileManager.default.contentsOfDirectory(atPath: directory.path)
                .filter { $0.hasPrefix("damaged-") }.map { directory.appendingPathComponent($0) }
        }
    }

    @Test func queuedTextBecomesAnEventOnItsDayWithNamesRecognised() async throws {
        let harness = try Harness()
        defer { harness.context.clean() }
        await harness.context.start()
        try harness.pending.append(harness.entry("Deniz Arıkan ile kahve"))

        await harness.run()

        let document = RawDocument(bytes: try Data(contentsOf: harness.dayFile))
        let event = try #require(document.bodyLines.events.first)
        #expect(document.bodyLines.events.count == 1)
        #expect(event.block.text == "[[Deniz Arıkan]] ile kahve")
        #expect(event.time?.hour == 9 && event.time?.minute == 30)
        #expect(!FileManager.default.fileExists(atPath: ShareFiles.pending(in: harness.group).path))
        #expect(harness.processor.report == ShareImportReport(added: 1))
        #expect(harness.processor.report?.message == String(localized: "\(1) paylaşım eklendi."))
    }

    /// A record leaves the queue with its write: a second run, or the app's next launch, does
    /// not write it again.
    @Test func aRecordIsWrittenOnceAcrossRunsAndLaunches() async throws {
        let harness = try Harness()
        defer { harness.context.clean() }
        await harness.context.start()
        try harness.pending.append(harness.entry("Tek kez"))
        try harness.pending.append(harness.entry("İkinci"))

        await harness.run()
        await harness.run()
        await harness.run(Harness.processor(context: harness.context, group: harness.group, lock: harness.lock))

        #expect(try harness.events() == ["Tek kez", "İkinci"])
        #expect(harness.pending.read().elements.isEmpty)
    }

    /// Locked, nothing enters the day file; the queue waits for the unlock.
    @Test func lockedAppLeavesTheQueueUntilUnlocked() async throws {
        let harness = try Harness()
        defer { harness.context.clean() }
        await harness.context.start()
        harness.lock.isLocked = true
        let entry = harness.entry("Kilit açılınca")
        try harness.pending.append(entry)

        await harness.run()
        #expect(try harness.events().isEmpty)
        #expect(harness.pending.read().elements.compactMap(\.entry) == [entry])
        #expect(harness.processor.report == nil)

        harness.lock.isLocked = false
        await harness.run()
        #expect(try harness.events() == ["Kilit açılınca"])
        #expect(harness.pending.read().elements.isEmpty)
    }

    @Test func nothingIsTakenBeforeTheVaultIsOpen() async throws {
        let harness = try Harness()
        defer { harness.context.clean() }
        try harness.pending.append(harness.entry("Bekler"))
        await harness.run()
        #expect(harness.pending.read().elements.count == 1)
        #expect(harness.processor.report == nil)
    }

    /// An unreadable record is kept aside (its bytes in `damaged-…json`) and reported; the readable
    /// ones are written.
    @Test func unreadableRecordsAreSetAsideAndTheRestIsWritten() async throws {
        let harness = try Harness()
        defer { harness.context.clean() }
        await harness.context.start()
        let url = ShareFiles.pending(in: harness.group)
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data(#"{"entries":[{"day":"2026-10-20","text":"kimliksiz"}],"format":1}"#.utf8).write(to: url)
        try harness.pending.append(harness.entry("Okunur"))

        await harness.run()

        #expect(try harness.events() == ["Okunur"])
        #expect(!FileManager.default.fileExists(atPath: url.path))
        let damaged = try harness.damagedFiles()
        #expect(damaged.count == 1)
        let kept =
            try JSONSerialization.jsonObject(with: Data(contentsOf: try #require(damaged.first))) as? [[String: String]]
        #expect(kept == [["day": "2026-10-20", "text": "kimliksiz"]])
        #expect(harness.processor.report == ShareImportReport(added: 1, unreadable: 1))
    }

    @Test func anUnreadableQueueIsSetAside() async throws {
        let harness = try Harness()
        defer { harness.context.clean() }
        await harness.context.start()
        let url = ShareFiles.pending(in: harness.group)
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        let garbage = Data("[bozuk".utf8)
        try garbage.write(to: url)

        await harness.run()

        #expect(!FileManager.default.fileExists(atPath: url.path))
        #expect(try harness.damagedFiles().map { try Data(contentsOf: $0) } == [garbage])
        #expect(harness.processor.report == ShareImportReport(unreadable: 1))
    }

    /// The day file cannot take the line (not UTF-8): its bytes stay, the record stays queued.
    @Test func aFailedWriteStaysQueued() async throws {
        let harness = try Harness()
        defer { harness.context.clean() }
        let bytes = Data([0x2D, 0x20, 0xFF, 0xFE, 0x0A])
        try FileManager.default.createDirectory(
            at: harness.dayFile.deletingLastPathComponent(), withIntermediateDirectories: true)
        try bytes.write(to: harness.dayFile)
        await harness.context.start()
        let entry = harness.entry("Yazılamaz")
        try harness.pending.append(entry)

        await harness.run()

        #expect(try Data(contentsOf: harness.dayFile) == bytes)
        #expect(harness.pending.read().elements.compactMap(\.entry) == [entry])
        #expect(harness.processor.report == ShareImportReport(waiting: 1))
    }

    /// A run saved the line and stopped before the record left the queue: the record still carries
    /// its mark, the next run finds the line and only removes the record. The saved line is the
    /// linked text (the mark), not the shared one.
    @Test func aRecordSavedBeforeARunStoppedIsNotWrittenAgain() async throws {
        let harness = try Harness()
        defer { harness.context.clean() }
        await harness.context.start()
        var entry = harness.entry("Deniz Arıkan ile kahve")
        let day = try #require(entry.calendarDay)
        #expect(await harness.context.store.addEvent(on: day, text: "[[Deniz Arıkan]] ile kahve", time: entry.clock))
        entry.writing = "[[Deniz Arıkan]] ile kahve"
        try harness.pending.append(entry)

        await harness.run()

        #expect(try harness.events() == ["[[Deniz Arıkan]] ile kahve"])
        #expect(harness.pending.read().elements.isEmpty)
        #expect(harness.processor.report == ShareImportReport(added: 1))
    }

    /// The line was saved and the run stopped; before the next run the day went back to iCloud
    /// (only its placeholder is left). That run cannot see the line and the write is refused: the
    /// record keeps its mark, so once the day is back the line is found, not written again.
    @Test func aMarkOutlivesADayBackInICloud() async throws {
        let harness = try Harness()
        defer { harness.context.clean() }
        await harness.context.start()
        var entry = harness.entry("Deniz Arıkan ile kahve")
        let day = try #require(entry.calendarDay)
        #expect(await harness.context.store.addEvent(on: day, text: "[[Deniz Arıkan]] ile kahve", time: entry.clock))
        entry.writing = "[[Deniz Arıkan]] ile kahve"
        try harness.pending.append(entry)
        let saved = try Data(contentsOf: harness.dayFile)
        let placeholder = harness.dayFile.deletingLastPathComponent()
            .appendingPathComponent(".\(Harness.day).md.icloud")
        try FileManager.default.removeItem(at: harness.dayFile)
        try Data().write(to: placeholder)

        await harness.run()

        #expect(!FileManager.default.fileExists(atPath: harness.dayFile.path))
        #expect(harness.pending.read().elements.compactMap(\.entry) == [entry])
        #expect(harness.processor.report == ShareImportReport(waiting: 1))

        try FileManager.default.removeItem(at: placeholder)
        try saved.write(to: harness.dayFile)
        await harness.run()

        #expect(try harness.events() == ["[[Deniz Arıkan]] ile kahve"])
        #expect(harness.pending.read().elements.isEmpty)
        #expect(harness.processor.report == ShareImportReport(added: 1))
    }

    /// A mark without its line (the run stopped before the save): the line is written, once.
    @Test func aMarkWithoutItsLineIsWrittenOnce() async throws {
        let harness = try Harness()
        defer { harness.context.clean() }
        await harness.context.start()
        var entry = harness.entry("Kaydedilmemiş")
        entry.writing = "Kaydedilmemiş"
        try harness.pending.append(entry)
        // The same text at another minute is another event.
        let day = try #require(entry.calendarDay)
        #expect(
            await harness.context.store.addEvent(
                on: day, text: "Kaydedilmemiş", time: try LineClock(hour: 8, minute: 0)))

        await harness.run()
        await harness.run()

        #expect(try harness.events() == ["Kaydedilmemiş", "Kaydedilmemiş"])
        #expect(harness.pending.read().elements.isEmpty)
        #expect(harness.processor.report == ShareImportReport(added: 1))
    }

    /// The record cannot be marked (the queue cannot change): nothing is written, it waits.
    @Test func aRecordThatCannotBeMarkedIsNotWritten() async throws {
        let harness = try Harness()
        defer { harness.context.clean() }
        await harness.context.start()
        let entry = harness.entry("İşaretsiz")
        try harness.pending.append(entry)
        let directory = ShareFiles.directory(in: harness.group)
        try FileManager.default.setAttributes([.posixPermissions: 0o555], ofItemAtPath: directory.path)
        defer { try? FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: directory.path) }

        await harness.run()

        #expect(try harness.events().isEmpty)
        #expect(harness.pending.read().elements.compactMap(\.entry) == [entry])
        #expect(harness.processor.report == ShareImportReport(waiting: 1))
    }

    @Test func targetTellsTheExtensionTheVaultAndTheLock() async throws {
        let harness = try Harness()
        defer { harness.context.clean() }
        let url = ShareFiles.target(in: harness.group)
        harness.processor.publishTarget()
        #expect(ShareTargetFile.read(from: url) == ShareTarget(vault: .none, appLock: false))
        await harness.context.start()
        harness.lock.isEnabled = true
        harness.processor.publishTarget()
        #expect(ShareTargetFile.read(from: url) == ShareTarget(vault: .local, appLock: true))
    }

    /// End to end with an iCloud vault: the app publishes its target, the extension's writer puts
    /// the line into the day file itself and leaves a marker, the app's next run refreshes the
    /// index and clears the marker.
    @Test func aLineTheExtensionWroteReachesTheIndex() async throws {
        let context = try CloudVaultContext()
        defer { context.clean() }
        let group = context.directory.appendingPathComponent("Group", isDirectory: true)
        let lock = Lock()
        let processor = ShareQueueProcessor(
            store: context.store, group: FolderAppGroupStore(containerURL: group), isLocked: { lock.isLocked },
            appLockEnabled: { lock.isEnabled })
        await context.store.createCloudVault()
        processor.publishTarget()
        #expect(ShareTargetFile.read(from: ShareFiles.target(in: group))?.writesDirectly == true)

        let container = context.container
        let writer = ShareEntryWriter(
            group: group, cloudContainer: { container }, coordination: DirectFileCoordination())
        let entry = ShareEntry(text: "Paylaşılanmakale", at: Date())
        #expect(try await writer.add(entry) == .written)

        processor.process()
        await processor.settle()

        #expect(try await context.store.search("Paylaşılanmakale").count == 1)
        #expect(!FileManager.default.fileExists(atPath: ShareFiles.written(in: group).path))
        #expect(processor.report == ShareImportReport(added: 1))
    }
}
