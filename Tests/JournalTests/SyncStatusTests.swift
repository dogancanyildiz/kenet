import Foundation
import Testing
import VaultIndex

@testable import Journal

@MainActor @Suite(.timeLimit(.minutes(1)))
struct SyncStatusTests {
    @Test func onlyAnICloudVaultReportsSync() {
        #expect(SyncStatus.resolve(isCloudVault: false, pendingDownloads: 3, mergingCopies: 2) == .idle)
        #expect(SyncStatus.resolve(isCloudVault: true, pendingDownloads: 0, mergingCopies: 0) == .idle)
        #expect(SyncStatus.resolve(isCloudVault: true, pendingDownloads: 3, mergingCopies: 0) == .downloading(3))
        // A merge in progress is what the indicator says while downloads still wait.
        #expect(SyncStatus.resolve(isCloudVault: true, pendingDownloads: 3, mergingCopies: 2) == .mergingCopies(2))
    }

    @Test func messagesFollowTheCatalog() {
        #expect(SyncStatus.idle.message.isEmpty)
        #expect(SyncStatus.downloading(3).message == String(localized: "\(3) dosya iCloud’dan iniyor."))
        #expect(SyncStatus.mergingCopies(2).message == String(localized: "\(2) gün kopyası birleştiriliyor."))
        #expect(
            VoiceOverCopy.syncStatusLabel(.downloading(3))
                == String(localized: "Eşitleme durumu: \(SyncStatus.downloading(3).message)"))
    }

    /// Downloading while placeholders wait; the count falls as files arrive and ends idle.
    @Test func downloadCountFallsToIdle() async throws {
        let expected = try PlaceholderExpectation.load()
        let context = try CloudSyncTestContext(.icloud, fixture: "placeholder")
        defer { context.clean() }
        await context.start()
        #expect(context.store.syncStatus == .downloading(expected.pending.count))

        try context.arrive("journal/2026-09-30.md", bytes: CloudDownloadTests.arrivedDay)
        await context.refresh()
        #expect(context.store.syncStatus == .downloading(expected.pending.count - 1))

        for path in expected.pending where path != "journal/2026-09-30.md" {
            try context.arrive(path, bytes: "Not\n")
        }
        await context.refresh()
        #expect(context.store.sync.pendingDownloads.isEmpty)
        #expect(context.store.syncStatus == .idle)
    }

    /// The same placeholders in a local vault or a selected folder never show the indicator.
    @Test(arguments: [CloudSyncTestContext.Kind.local, .selected])
    func otherVaultsStayIdle(_ kind: CloudSyncTestContext.Kind) async throws {
        let context = try CloudSyncTestContext(kind, fixture: "placeholder")
        defer { context.clean() }
        await context.start()
        #expect(!context.store.sync.pendingDownloads.isEmpty)
        #expect(context.store.syncStatus == .idle)
    }

    /// Another vault's lists and counts never count: a vault opened next starts over.
    @Test func anotherVaultStartsOver() async throws {
        let context = try CloudSyncTestContext(
            .icloud, fixture: "placeholder", downloader: RecordingCloudDownloader(refusing: 1))
        defer { context.clean() }
        await context.start()
        #expect(context.store.syncStatus != .idle)
        #expect(context.store.sync.downloadFailures == 1)
        let empty = context.directory.appendingPathComponent("Empty", isDirectory: true)
        try FileManager.default.createDirectory(at: empty, withIntermediateDirectories: true)
        await context.store.select(empty)
        #expect(context.store.vaultURL == empty)
        #expect(context.store.syncStatus == .idle)
        #expect(context.store.sync.pendingDownloads.isEmpty)
        #expect(context.store.sync.downloadFailures == 0)
    }
}
