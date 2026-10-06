import Foundation
import GoalTracking
import Testing
import VaultFormat

@testable import Journal

@MainActor @Suite("Geofence goal actions")
struct GeofenceActionTests {
    @Test func notifyThenMarkDoesNotNavigateAndPreservesBytes() async throws {
        let context = try GeofenceTestContext()
        defer { context.clean() }
        await context.start()
        let file = context.vault.root.appendingPathComponent("journal/2026-10-04.md")
        let original =
            "---\ntype: journal\ndate: 2026-10-04\ncustom: untouched\ngoals:\n  water: 2 # retain\n---\n\n## Journal\nKeep this text.\n"
        try Data(original.utf8).write(to: file)
        await context.vault.store.refresh()
        await context.service.enter(try context.target.id)
        #expect(context.center.notices.count == 1)
        #expect(try context.bytes() == Data(original.utf8))
        let action = try #require(context.center.notices.first?.action)
        await context.center.response?(action)
        let saved = String(decoding: try context.bytes(), as: UTF8.self)
        #expect(saved.contains("  spor: true"))
        #expect(saved.contains("  water: 2 # retain"))
        #expect(saved.hasSuffix("## Journal\nKeep this text.\n"))
        let bytes = try context.bytes()
        await context.center.response?(action)
        #expect(try context.bytes() == bytes)
    }

    @Test func automaticMarksAndNotifiesOnceEvenAfterRestart() async throws {
        let context = try GeofenceTestContext()
        defer { context.clean() }
        await context.start()
        let target = try context.target
        context.service.setMode(.automatic, for: target)
        await context.service.enter(target.id)
        await context.service.enter(target.id)
        #expect(context.center.notices.count == 1)
        #expect(context.center.notices.first?.automatic == true)
        #expect(String(decoding: try context.bytes(), as: UTF8.self).contains("  spor: true"))
        // Clearing today's file record does not permit a second arrival action in the same day.
        try await context.vault.store.setGoal(on: CalendarDate("2026-10-04")!, key: "spor", value: nil)
        let restarted = GeofenceService(
            location: context.location, center: context.center,
            defaults: context.vault.defaults.defaults, today: { CalendarDate("2026-10-04")! },
            allowsBackground: { true })
        restarted.attach(to: context.vault.store)
        restarted.activate()
        await restarted.enter(target.id)
        #expect(context.center.notices.count == 1)
        #expect(!String(decoding: try context.bytes(), as: UTF8.self).contains("spor: true"))
    }

    @Test func notifyDailyLimitSkipAndNextDay() async throws {
        let context = try GeofenceTestContext()
        defer { context.clean() }
        await context.start()
        let target = try context.target
        await context.service.enter(target.id)
        await context.service.enter(target.id)
        #expect(context.center.notices.count == 1)
        let first = try #require(context.center.notices.first?.action)
        await context.service.respond(
            to: GeofenceAction(regionID: first.regionID, vaultID: first.vaultID, day: first.day, mark: false))
        #expect(
            !FileManager.default.fileExists(
                atPath: context.vault.root.appendingPathComponent("journal/2026-10-04.md").path))
        let nextDay = GeofenceService(
            location: context.location, center: context.center,
            defaults: context.vault.defaults.defaults, today: { CalendarDate("2026-10-05")! },
            allowsBackground: { true })
        nextDay.attach(to: context.vault.store)
        nextDay.activate()
        await nextDay.enter(target.id)
        #expect(context.center.notices.count == 2)
        await nextDay.respond(to: first)
        #expect(
            !FileManager.default.fileExists(
                atPath: context.vault.root.appendingPathComponent("journal/2026-10-04.md").path))
    }

    @Test func alreadyMarkedAndOffDoNothing() async throws {
        let context = try GeofenceTestContext()
        defer { context.clean() }
        await context.start()
        let target = try context.target
        try await context.vault.store.setGoal(on: CalendarDate("2026-10-04")!, key: "spor", value: .boolean(true))
        let before = try context.bytes()
        await context.service.enter(target.id)
        #expect(context.center.notices.isEmpty)
        #expect(try context.bytes() == before)
        context.service.setMode(.off, for: target)
        try await context.vault.store.setGoal(on: CalendarDate("2026-10-04")!, key: "spor", value: nil)
        await context.service.enter(target.id)
        #expect(context.center.notices.isEmpty)
    }

    @Test func deniedNotificationDoesNotPreventAutomaticMark() async throws {
        let context = try GeofenceTestContext()
        defer { context.clean() }
        await context.start()
        context.center.canNotify = false
        let target = try context.target
        await context.service.enter(target.id)
        #expect(context.center.notices.isEmpty)
        context.service.setMode(.automatic, for: target)
        await context.service.enter(target.id)
        #expect(String(decoding: try context.bytes(), as: UTF8.self).contains("spor: true"))
    }

    @Test func coldBackgroundLaunchOpensBookmarkAndIndexBeforeWrite() async throws {
        let context = try GeofenceTestContext()
        defer { context.clean() }
        await context.start()
        let target = try context.target
        context.service.setMode(.automatic, for: target)
        let cold = IndexStore(
            location: VaultLocation(
                defaults: context.vault.defaults.defaults,
                documentsURL: context.vault.directory, bookmarks: pathBookmarks()),
            supportURL: context.vault.directory.appendingPathComponent("cold-index"))
        let source = FakeRegionSource()
        source.installed = [target.region]
        let service = GeofenceService(
            location: LocationService(source: source, defaults: context.vault.defaults.defaults),
            center: context.center, defaults: context.vault.defaults.defaults, today: { CalendarDate("2026-10-04")! },
            allowsBackground: { true })
        service.attach(to: cold)
        service.activate()
        #expect(source.installed == [target.region])
        await service.enter(target.id)
        #expect(cold.vaultURL?.standardizedFileURL.path == context.vault.root.standardizedFileURL.path)
        #expect(cold.lastUpdated != nil)
        #expect(String(decoding: try context.bytes(), as: UTF8.self).contains("spor: true"))
    }

    @Test func launchPolicyBlocksCallbackWork() async throws {
        let context = try GeofenceTestContext(allowed: false)
        defer { context.clean() }
        await context.start()
        let target = try context.target
        context.service.setMode(.automatic, for: target)
        await context.service.enter(target.id)
        #expect(context.center.notices.isEmpty)
        #expect(
            !FileManager.default.fileExists(
                atPath: context.vault.root.appendingPathComponent("journal/2026-10-04.md").path))
    }

    @Test func staleVaultAndChangedRegionActionsAreIgnored() async throws {
        let context = try GeofenceTestContext()
        defer { context.clean() }
        await context.start()
        let target = try context.target
        await context.service.enter(target.id)
        let action = try #require(context.center.notices.first?.action)
        await context.service.respond(
            to: GeofenceAction(regionID: action.regionID, vaultID: "wrong", day: action.day, mark: true))
        context.service.setMode(.off, for: target)
        await context.service.respond(to: action)
        #expect(
            !FileManager.default.fileExists(
                atPath: context.vault.root.appendingPathComponent("journal/2026-10-04.md").path))
        let other = context.vault.directory.appendingPathComponent("Other")
        try FileManager.default.createDirectory(at: other, withIntermediateDirectories: true)
        await context.vault.store.select(other)
        await context.service.respond(to: action)
        #expect(context.center.notices.count == 1)
        #expect(!FileManager.default.fileExists(atPath: other.appendingPathComponent("journal/2026-10-04.md").path))
    }

    @Test func concurrentEntryAndNotificationRetry() async throws {
        let context = try GeofenceTestContext()
        defer { context.clean() }
        await context.start()
        let identifier = try context.target.id
        context.center.fails = true
        await context.service.enter(identifier)
        #expect(context.service.errorText != nil)
        context.center.fails = false
        context.center.pauseNext = true
        let task = Task { await context.service.enter(identifier) }
        for _ in 0..<100 {
            if context.center.paused != nil { break }
            try await Task.sleep(for: .milliseconds(10))
        }
        #expect(context.center.paused != nil)
        await context.service.enter(identifier)
        #expect(context.center.notices.isEmpty)
        context.center.paused?.resume()
        context.center.paused = nil
        await task.value
        #expect(context.center.notices.count == 1)
        await context.service.enter(identifier)
        #expect(context.center.notices.count == 1)
    }

    @Test func inaccessibleBookmarkNeverFallsBackForBackgroundWrites() async throws {
        let context = try GeofenceTestContext()
        defer { context.clean() }
        await context.start()
        let target = try context.target
        context.service.setMode(.automatic, for: target)
        context.vault.defaults.defaults.set(Data("/nonexistent-geofence-vault".utf8), forKey: "vaultBookmark")
        await context.service.enter(target.id)
        #expect(context.service.errorText != nil)
        #expect(context.center.notices.isEmpty)
        #expect(
            !FileManager.default.fileExists(
                atPath: context.vault.root.appendingPathComponent("journal/2026-10-04.md").path))
    }

    @Test func lockedMarkActionDoesNotWriteAndSurfacesNotice() async throws {
        let context = try GeofenceTestContext()
        defer { context.clean() }
        let locked = GeofenceService(
            location: context.location, center: context.center,
            defaults: context.vault.defaults.defaults, today: { CalendarDate("2026-10-04")! },
            allowsBackground: { true }, isLocked: { true }, isLockEnabled: { true })
        locked.attach(to: context.vault.store)
        var openedGoals = false
        locked.onLockedMarkBlocked = { openedGoals = true }
        locked.activate()
        await context.vault.store.select(context.vault.root)
        let target = try #require(locked.targets.first { $0.goal.key == "spor" })
        await locked.enter(target.id)
        #expect(context.center.notices.count == 1)
        let action = try #require(context.center.notices.first?.action)
        let file = context.vault.root.appendingPathComponent("journal/2026-10-04.md")
        #expect(!FileManager.default.fileExists(atPath: file.path))
        await locked.respond(to: action)
        #expect(!FileManager.default.fileExists(atPath: file.path))
        #expect(openedGoals)
        #expect(
            locked.lockedMarkNotice
                == String(localized: "Günlük kilitliydi. Kilidi açtıktan sonra hedefi kendin işaretle."))
        #expect(locked.errorText == nil)
    }

    @Test func unlockClearsLockedMarkNotice() async throws {
        let context = try GeofenceTestContext()
        defer { context.clean() }
        let fixture = LockFixture(enabled: true)
        defer { fixture.clean() }
        let lock = fixture.lock()
        let service = GeofenceService(
            location: context.location, center: context.center,
            defaults: context.vault.defaults.defaults, today: { CalendarDate("2026-10-04")! },
            allowsBackground: { true })
        service.attach(to: context.vault.store)
        service.attach(lock: lock)
        service.activate()
        await context.vault.store.select(context.vault.root)
        let target = try #require(service.targets.first { $0.goal.key == "spor" })
        await service.enter(target.id)
        let action = try #require(context.center.notices.first?.action)
        await service.respond(to: action)
        #expect(service.lockedMarkNotice != nil)
        await lock.becomeActive()
        #expect(service.lockedMarkNotice == nil)
    }

    @Test func unlockedMarkActionStillWrites() async throws {
        let context = try GeofenceTestContext()
        defer { context.clean() }
        let unlocked = GeofenceService(
            location: context.location, center: context.center,
            defaults: context.vault.defaults.defaults, today: { CalendarDate("2026-10-04")! },
            allowsBackground: { true }, isLocked: { false }, isLockEnabled: { false })
        unlocked.attach(to: context.vault.store)
        unlocked.activate()
        await context.vault.store.select(context.vault.root)
        let target = try #require(unlocked.targets.first { $0.goal.key == "spor" })
        await unlocked.enter(target.id)
        let action = try #require(context.center.notices.first?.action)
        await unlocked.respond(to: action)
        #expect(String(decoding: try context.bytes(), as: UTF8.self).contains("  spor: true"))
    }

    @Test func hideContentPropagatesOnGeofenceNotice() async throws {
        let context = try GeofenceTestContext()
        defer { context.clean() }
        var prefs = NotificationPreferences()
        prefs.hideContent = true
        prefs.persist(in: context.vault.defaults.defaults)
        await context.start()
        await context.service.enter(try context.target.id)
        let notice = try #require(context.center.notices.first)
        #expect(notice.hideContent)
        #expect(
            LocationCopy.geofenceTitle(
                place: notice.placeName, goal: notice.goalName, automatic: false, hideContent: true
            ).contains(notice.goalName) == false)
    }
}
