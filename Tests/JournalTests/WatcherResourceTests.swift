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
            root: root, interval: 60, directoryLimit: 2,
            onCoverageChange: { count in Task { await diagnostics.recordCoverage(count) } },
            onDescriptorClosed: { descriptor in
                let wasClosed = fcntl(descriptor, F_GETFD) == -1 && errno == EBADF
                Task { await diagnostics.recordClose(wasClosed) }
            }, onChange: { Task { await diagnostics.changed() } })
        defer { watcher.stop() }
        try Data("timer only".utf8).write(to: root.appendingPathComponent("b/note.md"))
        try await Task.sleep(for: .milliseconds(600))
        #expect(await diagnostics.unwatched == 1)
        #expect(await diagnostics.changes == 0)
        watcher.setForeground(true)
        for _ in 0..<60 {
            if await diagnostics.changes > 0 { break }
            try await Task.sleep(for: .milliseconds(20))
        }
        #expect(await diagnostics.changes == 1)
        watcher.stop()
        for _ in 0..<100 {
            if await diagnostics.closed.count == 2 { break }
            try await Task.sleep(for: .milliseconds(20))
        }
        #expect(await diagnostics.closed == [true, true])
        // Keep the watcher alive: closure must follow stop(), not its eventual deinit.
        watcher.setForeground(false)
    }

    @Test func foregroundReturnTriggersBeforeFirstTimerTick() async throws {
        let root = try testDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let diagnostics = WatcherDiagnostics()
        let watcher = VaultWatcher(root: root, interval: 60, onChange: { Task { await diagnostics.changed() } })
        defer { watcher.stop() }
        watcher.setForeground(true, triggerOnActivation: false)
        try await Task.sleep(for: .milliseconds(400))
        #expect(await diagnostics.changes == 0)
        watcher.setForeground(false)
        watcher.setForeground(true)
        for _ in 0..<60 {
            if await diagnostics.changes > 0 { break }
            try await Task.sleep(for: .milliseconds(20))
        }
        #expect(await diagnostics.changes == 1)
    }
}
