import Foundation
import Testing

@testable import Journal

@MainActor
struct VaultLocationTests {
    @Test func defaultVaultContainsOnlyRequiredFiles() throws {
        let temp = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: temp) }
        let suite = try TestDefaults()
        defer { suite.clean() }
        let location = VaultLocation(defaults: suite.defaults, documentsURL: temp)
        let root = try location.createDefaultVault()
        #expect(
            Set(try FileManager.default.contentsOfDirectory(atPath: root.path))
                == Set([".app", "journal", "people", "places", "goals", "notes", "templates"]))
        let data = try Data(contentsOf: root.appendingPathComponent(".app/vault.json"))
        let json = try #require(JSONSerialization.jsonObject(with: data) as? [String: Int])
        #expect(json == ["formatVersion": 1])
        for name in ["journal", "people", "places", "goals", "notes"] {
            #expect(try FileManager.default.contentsOfDirectory(atPath: root.appendingPathComponent(name).path).isEmpty)
        }
        try Data("custom settings".utf8).write(to: root.appendingPathComponent(".app/vault.json"))
        _ = try location.createDefaultVault()
        #expect(
            try String(contentsOf: root.appendingPathComponent(".app/vault.json"), encoding: .utf8) == "custom settings"
        )
    }

    @Test func invalidBookmarkIsInaccessibleWithoutCreatingLocalVault() throws {
        let temp = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: temp) }
        let suite = try TestDefaults()
        defer { suite.clean() }
        let defaults = suite.defaults
        defaults.set(Data("invalid".utf8), forKey: "vaultBookmark")
        let location = VaultLocation(defaults: defaults, documentsURL: temp)
        let resolved = try location.resolve()
        #expect(resolved == .inaccessible)
        #expect(defaults.data(forKey: "vaultBookmark") == nil)
        #expect(!FileManager.default.fileExists(atPath: temp.appendingPathComponent("Vault").path))
    }
}

@MainActor
struct IndexStoreTests {
    @Test func sampleVaultCountsAndSeparateDatabases() async throws {
        let temp = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: temp) }
        let fixture = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
            .deletingLastPathComponent().appendingPathComponent("Fixtures/vaults/sample")
        let documents = temp.appendingPathComponent("documents")
        try FileManager.default.createDirectory(at: documents, withIntermediateDirectories: true)
        let sample = documents.appendingPathComponent("Vault")
        try FileManager.default.copyItem(at: fixture, to: sample)
        let suite = try TestDefaults()
        defer { suite.clean() }
        let defaults = suite.defaults
        let location = VaultLocation(defaults: defaults, documentsURL: documents)
        let store = IndexStore(location: location, supportURL: temp.appendingPathComponent("indexes"))
        await store.start()
        #expect(store.errorText == nil)
        #expect(store.counts.filesByKind["day"] == 14)
        #expect(store.counts.events == 40)
        #expect(store.counts.tasks == 24)
        #expect(store.counts.entities == 13)
        #expect(store.counts.links == 61)
        #expect(store.counts.unresolvedLinks == 1)
        #expect(store.lastUpdated != nil)
        await store.refresh(rebuild: true)
        #expect(store.counts.events == 40)
        let otherStore = IndexStore(
            location: VaultLocation(defaults: defaults, documentsURL: temp.appendingPathComponent("other")),
            supportURL: temp.appendingPathComponent("indexes"))
        await otherStore.start()
        #expect(otherStore.counts.files == 0)
        #expect(otherStore.errorText == nil)
        #expect(
            try FileManager.default.contentsOfDirectory(atPath: temp.appendingPathComponent("indexes").path)
                .filter { $0.hasSuffix(".sqlite") }.count == 2)
    }

    @Test func watcherUpdatesVisibleCounts() async throws {
        let temp = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: temp) }
        let suite = try TestDefaults()
        defer { suite.clean() }
        let defaults = suite.defaults
        let store = IndexStore(
            location: VaultLocation(defaults: defaults, documentsURL: temp),
            supportURL: temp.appendingPathComponent("indexes"))
        await store.start()
        let root = try #require(store.vaultURL)
        try Data("- [ ] Example task\n".utf8).write(to: root.appendingPathComponent("notes/example.md"))
        for _ in 0..<150 {
            if store.counts.tasks == 1 { break }
            try await Task.sleep(for: .milliseconds(20))
        }
        #expect(store.counts.tasks == 1)
    }
}

actor ChangeCounter {
    private(set) var value = 0
    func increment() { value += 1 }
}

@Suite(.serialized)
struct VaultWatcherTests {
    @Test func directoryEventsAddDeleteAndDebounce() async throws {
        let root = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let counter = ChangeCounter()
        let watcher = VaultWatcher(root: root) { Task { await counter.increment() } }
        defer { watcher.stop() }
        for number in 0..<5 {
            try Data("note".utf8).write(to: root.appendingPathComponent("note-\(number).md"))
        }
        try await waitForChange(counter, after: 0)
        try await Task.sleep(for: .milliseconds(400))
        #expect(await counter.value == 1)
        try FileManager.default.removeItem(at: root.appendingPathComponent("note-0.md"))
        try await waitForChange(counter, after: 1)
        let nested = root.appendingPathComponent("nested")
        try FileManager.default.createDirectory(at: nested, withIntermediateDirectories: true)
        let before = await counter.value
        try await waitForChange(counter, after: before)
        let installed = await counter.value
        try Data("nested".utf8).write(to: nested.appendingPathComponent("note.md"))
        try await waitForChange(counter, after: installed)
    }

    @Test func foregroundTimerDetectsContentEditAndStopsInBackground() async throws {
        let root = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let file = root.appendingPathComponent("note.md")
        try Data("before".utf8).write(to: file)
        let counter = ChangeCounter()
        let watcher = VaultWatcher(root: root, interval: 0.8) { Task { await counter.increment() } }
        defer { watcher.stop() }
        watcher.setForeground(true)
        try await waitForChange(counter, after: 0)
        let before = await counter.value
        let handle = try FileHandle(forWritingTo: file)
        try handle.write(contentsOf: Data("after!".utf8))
        try handle.close()
        try await waitForChange(counter, after: before)
        watcher.setForeground(false)
        try await Task.sleep(for: .milliseconds(400))
        let paused = await counter.value
        try await Task.sleep(for: .milliseconds(1200))
        #expect(await counter.value == paused)
        watcher.setForeground(true)
        try await waitForChange(counter, after: paused)
    }

    @Test func excludedDirectoriesAndStoppedWatcherDoNotNotify() async throws {
        let root = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        for name in [".hidden", "templates", "conflicts"] {
            try FileManager.default.createDirectory(
                at: root.appendingPathComponent(name), withIntermediateDirectories: true)
        }
        let counter = ChangeCounter()
        let watcher = VaultWatcher(root: root) { Task { await counter.increment() } }
        defer { watcher.stop() }
        for name in [".hidden", "templates", "conflicts"] {
            try Data("ignored".utf8).write(to: root.appendingPathComponent("\(name)/note.md"))
        }
        try await Task.sleep(for: .milliseconds(700))
        #expect(await counter.value == 0)
        watcher.stop()
        try Data("stopped".utf8).write(to: root.appendingPathComponent("note.md"))
        try await Task.sleep(for: .milliseconds(700))
        #expect(await counter.value == 0)
    }
}

private func temporaryDirectory() throws -> URL {
    let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
    try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
    return url
}

private func waitForChange(_ counter: ChangeCounter, after value: Int) async throws {
    for _ in 0..<150 {
        if await counter.value > value { return }
        try await Task.sleep(for: .milliseconds(20))
    }
    Issue.record("Expected watcher notification before timeout")
}
