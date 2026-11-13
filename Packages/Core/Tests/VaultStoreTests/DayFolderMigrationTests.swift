import Foundation
import Testing
import VaultFormat

@testable import VaultIndex
@testable import VaultStore

/// The legacy day folder these vaults still use (`LegacyVaultNames`).
private let legacy = LegacyVaultNames.dayFolder

/// `Fixtures/migration/legacy-vault`: a vault written before 2026-11-13 (`source/`), the vault after
/// one migration run (`expected/`) and what the run reports (`outcome.json`).
struct DayFolderMigrationTests {
    private struct Outcome: Decodable {
        let moved: [String]
        let copies: [String]
        let leftInPlace: [String]
        let removedLegacyFolder: Bool
    }

    /// A scratch copy of the legacy vault, each file given its own fixed modification time.
    private struct LegacyVault {
        let scratch: URL
        let root: URL
        let index: VaultIndex

        init(fixture: String = "source") throws {
            scratch = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
            root = scratch.appendingPathComponent("vault-root")
            try FileManager.default.createDirectory(at: scratch, withIntermediateDirectories: true)
            try FileManager.default.copyItem(at: Self.fixture().appendingPathComponent(fixture), to: root)
            for (offset, path) in try DayFolderMigrationTests.tree(root).keys.sorted().enumerated() {
                try FileManager.default.setAttributes(
                    [.modificationDate: Date(timeIntervalSince1970: TimeInterval(1_790_000_000 + offset * 61))],
                    ofItemAtPath: root.appendingPathComponent(path).path)
            }
            index = try VaultIndex(databaseURL: scratch.appendingPathComponent("index.sqlite"))
            try index.rebuild(vaultRoot: root)
        }

        static func fixture() throws -> URL { try Fixtures.root().appendingPathComponent("migration/legacy-vault") }

        func remove() { try? FileManager.default.removeItem(at: scratch) }

        func url(_ path: String) -> URL { root.appendingPathComponent(path) }

        func time(_ path: String) throws -> Date {
            try #require(try FileManager.default.attributesOfItem(atPath: url(path).path)[.modificationDate] as? Date)
        }

        func store(
            removeFile: @escaping @Sendable (URL) throws -> Void = { try FileManager.default.removeItem(at: $0) },
            moveFile: @escaping @Sendable (URL, URL) throws -> Void = {
                try FileManager.default.moveItem(at: $0, to: $1)
            },
            readFile: @escaping @Sendable (URL) throws -> Data = { try Data(contentsOf: $0) },
            coordination: any FileCoordination = DirectFileCoordination()
        ) -> VaultStore {
            VaultStore(
                vaultRoot: root, index: index, linkFile: { try FileManager.default.linkItem(at: $0, to: $1) },
                moveFile: moveFile, readFile: readFile, removeFile: removeFile, fileCoordination: coordination)
        }
    }

    /// Every regular file under `root`, by vault-relative path.
    private static func tree(_ root: URL) throws -> [String: Data] {
        var files: [String: Data] = [:]
        let enumerator = try #require(FileManager.default.enumerator(at: root, includingPropertiesForKeys: nil))
        for case let url as URL in enumerator {
            let values = try url.resourceValues(forKeys: [.isRegularFileKey])
            guard values.isRegularFile == true, url.lastPathComponent != ".DS_Store" else { continue }
            let path = String(url.standardizedFileURL.path.dropFirst(root.standardizedFileURL.path.count + 1))
            files[path] = try Data(contentsOf: url)
        }
        return files
    }

    private func expected() throws -> [String: Data] {
        try Self.tree(LegacyVault.fixture().appendingPathComponent("expected"))
    }

    @Test func legacyVaultMovesToTheNewLayout() async throws {
        let vault = try LegacyVault()
        defer { vault.remove() }
        let times = try ["2026-10-01", "2026-10-02", "2026-10-04"].map { try vault.time("\(legacy)/\($0).md") }
        let outcome = try await vault.store().migratingLegacyDayFolder()
        let wanted = try JSONDecoder().decode(
            Outcome.self, from: Data(contentsOf: LegacyVault.fixture().appendingPathComponent("outcome.json")))
        #expect(outcome.moved == wanted.moved)
        #expect(outcome.copies == wanted.copies)
        #expect(outcome.leftInPlace == wanted.leftInPlace)
        #expect(outcome.removedLegacyFolder == wanted.removedLegacyFolder)
        #expect(outcome.resumed.isEmpty && outcome.waiting.isEmpty && outcome.failed.isEmpty)
        #expect(try Self.tree(vault.root) == expected())
        // A rewritten file keeps the source's time, as a moved one does: a day copy merge compares it.
        for (day, time) in zip(["2026-10-01", "2026-10-02", "2026-10-04"], times) {
            #expect(try vault.time("diary/\(day).md") == time, "\(day)")
        }
        // The index followed the files: the moved days answer from `diary/`, the old paths are gone.
        #expect(try vault.index.day(on: CalendarDate("2026-10-01")!)?.file.path == "diary/2026-10-01.md")
        #expect(try vault.index.files().map(\.path).allSatisfy { !$0.hasPrefix(LegacyVaultNames.dayFolder + "/2026") })
        #expect(
            try vault.index.blocks(on: CalendarDate("2026-10-01")!).filter { $0.kind == "paragraph" }
                .map(\.section) == ["Diary"])
    }

    @Test func aSecondRunChangesNothing() async throws {
        let vault = try LegacyVault()
        defer { vault.remove() }
        _ = try await vault.store().migratingLegacyDayFolder()
        let first = try Self.tree(vault.root)
        let again = try await vault.store().migratingLegacyDayFolder()
        #expect(again.moved.isEmpty && again.copies.isEmpty && again.resumed.isEmpty && again.failed.isEmpty)
        #expect(again.leftInPlace == ["\(legacy)/eski", "\(legacy)/notlar.md"])
        #expect(try Self.tree(vault.root) == first)
    }

    /// The day file under `diary/` with other bytes stays as it was; the old version becomes a copy.
    @Test func anExistingDayFileIsNeverReplaced() async throws {
        let vault = try LegacyVault()
        defer { vault.remove() }
        let current = try Data(contentsOf: vault.url("diary/2026-10-05.md"))
        let outcome = try await vault.store().migratingLegacyDayFolder()
        #expect(try Data(contentsOf: vault.url("diary/2026-10-05.md")) == current)
        #expect(outcome.copies.contains("diary/2026-10-05 2.md"))
        #expect(DayCopyName.isDayCopy(path: "diary/2026-10-05 2.md"))
        #expect(!FileManager.default.fileExists(atPath: vault.url("\(legacy)/2026-10-05.md").path))
    }

    /// A run stopped after writing a target and before removing its source resumes: the next run
    /// sees the target holds the source's migrated bytes and only removes the source.
    @Test func anInterruptedRunResumes() async throws {
        let vault = try LegacyVault()
        defer { vault.remove() }
        let stuck = vault.url("\(legacy)/2026-10-01.md").standardizedFileURL.path
        let failing = vault.store(removeFile: { url in
            if url.standardizedFileURL.path == stuck { throw CocoaError(.fileWriteNoPermission) }
            try FileManager.default.removeItem(at: url)
        })
        let first = try await failing.migratingLegacyDayFolder()
        #expect(first.failed == ["\(legacy)/2026-10-01.md"])
        #expect(FileManager.default.fileExists(atPath: vault.url("\(legacy)/2026-10-01.md").path))
        #expect(FileManager.default.fileExists(atPath: vault.url("diary/2026-10-01.md").path))
        let second = try await vault.store().migratingLegacyDayFolder()
        #expect(second.resumed == ["\(legacy)/2026-10-01.md"])
        #expect(second.moved.isEmpty && second.copies.isEmpty && second.failed.isEmpty)
        #expect(try Self.tree(vault.root) == expected())
    }

    /// The migrated bytes differ from the source only in the heading's name and the `type` value.
    @Test func onlyTheHeadingAndTypeLinesChange() throws {
        let source = try LegacyVault.fixture().appendingPathComponent("source/\(legacy)")
        let target = try LegacyVault.fixture().appendingPathComponent("expected/diary")
        for day in ["2026-10-01", "2026-10-02"] {
            let old = RawDocument(bytes: Array(try Data(contentsOf: source.appendingPathComponent("\(day).md"))))
            let new = old.migratingLegacyDayNames()
            #expect(new.serialized() == Array(try Data(contentsOf: target.appendingPathComponent("\(day).md"))))
            #expect(new.hasByteOrderMark == old.hasByteOrderMark && new.lines.count == old.lines.count)
            let changed = old.lines.indices.filter { old.lines[$0] != new.lines[$0] }
            #expect(changed.count == 2, "\(day)")
            for index in changed {
                #expect(new.lines[index].ending == old.lines[index].ending)
                let text = try #require(new.lines[index].text)
                #expect(text.hasPrefix("## Diary") || text.hasPrefix("type: diary"), "\(text)")
            }
        }
    }

    /// Round trip: a file without legacy names, or one already migrated, keeps every byte.
    @Test func migratingTwiceOrNothingKeepsEveryByte() throws {
        let fixtures = try Fixtures.root()
        var files = try Self.tree(fixtures.appendingPathComponent("vaults/sample/diary")).values.map { $0 }
        files += try Self.tree(LegacyVault.fixture().appendingPathComponent("expected/diary")).values
        files.append(Data([0xFF, 0x0A]))
        for data in files {
            let document = RawDocument(bytes: Array(data))
            #expect(document.migratingLegacyDayNames().serialized() == Array(data))
        }
        let sources = try Self.tree(LegacyVault.fixture().appendingPathComponent("source/\(legacy)"))
        for (path, data) in sources {
            let once = RawDocument(bytes: Array(data)).migratingLegacyDayNames()
            #expect(once.migratingLegacyDayNames() == once, "\(path)")
        }
    }

    @Test func aFileWaitingForDownloadStaysAndTheFolderGoesWhenEmpty() async throws {
        let vault = try LegacyVault()
        defer { vault.remove() }
        for name in ["notlar.md", "eski"] { try FileManager.default.removeItem(at: vault.url("\(legacy)/" + name)) }
        let placeholder = vault.url("\(legacy)/.2026-10-08.md.icloud")
        try Data("yer tutucu".utf8).write(to: placeholder)
        let first = try await vault.store().migratingLegacyDayFolder()
        #expect(first.waiting == ["\(legacy)/2026-10-08.md"])
        #expect(!first.removedLegacyFolder)
        #expect(FileManager.default.fileExists(atPath: placeholder.path))
        try FileManager.default.removeItem(at: placeholder)
        let second = try await vault.store().migratingLegacyDayFolder()
        #expect(second.removedLegacyFolder)
        #expect(!FileManager.default.fileExists(atPath: vault.url(LegacyVaultNames.dayFolder).path))
    }

    @Test func aDiaryCaseVariantStopsTheRun() async throws {
        let vault = try LegacyVault()
        defer { vault.remove() }
        let before = try Self.tree(vault.root)
        try FileManager.default.moveItem(at: vault.url("diary"), to: vault.url("Diary"))
        await #expect(throws: VaultStoreError.reservedFolderCaseMismatch(found: "Diary", expected: "diary")) {
            try await vault.store().migratingLegacyDayFolder()
        }
        try FileManager.default.moveItem(at: vault.url("Diary"), to: vault.url("diary"))
        #expect(try Self.tree(vault.root) == before)
    }

    @Test func aVaultWithoutTheLegacyFolderIsLeftAlone() async throws {
        let vault = try LegacyVault(fixture: "expected")
        defer { vault.remove() }
        try FileManager.default.removeItem(at: vault.url(LegacyVaultNames.dayFolder))
        let before = try Self.tree(vault.root)
        let outcome = try await vault.store().migratingLegacyDayFolder()
        #expect(outcome.isEmpty)
        #expect(try Self.tree(vault.root) == before)
    }

    // MARK: - Another process acts inside the window

    /// Leaves the legacy folder with day files only, so the run can empty it.
    private func onlyDays(_ vault: LegacyVault) throws {
        for name in ["notlar.md", "eski"] { try FileManager.default.removeItem(at: vault.url("\(legacy)/" + name)) }
    }

    /// A file that arrives in the emptied folder inside the delete boundary stays, and so does the
    /// folder: removal is `rmdir`, never recursive.
    @Test func aFileArrivingBeforeTheFolderGoesIsKept() async throws {
        let vault = try LegacyVault()
        defer { vault.remove() }
        try onlyDays(vault)
        let late = vault.url("\(legacy)/geç.md")
        let coordination = Planting { operation in
            if case .delete = operation { try? Data("Geç gelen.\n".utf8).write(to: late) }
        }
        let outcome = try await vault.store(coordination: coordination).migratingLegacyDayFolder()
        #expect(!outcome.removedLegacyFolder)
        #expect(try Data(contentsOf: late) == Data("Geç gelen.\n".utf8))
    }

    /// A placeholder of the day's name under `diary/` blocks that name when the target is chosen:
    /// the source becomes a day copy, and the placeholder is left alone.
    @Test func aDownloadOnItsWayBlocksTheNameWhenChoosing() async throws {
        let vault = try LegacyVault()
        defer { vault.remove() }
        let placeholder = vault.url("diary/.2026-10-01.md.icloud")
        try Data("yer tutucu".utf8).write(to: placeholder)
        let outcome = try await vault.store().migratingLegacyDayFolder()
        #expect(outcome.copies.contains("diary/2026-10-01 2.md"))
        #expect(!FileManager.default.fileExists(atPath: vault.url("diary/2026-10-01.md").path))
        #expect(FileManager.default.fileExists(atPath: placeholder.path))
    }

    /// A placeholder that appears after the name was chosen, inside the boundary, stops that file:
    /// nothing is written beside it and the source stays.
    @Test func aDownloadArrivingInsideTheBoundaryStopsTheFile() async throws {
        let vault = try LegacyVault()
        defer { vault.remove() }
        let target = vault.url("diary/2026-10-01.md").standardizedFileURL.path
        let placeholder = vault.url("diary/.2026-10-01.md.icloud")
        let coordination = Planting { operation in
            if case .move(_, let destination) = operation, destination.standardizedFileURL.path == target {
                try? Data("yer tutucu".utf8).write(to: placeholder)
            }
        }
        let outcome = try await vault.store(coordination: coordination).migratingLegacyDayFolder()
        #expect(outcome.waiting.contains("\(legacy)/2026-10-01.md"))
        #expect(!FileManager.default.fileExists(atPath: target))
        #expect(FileManager.default.fileExists(atPath: vault.url("\(legacy)/2026-10-01.md").path))
    }

    /// A day file another process writes under the chosen name before the boundary is never
    /// replaced, even with a move that would replace it: the existence check inside the boundary
    /// stops the claim and the retry picks a day copy.
    @Test func aTargetCreatedBeforeTheBoundaryIsNeverReplaced() async throws {
        let vault = try LegacyVault()
        defer { vault.remove() }
        // `2026-10-04` needs no change, so it is moved; this move replaces like `rename(2)`.
        let target = vault.url("diary/2026-10-04.md").standardizedFileURL.path
        let planted = Data("Başka cihaz.\n".utf8)
        let once = Once()
        let coordination = Planting { operation in
            if case .move(_, let destination) = operation, destination.standardizedFileURL.path == target,
                once.first()
            {
                try? planted.write(to: URL(fileURLWithPath: target))
            }
        }
        let replacingMove: @Sendable (URL, URL) throws -> Void = { source, destination in
            guard rename(source.path, destination.path) == 0 else { throw CocoaError(.fileWriteUnknown) }
        }
        let outcome = try await vault.store(moveFile: replacingMove, coordination: coordination)
            .migratingLegacyDayFolder()
        #expect(try Data(contentsOf: URL(fileURLWithPath: target)) == planted)
        #expect(outcome.copies.contains("diary/2026-10-04 2.md"))
        #expect(outcome.failed.isEmpty)
    }

    /// A day file another process writes under the chosen name inside the boundary, after the
    /// checks, is never replaced: the write is exclusive, and the retry picks a day copy.
    @Test func aTargetCreatedInsideTheBoundaryIsNeverReplaced() async throws {
        let vault = try LegacyVault()
        defer { vault.remove() }
        let source = vault.url("\(legacy)/2026-10-01.md").standardizedFileURL.path
        let target = vault.url("diary/2026-10-01.md")
        let planted = Data("Başka cihaz.\n".utf8)
        let reads = Counter()
        // The second read of the source is the one inside the boundary, after the checks.
        let readFile: @Sendable (URL) throws -> Data = { url in
            if url.standardizedFileURL.path == source, reads.next() == 2 { try? planted.write(to: target) }
            return try Data(contentsOf: url)
        }
        let outcome = try await vault.store(readFile: readFile).migratingLegacyDayFolder()
        #expect(try Data(contentsOf: target) == planted)
        #expect(outcome.copies.contains("diary/2026-10-01 2.md"))
        #expect(outcome.failed.isEmpty)
    }

    /// An index that cannot take a batch's paths does not end the run or lose its counts: every
    /// batch moves its files, and the outcome says the index missed them.
    @Test func aFailedIndexUpdateNeitherStopsTheRunNorLosesItsCounts() async throws {
        let vault = try LegacyVault()
        defer { vault.remove() }
        try await vault.index.database.write {
            try $0.execute(
                sql: "CREATE TRIGGER fail_files BEFORE INSERT ON files BEGIN SELECT RAISE(FAIL, 'test'); END")
        }
        let first = try await vault.store().migratingLegacyDayBatch(limit: 2)
        #expect(first.indexUpdateFailed && !first.finished && first.moved.count == 2)
        let outcome = try await vault.store().migratingLegacyDayFolder(batchSize: 2)
        let wanted = try JSONDecoder().decode(
            Outcome.self, from: Data(contentsOf: LegacyVault.fixture().appendingPathComponent("outcome.json")))
        #expect(outcome.indexUpdateFailed && outcome.finished)
        #expect(first.moved + outcome.moved == wanted.moved && outcome.copies == wanted.copies)
        #expect(outcome.failed.isEmpty)
        #expect(try Self.tree(vault.root) == expected())
    }

    /// Batches leave the write queue between them and add up to the same run.
    @Test func batchesAddUpToOneRun() async throws {
        let vault = try LegacyVault()
        defer { vault.remove() }
        let outcome = try await vault.store().migratingLegacyDayFolder(batchSize: 2)
        let wanted = try JSONDecoder().decode(
            Outcome.self, from: Data(contentsOf: LegacyVault.fixture().appendingPathComponent("outcome.json")))
        #expect(outcome.moved == wanted.moved && outcome.copies == wanted.copies)
        #expect(try Self.tree(vault.root) == expected())
        let first = try await vault.store().migratingLegacyDayBatch(limit: 1)
        #expect(first.finished && first.moved.isEmpty)
    }
}

/// Runs `before` with each operation just before its accessor, as another process would.
private struct Planting: FileCoordination {
    let before: @Sendable (FileCoordinationOperation) -> Void

    init(_ before: @escaping @Sendable (FileCoordinationOperation) -> Void) { self.before = before }

    func coordinate<T>(
        _ operation: FileCoordinationOperation, accessor: (FileCoordinationAccess) throws -> T
    ) throws -> T {
        before(operation)
        return try accessor(FileCoordinationAccess())
    }
}

/// True the first time only.
private final class Once: @unchecked Sendable {
    private let lock = NSLock()
    private var done = false

    func first() -> Bool {
        lock.lock()
        defer { lock.unlock() }
        defer { done = true }
        return !done
    }
}

/// Counts calls, from 1.
private final class Counter: @unchecked Sendable {
    private let lock = NSLock()
    private var count = 0

    func next() -> Int {
        lock.lock()
        defer { lock.unlock() }
        count += 1
        return count
    }
}
