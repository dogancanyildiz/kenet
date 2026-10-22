import Foundation
import Testing

@testable import Journal

actor WatcherDiagnostics {
    private(set) var unwatched: Int?
    private(set) var closed: [Bool] = []
    private(set) var changes = 0
    func recordCoverage(_ count: Int) { unwatched = count }
    func recordClose(_ wasClosed: Bool) { closed.append(wasClosed) }
    func changed() { changes += 1 }
}

@Suite(.serialized)
struct WatcherResourceTests {
    @Test func directoryLimitFallsBackAndStopClosesDescriptors() async throws {
        let root = try testDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        for name in ["a", "b"] {
            try FileManager.default.createDirectory(
                at: root.appendingPathComponent(name), withIntermediateDirectories: true)
        }
        let diagnostics = WatcherDiagnostics()
        let watcher = VaultWatcher(
            root: root, interval: 60, directoryLimit: 2, fileEvents: false,
            onCoverageChange: { count in Task { await diagnostics.recordCoverage(count) } },
            onDescriptorClosed: { descriptor in
                let wasClosed = fcntl(descriptor, F_GETFD) == -1 && errno == EBADF
                Task { await diagnostics.recordClose(wasClosed) }
            }, onChange: { _ in Task { await diagnostics.changed() } })
        defer { watcher.stop() }
        await watcher.waitUntilReady()
        let clock = try WatcherClock()
        defer { clock.stop() }
        try Data("timer only".utf8).write(to: root.appendingPathComponent("b/note.md"))
        await waitUntil { await diagnostics.unwatched != nil }
        await clock.waitDebounces()
        #expect(await diagnostics.unwatched == 1)
        #expect(await diagnostics.changes == 0)
        watcher.setForeground(true)
        await waitUntil { await diagnostics.changes > 0 }
        #expect(await diagnostics.changes == 1)
        watcher.stop()
        await waitUntil { await diagnostics.closed.count == 2 }
        #expect(await diagnostics.closed == [true, true])
        // Keep the watcher alive: closure must follow stop(), not its eventual deinit.
        watcher.setForeground(false)
    }

    @Test func foregroundReturnTriggersBeforeFirstTimerTick() async throws {
        let root = try testDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let diagnostics = WatcherDiagnostics()
        // Directory sources, the Mac too: the event stream needs no foreground scan (`ScanFuseTests`).
        let watcher = VaultWatcher(
            root: root, interval: 60, fileEvents: false, onChange: { _ in Task { await diagnostics.changed() } })
        defer { watcher.stop() }
        await watcher.waitUntilReady()
        let clock = try WatcherClock()
        defer { clock.stop() }
        watcher.setForeground(true, triggerOnActivation: false)
        await clock.waitDebounces()
        #expect(await diagnostics.changes == 0)
        watcher.setForeground(false)
        watcher.setForeground(true)
        await waitUntil { await diagnostics.changes > 0 }
        #expect(await diagnostics.changes == 1)
    }
}
