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

    @Test func replanAddsTheNewPlanBeforeRemovingOldOwnedIdentifiersAndPreservesForeignRequests() async throws {
        let defaults = try TestDefaults()
        defer { defaults.clean() }
        let center = FakeNotificationCenter()
        let old = NotificationRequest(
            id: "task-2026-09-01", date: notificationDate("2026-09-01"), title: "old", body: "", destination: .tasks)
        let foreign = NotificationRequest(
            id: "other-feature", date: notificationDate(), title: "foreign", body: "", destination: .journal)
        center.values = [old.id: old, foreign.id: foreign]
        let service = service(center, defaults: defaults)
        service.update(isOpen: true, vaultID: "sample")
        await service.replanNow()
        #expect(center.operations.last == "remove" && center.removals.count == 1)
        #expect(center.removals.first?.contains(old.id) == true)
        #expect(center.removals.first?.contains(foreign.id) == false)
        #expect(center.removals.first?.contains { id in service.pending.contains { $0.id == id } } == false)
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
            service.update(isOpen: true, vaultID: "sample")
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
        service.update(isOpen: true, vaultID: "sample")
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
        service.update(isOpen: true, vaultID: "sample")
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
        service.update(isOpen: true, vaultID: "sample")
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
        service.update(isOpen: true, vaultID: "first")
        await service.replanNow()
        #expect(!service.pending.isEmpty)
        service.update(isOpen: false, vaultID: "second")
        await service.replanNow()
        #expect(service.pending.isEmpty)
        service.update(isOpen: true, vaultID: "second")
        await service.replanNow()
        #expect(service.pending.allSatisfy { $0.destination == .journal })
    }

    /// The plan left by the last launch, or by the vault before it reopened, stays while the vault loads.
    @Test func aLoadingVaultKeepsTheLastPlanUntilItsFirstPublishReplacesIt() async throws {
        let defaults = try TestDefaults()
        defer { defaults.clean() }
        let center = FakeNotificationCenter()
        let stale = NotificationRequest(
            id: "task-2026-09-01", date: notificationDate("2026-09-01"), title: "old", body: "", destination: .tasks)
        let today = NotificationRequest(
            id: "journal-2026-09-27", date: notificationDate(hour: 21), title: "old", body: "", destination: .journal)
        let foreign = NotificationRequest(
            id: "other-feature", date: notificationDate(), title: "foreign", body: "", destination: .journal)
        let launch = [stale.id: stale, today.id: today, foreign.id: foreign]
        center.values = launch
        let service = service(center, defaults: defaults)
        service.update(isOpen: false, vaultID: "sample")
        await service.replanNow()
        #expect(center.removals.isEmpty && center.additions.isEmpty)
        #expect(center.values == launch)
        #expect(service.pending.map(\.id) == [stale.id, today.id])

        service.update(isOpen: true, vaultID: "sample")
        await service.replanNow()
        #expect(center.values[stale.id] == nil && center.values[foreign.id] == foreign)
        #expect(center.values[today.id] != nil && center.values[today.id] != today)
        #expect(service.pending.count == 7)
        // The new requests are in place before anything is withdrawn.
        #expect(center.operations.last == "remove" && center.operations.filter { $0 == "remove" }.count == 1)

        let planned = center.values
        service.update(isOpen: false, vaultID: "sample")
        await service.replanNow()
        #expect(center.values == planned && center.removals.count == 1)
        #expect(service.pending.count == 7)
    }

    /// Another vault, even one that is still loading, or a lost vault withdraws the plan at once.
    @Test func aVaultSwitchOrLostAccessWithdrawsTheLastPlanAtOnce() async throws {
        let defaults = try TestDefaults()
        defer { defaults.clean() }
        let center = FakeNotificationCenter()
        let foreign = NotificationRequest(
            id: "other-feature", date: notificationDate(), title: "foreign", body: "", destination: .journal)
        center.values = [foreign.id: foreign]
        let service = service(center, defaults: defaults)
        // The first vault is still loading the plan of the last launch when another one opens.
        service.update(isOpen: false, vaultID: "first")
        await service.replanNow()
        center.values["journal-2026-09-27"] = NotificationRequest(
            id: "journal-2026-09-27", date: notificationDate(hour: 21), title: "old", body: "", destination: .journal)
        service.update(isOpen: false, vaultID: "second")
        await service.replanNow()
        #expect(center.values == [foreign.id: foreign] && service.pending.isEmpty)

        service.update(isOpen: true, vaultID: "second")
        await service.replanNow()
        #expect(service.pending.count == 7)
        service.update(isOpen: false, vaultID: nil)
        await service.replanNow()
        #expect(center.values == [foreign.id: foreign] && service.pending.isEmpty)
    }

    @Test func vaultSwitchRemovesDeliveredNotificationsOnce() async throws {
        let defaults = try TestDefaults()
        defer { defaults.clean() }
        let center = FakeNotificationCenter()
        let service = service(center, defaults: defaults)
        service.update(isOpen: false, vaultID: "first")
        await service.replanNow()
        service.update(isOpen: true, vaultID: "first")
        await service.replanNow()
        // An unreadable vault that reopens as itself is not a switch.
        service.update(isOpen: false, vaultID: nil)
        await service.replanNow()
        service.update(isOpen: true, vaultID: "first")
        await service.replanNow()
        #expect(center.deliveredRemovals == 0)
        service.update(isOpen: false, vaultID: "second")
        await service.replanNow()
        #expect(center.deliveredRemovals == 1)
        service.update(isOpen: true, vaultID: "second")
        await service.replanNow()
        await service.replanNow()
        #expect(center.deliveredRemovals == 1)
        service.update(isOpen: false, vaultID: nil)
        service.update(isOpen: true, vaultID: "first")
        await service.replanNow()
        #expect(center.deliveredRemovals == 2)
    }

    @Test func partialAddFailureIsVisibleAndRescheduleRecovers() async throws {
        let defaults = try TestDefaults()
        defer { defaults.clean() }
        let center = FakeNotificationCenter()
        center.failIDs = ["journal-2026-09-27"]
        let service = service(center, defaults: defaults)
        service.update(isOpen: true, vaultID: "sample")
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
        service.update(isOpen: true, vaultID: "sample")
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
        // Content shown is a stored choice; turning hiding on is the change under test.
        var shown = NotificationPreferences()
        shown.hideContent = false
        shown.persist(in: defaults.defaults)
        let center = FakeNotificationCenter()
        let service = service(center, defaults: defaults, debounce: .zero)
        #expect(!service.preferences.hideContent)
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
