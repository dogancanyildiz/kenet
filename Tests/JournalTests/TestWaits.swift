import Foundation
import Testing

@testable import Journal

/// Polls `condition` until it holds or `timeout` passes, and says whether it held. For state that
/// has no event or test hook to await; the ceiling only bounds a failing run, a passing one ends as
/// soon as the condition holds.
@discardableResult
func waitUntil(
    timeout: Duration = .seconds(10), isolation: isolated (any Actor)? = #isolation,
    _ condition: () async throws -> Bool
) async rethrows -> Bool {
    let deadline = ContinuousClock.now.advanced(by: timeout)
    while !(try await condition()) {
        guard ContinuousClock.now < deadline, !Task.isCancelled else { return false }
        // Polling interval, not a wait: the loop ends on the condition.
        try? await Task.sleep(for: .milliseconds(5))
    }
    return true
}

/// Starts `body` in a main-actor task and returns once that task runs it. The caller is on the main
/// actor too, so it resumes only after the body has run up to its first real suspension: a write
/// that has to wait for its turn is already queued in the store when this returns.
@MainActor
func startedTask<T: Sendable>(_ body: @escaping @MainActor () async -> T) async -> Task<T, Never> {
    let signal = StartSignal()
    let task = Task { @MainActor in
        signal.fire()
        return await body()
    }
    await signal.wait()
    return task
}

/// The throwing form of `startedTask`.
@MainActor
func startedTask<T: Sendable>(_ body: @escaping @MainActor () async throws -> T) async -> Task<T, any Error> {
    let signal = StartSignal()
    let task = Task { @MainActor in
        signal.fire()
        return try await body()
    }
    await signal.wait()
    return task
}

@MainActor private final class StartSignal {
    private var fired = false
    private var waiter: CheckedContinuation<Void, Never>?

    func fire() {
        fired = true
        waiter?.resume()
        waiter = nil
    }

    func wait() async {
        guard !fired else { return }
        await withCheckedContinuation { waiter = $0 }
    }
}

/// The clock for "the watcher did nothing" checks: a second `VaultWatcher` on its own empty folder.
/// Its callbacks pass through the same debounce and timer code as the watcher under test, so a
/// check that waits for them stretches with a slow machine instead of running out before a late
/// callback could arrive.
final class WatcherClock: Sendable {
    private let root: URL
    private let ticks: WatcherClockTicks
    private let watcher: VaultWatcher

    init(interval: TimeInterval = 60) throws {
        root = try testDirectory()
        let ticks = WatcherClockTicks()
        self.ticks = ticks
        watcher = VaultWatcher(root: root, interval: interval) { _ in Task { await ticks.increment() } }
    }

    /// Waits `count` debounce periods: each round activates the clock, which reports one debounce
    /// later.
    func waitDebounces(_ count: Int = 2) async {
        for _ in 0..<count {
            let before = await ticks.value
            watcher.setForeground(false)
            watcher.setForeground(true)
            if !(await waitUntil { await ticks.value > before }) {
                Issue.record("The watcher clock did not report a debounced change")
            }
        }
        // Background again: no timer tick of the clock is left to count in a later wait.
        watcher.setForeground(false)
    }

    /// Waits until the clock's foreground timer has reported `count` ticks, each one debounce after
    /// the tick itself.
    func waitTimerTicks(_ count: Int) async {
        let before = await ticks.value
        watcher.setForeground(false)
        watcher.setForeground(true, triggerOnActivation: false)
        if !(await waitUntil { await ticks.value >= before + count }) {
            Issue.record("The watcher clock's timer did not tick")
        }
        watcher.setForeground(false)
    }

    func stop() {
        watcher.stop()
        try? FileManager.default.removeItem(at: root)
    }
}

private actor WatcherClockTicks {
    private(set) var value = 0
    func increment() { value += 1 }
}
