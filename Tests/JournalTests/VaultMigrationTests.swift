import Foundation
import Testing
import VaultFormat

@testable import Journal

@MainActor
struct VaultMigrationTests {
    @Test func verifiedCopyKeepsSourceAndIndexesNewPath() async throws {
        let context = try CloudVaultContext()
        defer { context.clean() }
        try context.installLocalSample()
        let file = "journal/2026-09-20.md"
        let before = try Data(contentsOf: context.location.localRoot.appendingPathComponent(file))
        // Include arbitrary non-Markdown bytes and empty directories in the copy contract.
        let unknown = context.location.localRoot.appendingPathComponent(".unknown")
        try Data([0, 255, 13, 10]).write(to: unknown)
        try FileManager.default.createDirectory(
            at: context.location.localRoot.appendingPathComponent("empty"), withIntermediateDirectories: true)
        await context.store.start()
        await context.store.migrateVaultToCloud(deviceName: "Fictional Phone")
        let opened = try #require(context.store.vaultURL)
        #expect(opened == context.container.appendingPathComponent("Documents/Kenet"))
        #expect(context.store.vaultKind == .icloud)
        #expect(context.store.retainedLocalVault)
        #expect(context.store.lastUpdated != nil)
        #expect(context.store.counts.events == 40)
        #expect(try Data(contentsOf: context.location.localRoot.appendingPathComponent(file)) == before)
        #expect(try Data(contentsOf: opened.appendingPathComponent(file)) == before)
        #expect(try Data(contentsOf: opened.appendingPathComponent(".unknown")) == Data([0, 255, 13, 10]))
        #expect(FileManager.default.fileExists(atPath: opened.appendingPathComponent("empty").path))
        let eventDay = try #require(CalendarDate("2039-01-01"))
        #expect(await context.store.addEvent(on: eventDay, text: "Cloud-only event", time: nil))
        let day = "journal/\(eventDay).md"
        #expect(
            try String(contentsOf: opened.appendingPathComponent(day), encoding: .utf8).contains("Cloud-only event"))
        #expect(!FileManager.default.fileExists(atPath: context.location.localRoot.appendingPathComponent(day).path))
    }

    @Test(arguments: ["missing", "short", "sameSize"])
    func incompleteCopyNeverChangesRegistration(_ damage: String) async throws {
        let context = try CloudVaultContext()
        defer { context.clean() }
        try context.installLocalSample()
        try await context.location.refreshCloudAvailability()
        let migration = VaultMigration(copyDirectory: { source, target in
            try FileManager.default.copyItem(at: source, to: target)
            let file = target.appendingPathComponent("journal/2026-09-20.md")
            if damage == "missing" {
                try FileManager.default.removeItem(at: file)
            } else if damage == "short" {
                try Data([0]).write(to: file)
            } else {
                let bytes = try Data(contentsOf: file)
                try Data(repeating: 0, count: bytes.count).write(to: file)
            }
        })
        do {
            _ = try await context.location.migrateToCloud(deviceName: "Phone", migration: migration)
            Issue.record("Damaged copy was published")
        } catch {}
        #expect(context.location.kind == .local)
        #expect(FileManager.default.fileExists(atPath: context.location.localRoot.path))
        #expect(
            !FileManager.default.fileExists(atPath: context.container.appendingPathComponent("Documents/Kenet").path))
    }

    @Test func existingCloudVaultIsNeverOverwrittenAndSuffixIsUnique() async throws {
        let context = try CloudVaultContext()
        defer { context.clean() }
        try context.installLocalSample()
        try await context.location.refreshCloudAvailability()
        let canonical = try await context.location.useCloudVault()
        let marker = canonical.appendingPathComponent(".app/vault.json")
        let before = try Data(contentsOf: marker)
        _ = try context.location.useLocalVault()
        let occupied = context.container.appendingPathComponent("Documents/Kenet-Fable-Phone")
        try FileManager.default.createDirectory(at: occupied, withIntermediateDirectories: true)
        await context.store.start()
        await context.store.migrateVaultToCloud(deviceName: "Fable/Phone")
        let copied = context.container.appendingPathComponent("Documents/Kenet-Fable-Phone-2")
        #expect(context.store.vaultURL == canonical)
        #expect(context.store.counts.events == 0)
        #expect(context.store.lastUpdated != nil)
        #expect(context.store.notice?.contains(canonical.path) == true)
        #expect(context.store.notice?.contains(copied.path) == true)
        #expect(try Data(contentsOf: marker) == before)
        #expect(!FileManager.default.fileExists(atPath: canonical.appendingPathComponent("journal/2026-09-20.md").path))
        #expect(
            FileManager.default.fileExists(atPath: copied.appendingPathComponent("journal/2026-09-20.md").path))
        #expect(FileManager.default.fileExists(atPath: context.location.localRoot.path))
        #expect(context.location.kind == .icloud)
    }

    @Test func interruptedCopyCleansOnlyOwnedTemporaryFolderAndOffersAgain() async throws {
        let context = try CloudVaultContext()
        defer { context.clean() }
        try context.installLocalSample()
        let name = ".Kenet-tasima-" + UUID().uuidString
        let documents = context.container.appendingPathComponent("Documents")
        let owned = documents.appendingPathComponent(name)
        let other = documents.appendingPathComponent(".Kenet-tasima-" + UUID().uuidString)
        try FileManager.default.createDirectory(at: owned, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: other, withIntermediateDirectories: true)
        context.defaults.defaults.set(name, forKey: "vaultMigrationTemporaryName")
        await context.store.start()
        #expect(!FileManager.default.fileExists(atPath: owned.path))
        #expect(FileManager.default.fileExists(atPath: other.path))
        #expect(context.store.showsCloudMigration)
        #expect(context.location.kind == .local)
        #expect(FileManager.default.fileExists(atPath: context.location.localRoot.path))
    }

    @Test func failedManualMigrationOffersAgainOnNextStart() async throws {
        let context = try CloudVaultContext()
        defer { context.clean() }
        try context.installLocalSample()
        try await context.location.refreshCloudAvailability()
        context.location.declineCloudMigration()
        let migration = VaultMigration(copyDirectory: { source, target in
            try FileManager.default.copyItem(at: source, to: target)
            throw CocoaError(.fileWriteUnknown)
        })
        do {
            _ = try await context.location.migrateToCloud(deviceName: "Phone", migration: migration)
            Issue.record("Copy should fail")
        } catch {}
        let name = try #require(context.defaults.defaults.string(forKey: "vaultMigrationTemporaryName"))
        await context.store.start()
        #expect(context.store.showsCloudMigration)
        #expect(
            !FileManager.default.fileExists(
                atPath: context.container.appendingPathComponent("Documents").appendingPathComponent(name).path))
        #expect(context.location.kind == .local)
    }

    @Test(arguments: ["symlink", "placeholder"])
    func unsafeSourceIsNotPublished(_ kind: String) async throws {
        let context = try CloudVaultContext()
        defer { context.clean() }
        try context.installLocalSample()
        if kind == "symlink" {
            try FileManager.default.createSymbolicLink(
                at: context.location.localRoot.appendingPathComponent("link"),
                withDestinationURL: context.directory)
        } else {
            try Data().write(to: context.location.localRoot.appendingPathComponent(".pending.md.icloud"))
        }
        await context.store.start()
        await context.store.migrateVaultToCloud(deviceName: "Phone")
        #expect(context.store.errorText != nil)
        #expect(context.location.kind == .local)
        #expect(
            !FileManager.default.fileExists(
                atPath: context.container.appendingPathComponent("Documents/Kenet").path))
        #expect(FileManager.default.fileExists(atPath: context.location.localRoot.path))
    }

    @Test func placeholderCloudVaultIsDownloadedThenKeptBesideTheCopy() async throws {
        let provider = DownloadingUbiquityContainer(delivers: true)
        let context = try CloudVaultContext(ubiquity: provider)
        defer { context.clean() }
        await provider.set(context.container)
        try context.installLocalSample()
        let root = try context.installPlaceholderCloudVault()
        await context.store.start()
        await context.store.migrateVaultToCloud(deviceName: "Phone")
        #expect(context.store.errorText == nil)
        #expect(samePath(context.store.vaultURL, root))
        #expect(context.location.kind == .icloud)
        let requested = await provider.requests
        #expect(requested.count == 2)
        #expect(samePath(requested.first, root))
        let copied = context.container.appendingPathComponent("Documents/Kenet-Phone")
        #expect(FileManager.default.fileExists(atPath: copied.appendingPathComponent("journal/2026-09-20.md").path))
        #expect(!FileManager.default.fileExists(atPath: root.appendingPathComponent("journal/2026-09-20.md").path))
        #expect(
            try Data(contentsOf: root.appendingPathComponent(".app/vault.json"))
                == DownloadingUbiquityContainer.settings)
        #expect(FileManager.default.fileExists(atPath: context.location.localRoot.path))
    }

    @Test func copyRecognisesPlaceholderVaultAndNeverReplacesIt() async throws {
        let context = try CloudVaultContext()
        defer { context.clean() }
        try context.installLocalSample()
        let root = try context.installPlaceholderCloudVault()
        let before = try FileManager.default.subpathsOfDirectory(atPath: root.path).sorted()
        let result = try VaultMigration().copy(
            source: context.location.localRoot, container: context.container,
            temporaryName: ".Kenet-tasima-" + UUID().uuidString, deviceName: "Phone")
        #expect(result.openedExistingVault)
        #expect(result.copied.lastPathComponent == "Kenet-Phone")
        #expect(try FileManager.default.subpathsOfDirectory(atPath: root.path).sorted() == before)
        #expect(
            FileManager.default.fileExists(
                atPath: result.copied.appendingPathComponent("journal/2026-09-20.md").path))
    }

    @Test func stayingLocalAfterFailedMoveRemovesOnlyOwnTemporaryCopy() async throws {
        let context = try CloudVaultContext()
        defer { context.clean() }
        try context.installLocalSample()
        let documents = context.container.appendingPathComponent("Documents")
        let other = documents.appendingPathComponent(".Kenet-tasima-" + UUID().uuidString)
        try FileManager.default.createDirectory(at: other, withIntermediateDirectories: true)
        await context.store.start()
        #expect(context.store.showsCloudMigration)
        let failing = VaultMigration(copyDirectory: { source, target in
            try FileManager.default.copyItem(at: source, to: target)
            throw CocoaError(.fileWriteUnknown)
        })
        await context.store.migrateVaultToCloud(deviceName: "Phone", migration: failing)
        #expect(context.store.errorText != nil)
        let name = try #require(context.defaults.defaults.string(forKey: "vaultMigrationTemporaryName"))
        let owned = documents.appendingPathComponent(name)
        #expect(FileManager.default.fileExists(atPath: owned.path))
        await context.store.continueLocally()
        #expect(!FileManager.default.fileExists(atPath: owned.path))
        #expect(FileManager.default.fileExists(atPath: other.path))
        #expect(context.defaults.defaults.string(forKey: "vaultMigrationTemporaryName") == nil)
        #expect(!context.store.showsCloudMigration)
        #expect(context.location.kind == .local)
        #expect(context.store.vaultURL == context.location.localRoot)
        #expect(
            FileManager.default.fileExists(
                atPath: context.location.localRoot.appendingPathComponent("journal/2026-09-20.md").path))
    }

    @Test func writesAreClosedWhileTheVaultIsCopied() async throws {
        let context = try CloudVaultContext()
        defer { context.clean() }
        try context.installLocalSample()
        await context.store.start()
        #expect(context.store.canAddEvent)
        let store = context.store
        let recorder = MigrationFlagRecorder()
        let migration = VaultMigration(copyDirectory: { source, target in
            // The copy runs off the main actor while the store awaits it; read the flags there.
            DispatchQueue.main.sync {
                MainActor.assumeIsolated {
                    recorder.flags.append(.init(canAddEvent: store.canAddEvent, migrating: store.isMigratingCloud))
                }
            }
            try FileManager.default.copyItem(at: source, to: target)
        })
        await context.store.migrateVaultToCloud(deviceName: "Phone", migration: migration)
        #expect(recorder.flags == [.init(canAddEvent: false, migrating: true)])
        #expect(context.location.kind == .icloud)
        #expect(context.store.canAddEvent)
    }

    @Test func sourceChangedDuringCopyIsNotPublished() async throws {
        let context = try CloudVaultContext()
        defer { context.clean() }
        try context.installLocalSample()
        try await context.location.refreshCloudAvailability()
        let late = Data("- 10:00 Late event\n".utf8)
        let migration = VaultMigration(copyDirectory: { source, target in
            try FileManager.default.copyItem(at: source, to: target)
            try late.write(to: source.appendingPathComponent("journal/2026-09-21-late.md"))
        })
        do {
            _ = try await context.location.migrateToCloud(deviceName: "Phone", migration: migration)
            Issue.record("A copy older than its source was published")
        } catch {}
        #expect(context.location.kind == .local)
        #expect(
            !FileManager.default.fileExists(atPath: context.container.appendingPathComponent("Documents/Kenet").path))
        #expect(
            try Data(contentsOf: context.location.localRoot.appendingPathComponent("journal/2026-09-21-late.md"))
                == late)
    }

    @Test func unrecognizedCloudFolderIsNotReplaced() async throws {
        let context = try CloudVaultContext()
        defer { context.clean() }
        try context.installLocalSample()
        let destination = context.container.appendingPathComponent("Documents/Kenet")
        try FileManager.default.createDirectory(at: destination, withIntermediateDirectories: true)
        let file = destination.appendingPathComponent("unrecognized")
        try Data([42]).write(to: file)
        await context.store.start()
        await context.store.migrateVaultToCloud(deviceName: "Phone")
        #expect(context.store.errorText != nil)
        #expect(context.location.kind == .local)
        #expect(try Data(contentsOf: file) == Data([42]))
        #expect(FileManager.default.fileExists(atPath: context.location.localRoot.path))
    }
}

@MainActor
private final class MigrationFlagRecorder {
    struct Flags: Equatable {
        let canAddEvent: Bool
        let migrating: Bool
    }
    var flags: [Flags] = []
}
