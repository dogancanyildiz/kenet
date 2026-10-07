import Foundation
import Testing
import VaultFormat
import VaultIndex

@testable import Journal

@MainActor
struct NotificationIntegrationTests {
    @Test func indexPublicationsCancelCompletedGoalsAndWrittenJournalReminders() async throws {
        let context = try TaskTestContext()
        defer { context.clean() }
        let defaults = try TestDefaults()
        defer { defaults.clean() }
        let center = FakeNotificationCenter()
        let today = LocalDay.today()
        let service = NotificationService(
            center: center, defaults: defaults.defaults,
            now: { notificationDate(today.description) }, timeZone: { notificationUTC })
        service.attach(to: context.store)
        await context.start()
        await service.replanNow()
        #expect(service.pending.count == 7)
        try await context.store.createGoal(name: "Day", period: .day, kind: .boolean, target: 1, unit: nil)
        await service.replanNow()
        #expect(service.pending.contains { $0.id == "goals-\(today)" })
        try await context.store.setGoal(on: today, key: "day", value: .boolean(true))
        await service.replanNow()
        #expect(!service.pending.contains { $0.id == "goals-\(today)" })
        #expect(service.pending.contains { $0.id == "journal-\(today)" })
        #expect(await context.store.addEvent(on: today, text: "A moment", time: nil))
        await service.replanNow()
        #expect(!service.pending.contains { $0.id == "journal-\(today)" })
        #expect(center.permissionRequests == 0)
    }

    @Test func futureGoalCorrectionsAreIncludedInSnapshotPlanningWindow() async throws {
        let context = try TaskTestContext(sample: true)
        defer { context.clean() }
        await context.start()
        let future = CalendarDate("2026-09-28")!
        try await context.store.setGoal(on: future, key: "kitap", value: .number(20))
        try await context.store.setGoal(on: future, key: "su", value: .number(8))
        let index = try VaultIndex()
        try index.rebuild(vaultRoot: context.root)
        let snapshot = VaultReadModel(snapshot: try index.snapshot(), today: CalendarDate("2026-09-27")!)
        #expect(snapshot.goalLogs["su"]?.contains { $0.day == future } == true)
        let plan = NotificationPlanner.requests(
            snapshot: snapshot, preferences: NotificationPreferences(), now: notificationDate(),
            timeZone: notificationUTC)
        #expect(!plan.contains { $0.id == "goals-2026-09-28" })
    }

    @Test func successiveUpdatesDebounceIntoOnePlanAndPreferenceChangesReplanImmediately() async throws {
        let defaults = try TestDefaults()
        defer { defaults.clean() }
        let center = FakeNotificationCenter()
        let service = NotificationService(
            center: center, defaults: defaults.defaults,
            now: { notificationDate() }, timeZone: { notificationUTC }, debounce: .milliseconds(20))
        service.activateAutomatically(environment: [:], arguments: [])
        for _ in 0..<5 { service.update(snapshot: .empty, vaultID: "sample") }
        for _ in 0..<100 {
            if service.pending.count == 7 && !service.isPlanning { break }
            try await Task.sleep(for: .milliseconds(5))
        }
        #expect(service.pending.count == 7 && center.removals.count == 1)
        service.preferences.journalEnabled = false
        for _ in 0..<100 {
            if center.values.isEmpty && !service.isPlanning { break }
            try await Task.sleep(for: .milliseconds(5))
        }
        #expect(service.pending.isEmpty && center.removals.count == 2)
        #expect(center.permissionRequests == 0)
        #expect(NotificationPreferences.read(from: defaults.defaults).journalEnabled == false)
    }
}
