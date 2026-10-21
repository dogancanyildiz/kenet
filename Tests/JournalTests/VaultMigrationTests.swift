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
        let canonical = try context.location.useCloudVault()
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
