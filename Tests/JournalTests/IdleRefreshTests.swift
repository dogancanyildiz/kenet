import Foundation
import Testing
import VaultIndex

@testable import Journal

@MainActor
struct IdleRefreshTests {
    @Test func emptyRefreshDoesNotPublishOrReplanNotifications() async throws {
        let temp = try testDirectory()
        defer { try? FileManager.default.removeItem(at: temp) }
        let suite = try TestDefaults()
        defer { suite.clean() }
        let store = IndexStore(
            location: VaultLocation(defaults: suite.defaults, documentsURL: temp),
            supportURL: temp.appendingPathComponent("indexes"))
        await store.start()
        let root = try #require(store.vaultURL)
        try Data("- [ ] Seed task\n".utf8).write(to: root.appendingPathComponent("notes/seed.md"))
        await store.refresh()
        #expect(store.counts.tasks == 1)

        let defaults = try TestDefaults()
        defer { defaults.clean() }
        let center = FakeNotificationCenter()
        let service = NotificationService(
            center: center, defaults: defaults.defaults,
            now: { notificationDate() }, timeZone: { notificationUTC }, debounce: .milliseconds(5))
        var publishes = 0
        store.onSnapshotChange = { content, url in
            publishes += 1
            service.update(snapshot: content, vaultID: url?.path)
        }
        service.activateAutomatically(environment: [:], arguments: [])
        service.update(snapshot: store.content, vaultID: store.vaultURL?.path)
        await service.replanNow()
        let afterStart = try #require(store.lastUpdated)
        let publishesAfterAttach = publishes
        let additionsAfterPlan = center.additions.count
        let removalsAfterPlan = center.removals.count

        await store.refresh()
        await store.refresh()
        await store.refresh()
        try await Task.sleep(for: .milliseconds(50))

        #expect(store.lastUpdated == afterStart)
        #expect(publishes == publishesAfterAttach)
        #expect(center.additions.count == additionsAfterPlan)
        #expect(center.removals.count == removalsAfterPlan)
        #expect(!store.isProcessing)

        try Data("- [ ] Grown task\n".utf8).write(to: root.appendingPathComponent("notes/seed.md"))
        await store.refresh()
        for _ in 0..<100 {
            if center.additions.count > additionsAfterPlan && !service.isPlanning { break }
            try await Task.sleep(for: .milliseconds(5))
        }

        #expect(store.lastUpdated != afterStart)
        #expect(publishes == publishesAfterAttach + 1)
        #expect(center.additions.count > additionsAfterPlan)
        #expect(center.removals.count == removalsAfterPlan + 1)
        #expect(store.counts.tasks == 1)
    }

    @Test func writeDuringRefreshKeepsPublishedResult() async throws {
        let temp = try testDirectory()
        defer { try? FileManager.default.removeItem(at: temp) }
        let suite = try TestDefaults()
        defer { suite.clean() }
        let gate = UpdateGate()
        let store = IndexStore(
            location: VaultLocation(defaults: suite.defaults, documentsURL: temp),
            supportURL: temp.appendingPathComponent("indexes"),
            update: { index, root, rebuild, previous, skip, skipped, previousContent in
                let result = try await IndexUpdate.read(
                    index: index, root: root, rebuild: rebuild, previousTypes: previous,
                    skipUnchanged: skip, previousSkipped: skipped, previousContent: previousContent)
                await gate.hold()
                return result
            })
        await store.start()
        let root = try #require(store.vaultURL)
        try Data("- [ ] External\n".utf8).write(to: root.appendingPathComponent("notes/external.md"))

        await gate.arm()
        let refresh = Task { await store.refresh() }
        try await waitForGate(gate)

        let write = Task { await store.addEvent(text: "Kept event", time: nil) }
        try await Task.sleep(for: .milliseconds(40))
        #expect(await gate.blocked)
        #expect(!store.isWriting)

        await gate.release()
        await refresh.value
        #expect(await write.value)
        #expect(store.counts.events == 1)
        #expect(
            store.content.days.contains { day in
                day.events.contains { $0.text.plainText.contains("Kept event") }
            })
        #expect(store.counts.tasks == 1)
        #expect(store.errorText == nil)
        #expect(!store.isProcessing)
    }

    @Test func refreshRecoversAfterSnapshotError() async throws {
        let temp = try testDirectory()
        defer { try? FileManager.default.removeItem(at: temp) }
        let suite = try TestDefaults()
        defer { suite.clean() }
        enum SnapshotFailure: Error { case boom }
        final class Flag: @unchecked Sendable { var failNext = false }
        let flag = Flag()
        let store = IndexStore(
            location: VaultLocation(defaults: suite.defaults, documentsURL: temp),
            supportURL: temp.appendingPathComponent("indexes"),
            update: { index, root, rebuild, previous, skip, skipped, previousContent in
                if flag.failNext {
                    flag.failNext = false
                    _ = try rebuild ? index.rebuild(vaultRoot: root) : index.refresh(vaultRoot: root)
                    throw SnapshotFailure.boom
                }
                return try await IndexUpdate.read(
                    index: index, root: root, rebuild: rebuild, previousTypes: previous,
                    skipUnchanged: skip, previousSkipped: skipped, previousContent: previousContent)
            })
        await store.start()
        let root = try #require(store.vaultURL)
        try Data("- [ ] Recovered task\n".utf8).write(to: root.appendingPathComponent("notes/recover.md"))
        flag.failNext = true
        await store.refresh()
        #expect(store.errorText != nil)
        #expect(store.counts.tasks == 0)

        await store.refresh()
        #expect(store.errorText == nil)
        #expect(store.counts.tasks == 1)
        #expect(!store.isProcessing)
    }

    @Test func rebuildClearsContentWhenVaultEmptied() async throws {
        let temp = try testDirectory()
        defer { try? FileManager.default.removeItem(at: temp) }
        let suite = try TestDefaults()
        defer { suite.clean() }
        let store = IndexStore(
            location: VaultLocation(defaults: suite.defaults, documentsURL: temp),
            supportURL: temp.appendingPathComponent("indexes"))
        await store.start()
        let root = try #require(store.vaultURL)
        try Data("- [ ] Seed task\n".utf8).write(to: root.appendingPathComponent("notes/seed.md"))
        await store.refresh()
        #expect(store.counts.tasks == 1)

        let enumerator = FileManager.default.enumerator(at: root, includingPropertiesForKeys: nil)
        while let url = enumerator?.nextObject() as? URL {
            if url.pathExtension == "md" { try FileManager.default.removeItem(at: url) }
        }
        await store.refresh(rebuild: true)
        #expect(store.counts.tasks == 0)
        #expect(store.counts.files == 0)
        #expect(store.content.tasks.isEmpty)
        #expect(store.errorText == nil)
        #expect(!store.isProcessing)
    }

    @Test func skippedPathChangePublishes() async throws {
        let temp = try testDirectory()
        defer { try? FileManager.default.removeItem(at: temp) }
        let suite = try TestDefaults()
        defer { suite.clean() }
        let store = IndexStore(
            location: VaultLocation(defaults: suite.defaults, documentsURL: temp),
            supportURL: temp.appendingPathComponent("indexes"))
        await store.start()
        let root = try #require(store.vaultURL)
        try Data("Body\n".utf8).write(to: root.appendingPathComponent("notes/Su.md"))
        await store.refresh()
        let afterSeed = try #require(store.lastUpdated)
        #expect(store.skippedPaths.isEmpty)

        try FileManager.default.createSymbolicLink(
            at: root.appendingPathComponent("Kitap.md"),
            withDestinationURL: root.appendingPathComponent("notes/Su.md"))
        await store.refresh()
        #expect(store.lastUpdated != afterSeed)
        #expect(store.skippedPaths.contains { $0.path == "Kitap.md" && $0.reason == .symbolicLink })
        #expect(!store.isProcessing)
    }
}
