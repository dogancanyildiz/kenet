import Foundation
import Testing

@testable import Journal

@MainActor
struct NotificationServiceTests {
    private func service(_ center: FakeNotificationCenter, defaults: TestDefaults, debounce: Duration = .seconds(2))
        -> NotificationService
    {
        NotificationService(
            center: center, defaults: defaults.defaults, now: { notificationDate() }, timeZone: { notificationUTC },
            debounce: debounce)
    }

    @Test func replanRemovesOldOwnedIdentifiersBeforeAddingAndPreservesForeignRequests() async throws {
        let defaults = try TestDefaults()
        defer { defaults.clean() }
        let center = FakeNotificationCenter()
        let old = NotificationRequest(
            id: "task-2026-09-01", date: notificationDate("2026-09-01"), title: "old", body: "", destination: .tasks)
        let foreign = NotificationRequest(
            id: "other-feature", date: notificationDate(), title: "foreign", body: "", destination: .journal)
        center.values = [old.id: old, foreign.id: foreign]
        let service = service(center, defaults: defaults)
        service.update(snapshot: .empty, vaultID: "sample")
        await service.replanNow()
        #expect(center.operations.first == "remove")
        #expect(center.removals.first?.contains(old.id) == true)
        #expect(center.removals.first?.contains(foreign.id) == false)
        #expect(center.values[foreign.id] == foreign)
        #expect(service.pending.count == 7)
        #expect(!service.pending.contains { $0.id == old.id })
        let ids = Set(service.pending.map(\.id))
        await service.replanNow()
        #expect(Set(service.pending.map(\.id)) == ids)
        #expect(center.values.count == 8)
        #expect(center.permissionRequests == 0)
    }

    @Test func onlyAllowedAuthorizationSchedulesAndNeverPromptsOnReplan() async throws {
        let defaults = try TestDefaults()
        defer { defaults.clean() }
        for status in NotificationAuthorization.allCases {
            let center = FakeNotificationCenter()
            center.status = status
            let service = service(center, defaults: defaults)
            service.update(snapshot: .empty, vaultID: "sample")
            await service.replanNow()
            #expect(service.authorization == status)
            #expect(service.pending.count == (status.canSchedule ? 7 : 0))
            #expect(center.permissionRequests == 0)
        }
    }

    @Test func explicitPermissionActionGrantsOrDeniesAndErrorsAreVisible() async throws {
        let defaults = try TestDefaults()
        defer { defaults.clean() }
        let center = FakeNotificationCenter()
        center.status = .notDetermined
        let service = service(center, defaults: defaults)
        service.update(snapshot: .empty, vaultID: "sample")
        await service.replanNow()
        #expect(center.permissionRequests == 0)
        center.failPermission = true
        await service.requestAccess()
        #expect(service.errorText != nil && !service.isRequesting)
        center.failPermission = false
        center.permissionResult = .denied
        await service.requestAccess()
        #expect(service.authorization == .denied && service.pending.isEmpty)
        let count = center.permissionRequests
        await service.requestAccess()
        #expect(center.permissionRequests == count)
        center.status = .notDetermined
        await service.replanNow()
        center.permissionResult = .authorized
        await service.requestAccess()
        #expect(service.authorization == .authorized && service.pending.count == 7)
    }

    @Test func foregroundRevocationClearsPendingWithoutAskingAgain() async throws {
        let defaults = try TestDefaults()
        defer { defaults.clean() }
        let center = FakeNotificationCenter()
        let service = service(center, defaults: defaults)
        service.update(snapshot: .empty, vaultID: "sample")
        await service.replanNow()
        center.status = .denied
        await service.foreground()
        #expect(service.pending.isEmpty && center.values.isEmpty)
        #expect(center.permissionRequests == 0)
    }

    @Test func inFlightOldPlanIsRemovedWhenSettingsDisableIt() async throws {
        let defaults = try TestDefaults()
        defer { defaults.clean() }
        let center = FakeNotificationCenter()
        center.pauseNextAdd = true
        let service = service(center, defaults: defaults)
        service.update(snapshot: .empty, vaultID: "sample")
        let planning = Task { await service.replanNow() }
        for _ in 0..<100 {
            if center.pausedAdd != nil { break }
            await Task.yield()
        }
        let continuation = try #require(center.pausedAdd)
        service.preferences.journalEnabled = false
        continuation.resume()
        await planning.value
        #expect(service.pending.isEmpty && center.values.isEmpty)
        #expect(center.maxConcurrentAdds == 1)
        #expect(center.removals.count == 2)
    }

    @Test func vaultSwitchAndMissingSnapshotRemovePreviousVaultPlan() async throws {
        let defaults = try TestDefaults()
        defer { defaults.clean() }
        let center = FakeNotificationCenter()
        let service = service(center, defaults: defaults)
        service.update(snapshot: try notificationSample(), vaultID: "first")
        await service.replanNow()
        #expect(!service.pending.isEmpty)
        service.update(snapshot: nil, vaultID: "second")
        await service.replanNow()
        #expect(service.pending.isEmpty)
        service.update(snapshot: .empty, vaultID: "second")
        await service.replanNow()
        #expect(service.pending.allSatisfy { $0.destination == .journal })
    }

    @Test func partialAddFailureIsVisibleAndRescheduleRecovers() async throws {
        let defaults = try TestDefaults()
        defer { defaults.clean() }
        let center = FakeNotificationCenter()
        center.failIDs = ["journal-2026-09-27"]
        let service = service(center, defaults: defaults)
        service.update(snapshot: .empty, vaultID: "sample")
        await service.replanNow()
        #expect(service.errorText != nil && service.pending.count == 6)
        center.failIDs = []
        await service.replanNow()
        #expect(service.errorText == nil && service.pending.count == 7)
    }

    @Test func testHostAutomaticActivationDoesNotTouchCenter() async throws {
        let defaults = try TestDefaults()
        defer { defaults.clean() }
        let center = FakeNotificationCenter()
        let service = service(center, defaults: defaults)
        service.update(snapshot: .empty, vaultID: "sample")
        service.activateAutomatically(environment: ["JOURNAL_NO_AUTOSTART": "1"], arguments: [])
        service.activateAutomatically(environment: [:], arguments: ["JOURNAL_NO_AUTOSTART"])
        service.activateAutomatically(environment: ["XCTestConfigurationFilePath": "test"], arguments: [])
        await Task.yield()
        #expect(
            center.activationCount == 0 && center.authorizationReads == 0 && center.permissionRequests == 0
                && center.additions.isEmpty)
    }

    @Test func responseEmitsFreshNavigationRequestForEveryTap() async throws {
        let defaults = try TestDefaults()
        defer { defaults.clean() }
        let center = FakeNotificationCenter()
        let service = service(center, defaults: defaults)
        service.activateAutomatically(environment: [:], arguments: [])
        await service.replanNow()
        center.response?(.journal)
        let first = try #require(service.navigationRequest)
        center.response?(.journal)
        #expect(service.navigationRequest?.id != first.id && service.navigationRequest?.destination == .journal)
        center.response?(.tasks)
        #expect(service.navigationRequest?.destination == .tasks)
        #expect(NotificationDestination.from(identifier: "goals-2026-09-27") == .goals)
        #expect(NotificationDestination.from(identifier: "task-2026-09-27") == .tasks)
        #expect(NotificationDestination.from(identifier: "journal-2026-09-27") == .journal)
        #expect(NotificationDestination.from(identifier: "task-2026-13-01") == nil)
        #expect(NotificationDestination.from(identifier: "task-other") == nil)
    }

    @Test func enablingHideContentRemovesDeliveredNotifications() async throws {
        let defaults = try TestDefaults()
        defer { defaults.clean() }
        let center = FakeNotificationCenter()
        let service = service(center, defaults: defaults, debounce: .zero)
        #expect(center.deliveredRemovals == 0)
        service.preferences.hideContent = true
        for _ in 0..<50 where center.deliveredRemovals == 0 { await Task.yield() }
        #expect(center.deliveredRemovals == 1)
        #expect(center.operations.contains("removeDelivered"))
        service.preferences.hideContent = true
        await Task.yield()
        #expect(center.deliveredRemovals == 1)
        service.preferences.hideContent = false
        service.preferences.hideContent = true
        for _ in 0..<50 where center.deliveredRemovals < 2 { await Task.yield() }
        #expect(center.deliveredRemovals == 2)
    }
}
