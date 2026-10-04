import Foundation
import Testing

@testable import Journal

@MainActor struct AppLockTests {
    @Test func disabledNeverCoversOrAuthenticates() async {
        let fixture = LockFixture()
        defer { fixture.clean() }
        let lock = fixture.lock()
        #expect(!lock.shouldCover)
        lock.resignActive(startTimeout: true)
        #expect(!lock.shouldCover)
        await lock.becomeActive()
        #expect(!lock.shouldCover)
        #expect(fixture.context.calls == 0)
    }

    @Test func enablingRequiresAuthenticationAndPersistsOnlySuccess() async {
        let fixture = LockFixture()
        defer { fixture.clean() }
        let lock = fixture.lock()
        await lock.becomeActive()
        await lock.setEnabled(true)
        #expect(fixture.context.calls == 1)
        #expect(lock.isEnabled && !lock.isLocked && !lock.shouldCover)
        #expect(fixture.defaults.bool(forKey: AppLockService.enabledKey))
        await lock.setEnabled(true)
        #expect(fixture.context.calls == 1)
    }

    @Test func failedEnableRemainsDisabledAndCanRetry() async {
        let fixture = LockFixture()
        defer { fixture.clean() }
        fixture.context.result = false
        let lock = fixture.lock()
        await lock.becomeActive()
        await lock.setEnabled(true)
        #expect(!lock.isEnabled && !lock.shouldCover && lock.authenticationFailed)
        #expect(!fixture.defaults.bool(forKey: AppLockService.enabledKey))
        fixture.context.result = true
        await lock.setEnabled(true)
        #expect(lock.isEnabled && !lock.authenticationFailed)
    }

    @Test func coldLaunchIsCoveredBeforeFirstAuthentication() async {
        let fixture = LockFixture(enabled: true)
        defer { fixture.clean() }
        let lock = fixture.lock()
        #expect(lock.isLocked && lock.shouldCover)
        await lock.becomeActive()
        #expect(fixture.context.calls == 1)
        #expect(!lock.isLocked && !lock.shouldCover)
    }

    @Test func allDelayBoundariesRequireAuthenticationAtDeadline() async {
        for delay in AppLockDelay.allCases {
            let fixture = LockFixture(enabled: true)
            defer { fixture.clean() }
            let lock = fixture.lock()
            lock.delay = delay
            await lock.becomeActive()
            lock.resignActive(startTimeout: true)
            #expect(lock.shouldCover)
            fixture.time = fixture.time.addingTimeInterval(Double(delay.rawValue))
            await lock.becomeActive()
            #expect(fixture.context.calls == 2)
            #expect(!lock.isLocked && !lock.shouldCover)
        }
    }

    @Test func gracePeriodStillCoversBackgroundAndReturnsWithoutPrompt() async {
        for delay in [AppLockDelay.oneMinute, .fiveMinutes, .fifteenMinutes] {
            let fixture = LockFixture(enabled: true)
            defer { fixture.clean() }
            let lock = fixture.lock()
            lock.delay = delay
            await lock.becomeActive()
            lock.resignActive(startTimeout: true)
            fixture.time = fixture.time.addingTimeInterval(Double(delay.rawValue) - 1)
            #expect(lock.shouldCover && !lock.isLocked)
            await lock.becomeActive()
            #expect(fixture.context.calls == 1)
            #expect(!lock.shouldCover)
        }
    }

    @Test func inactiveCoversWithoutStartingIOSTimeout() async {
        let fixture = LockFixture(enabled: true)
        defer { fixture.clean() }
        let lock = fixture.lock()
        await lock.becomeActive()
        lock.resignActive(startTimeout: false)
        #expect(lock.shouldCover && !lock.isLocked)
        fixture.time = fixture.time.addingTimeInterval(1000)
        await lock.becomeActive()
        #expect(fixture.context.calls == 1)
        #expect(!lock.shouldCover)
    }

    @Test func duplicateBackgroundDoesNotRestartDeadline() async {
        let fixture = LockFixture(enabled: true)
        defer { fixture.clean() }
        let lock = fixture.lock()
        lock.delay = .oneMinute
        await lock.becomeActive()
        lock.resignActive(startTimeout: true)
        fixture.time = fixture.time.addingTimeInterval(40)
        lock.resignActive(startTimeout: true)
        fixture.time = fixture.time.addingTimeInterval(20)
        await lock.becomeActive()
        #expect(fixture.context.calls == 2)
    }

    @Test func failedUnlockStaysCoveredUntilExplicitRetrySucceeds() async {
        let fixture = LockFixture(enabled: true)
        defer { fixture.clean() }
        fixture.context.result = false
        let lock = fixture.lock()
        await lock.becomeActive()
        #expect(lock.isLocked && lock.shouldCover && lock.authenticationFailed)
        lock.resignActive(startTimeout: false)
        await lock.becomeActive()
        #expect(fixture.context.calls == 1)
        fixture.context.result = true
        #expect(await lock.unlock())
        #expect(!lock.isLocked && !lock.shouldCover && !lock.authenticationFailed)
    }

    @Test func thrownCancellationStaysLocked() async {
        let fixture = LockFixture(enabled: true)
        defer { fixture.clean() }
        fixture.context.throwsError = true
        let lock = fixture.lock()
        await lock.becomeActive()
        #expect(lock.isLocked && lock.authenticationFailed && !lock.isAuthenticating)
        fixture.context.throwsError = false
        #expect(await lock.unlock())
    }

    @Test func settingsRestoreButAuthenticationDoesNotPersist() async {
        let fixture = LockFixture()
        defer { fixture.clean() }
        let lock = fixture.lock()
        lock.delay = .fifteenMinutes
        await lock.setEnabled(true)
        let restored = fixture.lock()
        #expect(restored.isEnabled && restored.isLocked)
        #expect(restored.delay == .fifteenMinutes)
        await lock.setEnabled(false)
        let disabled = fixture.lock()
        #expect(!disabled.isEnabled && !disabled.shouldCover)
        #expect(disabled.delay == .fifteenMinutes)
        #expect(fixture.context.calls == 1)
    }

    @Test func invalidSavedDelayFallsBackToImmediately() {
        let fixture = LockFixture()
        defer { fixture.clean() }
        fixture.defaults.set(123, forKey: AppLockService.delayKey)
        #expect(fixture.lock().delay == .immediately)
    }

    @Test func backgroundInvalidatesInFlightUnlockAndRejectsLateSuccess() async {
        let fixture = LockFixture(enabled: true)
        defer { fixture.clean() }
        fixture.context.paused = true
        let lock = fixture.lock()
        let foreground = Task { await lock.becomeActive() }
        while fixture.context.pending == nil { await Task.yield() }
        lock.resignActive(startTimeout: true)
        #expect(fixture.context.invalidations == 1)
        fixture.context.pending?.resume(returning: true)
        await foreground.value
        #expect(lock.isLocked && lock.shouldCover && !lock.isAuthenticating)
    }

    @Test func backgroundRejectsLateEnableAndDoesNotPersistIt() async {
        let fixture = LockFixture()
        defer { fixture.clean() }
        fixture.context.paused = true
        let lock = fixture.lock()
        await lock.becomeActive()
        let enabling = Task { await lock.setEnabled(true) }
        while fixture.context.pending == nil { await Task.yield() }
        lock.resignActive(startTimeout: true)
        fixture.context.pending?.resume(returning: true)
        await enabling.value
        #expect(!lock.isEnabled)
        #expect(!fixture.defaults.bool(forKey: AppLockService.enabledKey))
    }

    @Test func concurrentAttemptsAreNotDuplicated() async {
        let fixture = LockFixture(enabled: true)
        defer { fixture.clean() }
        fixture.context.paused = true
        let lock = fixture.lock()
        let first = Task { await lock.unlock() }
        while fixture.context.pending == nil { await Task.yield() }
        #expect(!(await lock.unlock()))
        #expect(fixture.context.calls == 1)
        fixture.context.pending?.resume(returning: true)
        #expect(await first.value)
    }

    @Test func quickEntryChecksDeadlineAndLeavesMainWindowCovered() async {
        let fixture = LockFixture(enabled: true)
        defer { fixture.clean() }
        let lock = fixture.lock()
        lock.delay = .oneMinute
        await lock.becomeActive()
        lock.resignActive(startTimeout: true)
        fixture.time = fixture.time.addingTimeInterval(60)
        fixture.context.result = false
        #expect(!(await lock.authorizeQuickEntry()))
        #expect(lock.isLocked && lock.shouldCover)
        fixture.context.result = true
        #expect(await lock.authorizeQuickEntry())
        #expect(!lock.isLocked && lock.shouldCover)
        #expect(!lock.isForeground)
        lock.quickEntryClosed()
        fixture.time = fixture.time.addingTimeInterval(60)
        #expect(await lock.authorizeQuickEntry())
        #expect(fixture.context.calls == 4)
    }

    @Test func backwardsClockRequiresAuthentication() async {
        let fixture = LockFixture(enabled: true)
        defer { fixture.clean() }
        let lock = fixture.lock()
        lock.delay = .fiveMinutes
        await lock.becomeActive()
        lock.resignActive(startTimeout: true)
        fixture.time = fixture.time.addingTimeInterval(-1)
        await lock.becomeActive()
        #expect(fixture.context.calls == 2)
    }

    @Test func synchronousActivationCannotAuthenticateAfterNewBackground() async {
        let fixture = LockFixture(enabled: true)
        defer { fixture.clean() }
        let lock = fixture.lock()
        lock.activate()
        #expect(lock.isForeground && lock.shouldCover)
        lock.resignActive(startTimeout: true)
        await Task.yield()
        #expect(!lock.isForeground && lock.isLocked && lock.shouldCover)
        #expect(fixture.context.calls == 0)
    }

    @Test func authenticationPromptInactivityDoesNotCancelAttempt() async {
        let fixture = LockFixture(enabled: true)
        defer { fixture.clean() }
        fixture.context.paused = true
        let lock = fixture.lock()
        let foreground = Task { await lock.becomeActive() }
        while fixture.context.pending == nil { await Task.yield() }
        lock.resignActive(startTimeout: false)
        #expect(lock.shouldCover && lock.isAuthenticating)
        #expect(fixture.context.invalidations == 0)
        fixture.context.pending?.resume(returning: true)
        await foreground.value
        #expect(!lock.isLocked && lock.shouldCover)
        // The system prompt dismissed; the next active event removes the cover.
        fixture.context.paused = false
        lock.delay = .oneMinute
        await lock.becomeActive()
        #expect(!lock.shouldCover && fixture.context.calls == 1)
    }

    @Test func immediateQuickEntryLocksAgainWhenPanelCloses() async {
        let fixture = LockFixture(enabled: true)
        defer { fixture.clean() }
        let lock = fixture.lock()
        #expect(await lock.authorizeQuickEntry())
        #expect(!lock.isLocked && lock.shouldCover)
        lock.quickEntryClosed()
        #expect(lock.isLocked && lock.shouldCover)
        #expect(await lock.authorizeQuickEntry())
        #expect(fixture.context.calls == 2)
    }

    @Test func coverCallbacksRunSynchronouslyAndCanBeRemoved() async {
        let fixture = LockFixture(enabled: true)
        defer { fixture.clean() }
        let lock = fixture.lock()
        await lock.becomeActive()
        var covered = false
        let id = lock.registerCover { covered = lock.shouldCover }
        lock.resignActive(startTimeout: false)
        #expect(covered)
        lock.unregisterCover(id)
        await lock.becomeActive()
        #expect(covered)
    }
}

@MainActor private final class LockFixture {
    let suite = "AppLockTests.\(UUID().uuidString)"
    let defaults: UserDefaults
    let context = FakeAppLockContext()
    var time = Date(timeIntervalSince1970: 1000)

    init(enabled: Bool = false) {
        defaults = UserDefaults(suiteName: suite)!
        defaults.set(enabled, forKey: AppLockService.enabledKey)
    }

    func lock() -> AppLockService {
        AppLockService(defaults: defaults, makeContext: { self.context }, now: { self.time })
    }

    func clean() { defaults.removePersistentDomain(forName: suite) }
}

@MainActor private final class FakeAppLockContext: AppLockAuthenticating {
    enum Failure: Error { case cancelled }
    var result = true
    var throwsError = false
    var paused = false
    var calls = 0
    var invalidations = 0
    var pending: CheckedContinuation<Bool, Never>?

    func authenticate(reason: String) async throws -> Bool {
        calls += 1
        if throwsError { throw Failure.cancelled }
        if paused { return await withCheckedContinuation { pending = $0 } }
        return result
    }

    func invalidate() { invalidations += 1 }
}
