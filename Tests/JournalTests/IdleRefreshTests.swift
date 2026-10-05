import Foundation
import Testing

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
}
