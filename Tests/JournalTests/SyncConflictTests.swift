import Foundation
import SwiftUI
import Testing
import VaultIndex

@testable import Journal

/// Stands in for iCloud: answers with the versions set for a vault-relative path and records
/// every path it was asked about.
final class FakeConflictVersionSource: ConflictVersionSource, @unchecked Sendable {
    private let lock = NSLock()
    private let versions: [String: [ConflictVersion]]
    private var askedPaths: [String] = []

    init(_ versions: [String: [ConflictVersion]]) { self.versions = versions }

    /// Vault-relative paths asked so far, in asking order.
    var asked: [String] { lock.withLock { askedPaths } }

    func unresolvedConflicts(at url: URL) -> [ConflictVersion] {
        let marker = "/Vault/"
        guard let range = url.path.range(of: marker, options: .backwards) else { return [] }
        let path = String(url.path[range.upperBound...])
        lock.withLock { askedPaths.append(path) }
        return versions[path] ?? []
    }
}

/// A copy of `Fixtures/vaults/conflict-copies/source` named `Vault` inside `folder`, opened through
/// an `IndexStore` that asks `source` for iCloud versions.
@MainActor
struct ConflictVaultTestContext {
    let directory: URL
    let root: URL
    let defaults: TestDefaults
    let store: IndexStore

    static let fixtures = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
        .deletingLastPathComponent().appendingPathComponent("Fixtures/vaults/conflict-copies")

    init(folder: String, source: any ConflictVersionSource) throws {
        directory = try testDirectory()
        root = directory.appendingPathComponent(folder).appendingPathComponent("Vault")
        try FileManager.default.createDirectory(at: root.deletingLastPathComponent(), withIntermediateDirectories: true)
        try FileManager.default.copyItem(at: Self.fixtures.appendingPathComponent("source"), to: root)
        defaults = try TestDefaults()
        store = IndexStore(
            location: VaultLocation(defaults: defaults.defaults, documentsURL: directory, bookmarks: pathBookmarks()),
            supportURL: directory.appendingPathComponent("indexes"), conflictVersions: source)
    }

    func start() async { await store.select(root) }

    /// `expected.json`'s conflict copies.
    static func expectedConflictCopies() throws -> [CopyFile] {
        struct Copy: Decodable {
            let folder: String
            let copy: String
            let original: String
        }
        struct Expected: Decodable {
            let conflictCopies: [Copy]
        }
        let expected = try JSONDecoder().decode(
            Expected.self, from: Data(contentsOf: fixtures.appendingPathComponent("expected.json")))
        return expected.conflictCopies.map { CopyFile(folder: $0.folder, copy: $0.copy, original: $0.original) }
    }

    /// Every regular file under the vault with its bytes.
    func files() throws -> [String: Data] {
        var bytes: [String: Data] = [:]
        for path in try FileManager.default.subpathsOfDirectory(atPath: root.path) {
            let url = root.appendingPathComponent(path)
            var isDirectory: ObjCBool = false
            guard FileManager.default.fileExists(atPath: url.path, isDirectory: &isDirectory), !isDirectory.boolValue
            else { continue }
            bytes[path] = try Data(contentsOf: url)
        }
        return bytes
    }

    func clean() {
        defaults.clean()
        try? FileManager.default.removeItem(at: directory)
    }
}

@MainActor @Suite(.timeLimit(.minutes(1)))
struct SyncConflictTests {
    private static let iCloud = "Library/Mobile Documents/com~apple~CloudDocs"
    private static let mac = ConflictVersion(modificationTime: 1_791_000_000, deviceName: "Ada'nın Mac'i")
    private static let phone = ConflictVersion(modificationTime: 1_791_003_600, deviceName: "Ece'nin iPhone'u")
    private static let unknown = ConflictVersion(modificationTime: 0, deviceName: nil)

    /// Versions for the day file, a day copy and a note, given oldest first.
    private static func source() -> FakeConflictVersionSource {
        FakeConflictVersionSource([
            "journal/2026-10-02.md": [unknown, mac, phone],
            "journal/2026-10-02 2.md": [mac],
            "2026-10-02 (conflict 20261002T110533Z).md": [phone, mac],
        ])
    }

    /// A vault outside iCloud Drive costs nothing: no file is asked, nothing is listed.
    @Test func localVaultAsksNoFileAndListsNothing() async throws {
        let source = Self.source()
        for folder in ["Documents", "Library/CloudStorage/Dropbox"] {
            let context = try ConflictVaultTestContext(folder: folder, source: source)
            defer { context.clean() }
            await context.start()
            #expect(context.store.vaultURL != nil)
            #expect(context.store.syncedFolder != .iCloudDrive)
            #expect(try await context.store.computeConflictedFiles().isEmpty, "\(folder)")
        }
        #expect(source.asked.isEmpty)
    }

    /// Every indexed file and every day copy is asked once; flagged files come in path order with
    /// their versions newest first. Conflict copies under `conflicts/` are not vault files and are
    /// not asked. Listing changes no byte.
    @Test func iCloudVaultListsFlaggedFilesNewestFirstAndChangesNothing() async throws {
        let source = Self.source()
        let context = try ConflictVaultTestContext(folder: Self.iCloud, source: source)
        defer { context.clean() }
        try Data("- Kopya\n".utf8).write(to: context.root.appendingPathComponent("journal/2026-10-02 2.md"))
        #expect(try await context.store.computeConflictedFiles().isEmpty)
        await context.start()
        #expect(context.store.syncedFolder == .iCloudDrive)
        let before = try context.files()

        let listed = try await context.store.computeConflictedFiles()

        #expect(
            listed == [
                ConflictedFile(path: "2026-10-02 (conflict 20261002T110533Z).md", versions: [Self.phone, Self.mac]),
                ConflictedFile(path: "journal/2026-10-02 2.md", versions: [Self.mac]),
                ConflictedFile(path: "journal/2026-10-02.md", versions: [Self.phone, Self.mac, Self.unknown]),
            ])
        #expect(
            source.asked.sorted() == [
                "2026-10-02 (conflict 20261002T110533Z).md", "journal/2026-10-02 2.md", "journal/2026-10-02.md",
            ])
        #expect(try context.files() == before)
    }

    /// The saved versions under `conflicts/` are listed in any vault, synced or not, and stay in place.
    @Test func conflictCopiesAreListedInAnyVault() async throws {
        let expected = try ConflictVaultTestContext.expectedConflictCopies()
        for folder in ["Documents", Self.iCloud] {
            let context = try ConflictVaultTestContext(folder: folder, source: Self.source())
            defer { context.clean() }
            #expect(try await context.store.computeConflictCopies().isEmpty)
            await context.start()
            let before = try context.files()
            #expect(try await context.store.computeConflictCopies() == expected, "\(folder)")
            #expect(try context.files() == before)
        }
    }

    /// No conflicts, no section: both Diagnostics sections draw nothing when their list is empty.
    @Test func emptySectionsDrawNothing() {
        #expect(Self.size(ConflictedFilesSection(files: [])).height == 0)
        #expect(Self.size(ConflictCopiesSection(copies: [])).height == 0)
        let file = ConflictedFile(path: "journal/2026-10-02.md", versions: [Self.phone, Self.mac])
        #expect(Self.size(ConflictedFilesSection(files: [file])).height > 0)
        let copy = CopyFile(
            folder: "conflicts", copy: "conflicts/2026-10-02 (conflict 20261002T110533Z).md",
            original: "journal/2026-10-02.md")
        #expect(Self.size(ConflictCopiesSection(copies: [copy])).height > 0)
    }

    /// Each named device once, in version order; no names, no line.
    @Test func deviceNamesAreListedOnceInVersionOrder() {
        let again = ConflictVersion(modificationTime: 1_790_000_000, deviceName: "Ece'nin iPhone'u")
        let file = ConflictedFile(path: "Ada.md", versions: [Self.phone, Self.unknown, Self.mac, again])
        #expect(ConflictedFilesSection.deviceNames(file) == "Ece'nin iPhone'u, Ada'nın Mac'i")
        #expect(ConflictedFilesSection.deviceNames(ConflictedFile(path: "Ada.md", versions: [Self.unknown])) == nil)
    }

    private static func size(_ view: some View) -> CGSize {
        let renderer = ImageRenderer(content: view.frame(width: 360))
        renderer.scale = 1
        guard let image = renderer.cgImage else { return .zero }
        return CGSize(width: image.width, height: image.height)
    }
}
