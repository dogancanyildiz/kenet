import Foundation
import Testing
import VaultIndex

@testable import Journal

/// A vault under a synced folder and one with sync copies, opened through `IndexStore`.
@MainActor
struct SyncedVaultTestContext {
    let directory: URL
    let root: URL
    let defaults: TestDefaults
    let store: IndexStore

    static let fixtures = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
        .deletingLastPathComponent().appendingPathComponent("Fixtures/vaults/copy-files")

    /// `folder` is where the vault lives inside a fresh temporary directory; the vault itself is
    /// a copy of `Fixtures/vaults/copy-files/source`.
    init(folder: String = "Library/Mobile Documents/com~apple~CloudDocs") throws {
        directory = try testDirectory()
        root = directory.appendingPathComponent(folder).appendingPathComponent("Vault")
        try FileManager.default.createDirectory(at: root.deletingLastPathComponent(), withIntermediateDirectories: true)
        try FileManager.default.copyItem(at: Self.fixtures.appendingPathComponent("source"), to: root)
        defaults = try TestDefaults()
        store = IndexStore(
            location: VaultLocation(defaults: defaults.defaults, documentsURL: directory, bookmarks: pathBookmarks()),
            supportURL: directory.appendingPathComponent("indexes"))
    }

    func start() async { await store.select(root) }

    /// Day copies, then entity copies, as `expected.json` lists them.
    static func expectedCopies() throws -> [CopyFile] {
        struct Copy: Decodable {
            let folder: String
            let copy: String
            let original: String
        }
        struct Expected: Decodable {
            let entityCopies: [Copy]
            let dayCopies: [Copy]
        }
        let expected = try JSONDecoder().decode(
            Expected.self, from: Data(contentsOf: fixtures.appendingPathComponent("expected.json")))
        return (expected.dayCopies + expected.entityCopies).map {
            CopyFile(folder: $0.folder, copy: $0.copy, original: $0.original)
        }
    }

    func clean() {
        defaults.clean()
        try? FileManager.default.removeItem(at: directory)
    }
}

@MainActor @Suite(.timeLimit(.minutes(1)))
struct SyncedFolderNoticeTests {
    private static let services: [SyncedFolderKind: String] = [
        .iCloudDrive: "iCloud Drive", .dropbox: "Dropbox", .oneDrive: "OneDrive", .googleDrive: "Google Drive",
    ]

    private static func bundle(_ language: String) throws -> Bundle {
        let path = try #require(Bundle.main.path(forResource: language, ofType: "lproj"))
        return try #require(Bundle(path: path))
    }

    /// Each named service appears in its notice; a file provider gets the generic phrase and no name.
    @Test func noticeNamesTheServiceOrTheGenericPhrase() {
        for kind in SyncedFolderKind.allCases {
            let notice = kind.notice()
            if let name = Self.services[kind] {
                #expect(kind.serviceName == name)
                #expect(notice.contains(name), "\(kind)")
            } else {
                #expect(kind.serviceName == nil)
                #expect(notice.contains(String(localized: "bir eşitleme hizmeti")))
                #expect(!Self.services.values.contains { notice.contains($0) })
            }
        }
    }

    /// The decided sentence in both catalogs; the CI process language is English, so each table
    /// is read directly.
    @Test func noticeReadsAsDecidedInTurkishAndEnglish() throws {
        let turkish = try Self.bundle("tr")
        #expect(
            SyncedFolderKind.dropbox.notice(bundle: turkish)
                == "Bu klasör Dropbox ile eşitleniyor. Kenet dosyaları koordineli yazar; iki cihaz aynı günü düzenlerse gün kopyası oluşabilir ve kopya Tanılama'da görünür."
        )
        #expect(
            SyncedFolderKind.fileProvider.notice(bundle: turkish).hasPrefix(
                "Bu klasör bir eşitleme hizmeti ile eşitleniyor."))
        let english = try Self.bundle("en")
        #expect(
            SyncedFolderKind.iCloudDrive.notice(bundle: english)
                == "This folder syncs with iCloud Drive. Kenet coordinates its file writes; if two devices edit the same day, a day copy can appear, and the copy shows in Diagnostics."
        )
        #expect(
            SyncedFolderKind.fileProvider.notice(bundle: english).hasPrefix("This folder syncs with a sync service."))
    }

    @Test func storeReportsTheServiceOfTheOpenVault() async throws {
        let synced = try SyncedVaultTestContext()
        defer { synced.clean() }
        #expect(synced.store.syncedFolder == nil)
        await synced.start()
        #expect(synced.store.syncedFolder == .iCloudDrive)

        let dropbox = try SyncedVaultTestContext(folder: "Library/CloudStorage/Dropbox")
        defer { dropbox.clean() }
        await dropbox.start()
        #expect(dropbox.store.syncedFolder == .dropbox)

        let local = try SyncedVaultTestContext(folder: "Documents")
        defer { local.clean() }
        await local.start()
        #expect(local.store.vaultURL != nil)
        #expect(local.store.syncedFolder == nil)
    }

    /// Day copies from disk, then entity copies from the index; the copies stay where they are.
    @Test func copyFilesListDayThenEntityCopiesAndChangeNothing() async throws {
        let context = try SyncedVaultTestContext(folder: "Documents")
        defer { context.clean() }
        #expect(try await context.store.computeCopyFiles().isEmpty)
        await context.start()
        let expected = try SyncedVaultTestContext.expectedCopies()
        #expect(try await context.store.computeCopyFiles() == expected)
        for copy in expected {
            #expect(FileManager.default.fileExists(atPath: context.root.appendingPathComponent(copy.copy).path))
        }
        #expect(context.store.content.entities.contains { $0.id == "people/Elif 2.md" })
    }
}
