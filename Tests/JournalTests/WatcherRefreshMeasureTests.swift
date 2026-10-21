import Foundation
import Testing
import VaultIndex

@testable import Journal

/// Optional scale measurement. Enable with MEASURE_READ_MODEL=1 (skipped in default CI).
@MainActor
struct WatcherRefreshMeasureTests {
    @Test(.enabled(if: ProcessInfo.processInfo.environment["MEASURE_READ_MODEL"] == "1"))
    func fiveYearOpeningStallAndSingleFileRefresh() async throws {
        let temp = try testDirectory()
        defer { try? FileManager.default.removeItem(at: temp) }
        let root = temp.appendingPathComponent("Vault", isDirectory: true)
        _ = try SyntheticVault.generate(at: root, configuration: .fiveYears)
        let suite = try TestDefaults()
        defer { suite.clean() }

        var initMs: [Double] = []
        var readyMs: [Double] = []
        for _ in 0..<5 {
            let start = DispatchTime.now()
            let watcher = VaultWatcher(root: root, onChange: { _ in })
            initMs.append(milliseconds(since: start))
            await watcher.waitUntilReady()
            readyMs.append(milliseconds(since: start))
            watcher.stop()
        }

        let store = IndexStore(
            location: VaultLocation(defaults: suite.defaults, documentsURL: temp),
            supportURL: temp.appendingPathComponent("indexes"))
        let beat = MainHeartbeat()
        let ticking = Task { @MainActor in await beat.run() }
        let openStart = DispatchTime.now()
        await store.start()
        let openMs = milliseconds(since: openStart)
        beat.running = false
        await ticking.value
        #expect(store.lastUpdated != nil)

        let note = root.appendingPathComponent("notes/Not 0001.md")
        var refreshMs: [Double] = []
        for round in 0..<5 {
            let handle = try FileHandle(forWritingTo: note)
            try handle.seekToEnd()
            try handle.write(contentsOf: Data("\n- [ ] Measure \(round)\n".utf8))
            try handle.close()
            let start = DispatchTime.now()
            await store.refresh()
            refreshMs.append(milliseconds(since: start))
        }
        var directoryMs: [Double] = []
        for round in 0..<5 {
            let handle = try FileHandle(forWritingTo: note)
            try handle.seekToEnd()
            try handle.write(contentsOf: Data("\n- [ ] Directory \(round)\n".utf8))
            try handle.close()
            let start = DispatchTime.now()
            await store.refresh(directories: ["notes"])
            directoryMs.append(milliseconds(since: start))
        }
        // A new file, from the write to the task count: debounce, event and directory refresh.
        var eventMs: [Double] = []
        for round in 0..<5 {
            let before = store.counts.tasks
            let start = DispatchTime.now()
            try Data("- [ ] Event \(round)\n".utf8).write(to: root.appendingPathComponent("notes/Event \(round).md"))
            for _ in 0..<300 {
                if store.counts.tasks > before { break }
                try await Task.sleep(for: .milliseconds(2))
            }
            eventMs.append(milliseconds(since: start))
            #expect(store.counts.tasks > before)
        }

        let index = try VaultIndex()
        try index.rebuild(vaultRoot: root)
        var coreFull: [Double] = []
        var coreNotes: [Double] = []
        var coreJournal: [Double] = []
        let day = root.appendingPathComponent("journal/2026-10-05.md")
        for round in 0..<5 {
            for file in [note, day] {
                let handle = try FileHandle(forWritingTo: file)
                try handle.seekToEnd()
                try handle.write(contentsOf: Data("\n- [ ] Core \(round)\n".utf8))
                try handle.close()
            }
            var start = DispatchTime.now()
            try index.refresh(vaultRoot: root)
            coreFull.append(milliseconds(since: start))
            for file in [note, day] {
                let handle = try FileHandle(forWritingTo: file)
                try handle.seekToEnd()
                try handle.write(contentsOf: Data("\n- [ ] Scoped \(round)\n".utf8))
                try handle.close()
            }
            start = DispatchTime.now()
            try index.update(paths: ["notes"], vaultRoot: root)
            coreNotes.append(milliseconds(since: start))
            start = DispatchTime.now()
            try index.update(paths: ["journal"], vaultRoot: root)
            coreJournal.append(milliseconds(since: start))
        }
        print(
            """
            MEASURE_READ_MODEL watcher fiveYears:
              watcher init on main median: \(format(median(initMs))) ms (first walk done: \(format(median(readyMs))) ms)
              open: \(format(openMs)) ms, longest main-actor stall: \(format(beat.longestGap)) ms
              store refresh after one note edit median: \(format(median(refreshMs))) ms
              store directory refresh (notes/) after one note edit median: \(format(median(directoryMs))) ms
              new note file to task count median: \(format(median(eventMs))) ms
              core refresh (whole vault) median: \(format(median(coreFull))) ms
              core update notes/ median: \(format(median(coreNotes))) ms
              core update journal/ median: \(format(median(coreJournal))) ms
            """)
    }

    /// In-place edit to task count, foreground: directory sources wait for the 10 s fuse, the Mac's
    /// event stream reports the edit itself. Also the opening's longest main-actor stall for each.
    @Test(.enabled(if: ProcessInfo.processInfo.environment["MEASURE_READ_MODEL"] == "1"))
    func fiveYearInPlaceEditReachesTheIndex() async throws {
        let temp = try testDirectory()
        defer { try? FileManager.default.removeItem(at: temp) }
        let root = temp.appendingPathComponent("Vault", isDirectory: true)
        _ = try SyntheticVault.generate(at: root, configuration: .fiveYears)
        let note = root.appendingPathComponent("notes/Not 0001.md")
        var lines: [String] = []
        for (label, fileEvents, rounds) in [("file events", true, 5), ("directory sources", false, 3)] {
            let suite = try TestDefaults()
            defer { suite.clean() }
            let store = IndexStore(
                location: VaultLocation(defaults: suite.defaults, documentsURL: temp),
                supportURL: temp.appendingPathComponent("indexes-\(fileEvents)"), watcherFileEvents: fileEvents)
            store.setForeground(true)
            defer { store.setForeground(false) }
            let beat = MainHeartbeat()
            let ticking = Task { @MainActor in await beat.run() }
            let openStart = DispatchTime.now()
            await store.start()
            let openMs = milliseconds(since: openStart)
            beat.running = false
            await ticking.value
            var editMs: [Double] = []
            for round in 0..<rounds {
                await store.waitWhileRefreshInFlight()
                let before = store.counts.tasks
                let start = DispatchTime.now()
                let handle = try FileHandle(forWritingTo: note)
                try handle.seekToEnd()
                try handle.write(contentsOf: Data("\n- [ ] In place \(fileEvents) \(round)\n".utf8))
                try handle.close()
                #expect(await waitUntil(timeout: .seconds(15)) { store.counts.tasks > before })
                editMs.append(milliseconds(since: start))
            }
            lines.append(
                "  \(label): open \(format(openMs)) ms, longest main-actor stall \(format(beat.longestGap)) ms, "
                    + "in-place edit to task count median \(format(median(editMs))) ms, rounds \(editMs.map(format).joined(separator: " / ")) ms"
            )
        }
        print("MEASURE_READ_MODEL watcher in-place fiveYears:\n" + lines.joined(separator: "\n"))
    }
}

@MainActor
private final class MainHeartbeat {
    var running = true
    private(set) var longestGap = 0.0

    func run() async {
        var last = DispatchTime.now()
        while running {
            try? await Task.sleep(for: .milliseconds(1))
            let now = DispatchTime.now()
            longestGap = max(longestGap, Double(now.uptimeNanoseconds - last.uptimeNanoseconds) / 1_000_000)
            last = now
        }
    }
}

private func milliseconds(since start: DispatchTime) -> Double {
    Double(DispatchTime.now().uptimeNanoseconds - start.uptimeNanoseconds) / 1_000_000
}

private func median(_ values: [Double]) -> Double { values.sorted()[values.count / 2] }

private func format(_ value: Double) -> String { String(format: "%.1f", value) }
