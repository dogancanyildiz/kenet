#if os(macOS)
    import CoreServices
    import Foundation
    import Testing

    @testable import Journal

    /// On the Mac one FSEvents stream reports file changes, in-place edits included.
    @Suite(.serialized)
    struct FileEventWatcherTests {
        @Test func inPlaceWritesAndAtomicSavesReportTheirDirectory() async throws {
            let root = try testDirectory()
            defer { try? FileManager.default.removeItem(at: root) }
            let steps = ["append", "truncate", "plain", "touch", "atomic"]
            for name in steps {
                try put("- [ ] Seed\n", at: root.appendingPathComponent("\(name)/note.md"))
            }
            let changes = LockedLog<VaultChange>()
            let watcher = VaultWatcher(root: root, interval: 60) { changes.append($0) }
            defer { watcher.stop() }
            await watcher.waitUntilReady()

            // Each step edits its own directory: a late change from one step cannot pass for the next.
            for name in steps {
                let note = root.appendingPathComponent("\(name)/note.md")
                switch name {
                case "append":
                    let handle = try FileHandle(forWritingTo: note)
                    try handle.seekToEnd()
                    try handle.write(contentsOf: Data("- [ ] Appended\n".utf8))
                    try handle.close()
                case "truncate":
                    let handle = try FileHandle(forWritingTo: note)
                    try handle.truncate(atOffset: 0)
                    try handle.write(contentsOf: Data("- [ ] Rewritten\n".utf8))
                    try handle.close()
                case "plain": try Data("- [ ] Plain\n".utf8).write(to: note)
                case "touch":
                    try FileManager.default.setAttributes(
                        [.modificationDate: Date(timeIntervalSinceNow: 60)], ofItemAtPath: note.path)
                default: try Data("- [ ] Atomic\n".utf8).write(to: note, options: .atomic)
                }
                let reported = await waitUntil { changes.all.contains { $0.names(name) } }
                #expect(reported, "\(name) reached no change")
            }
            #expect(!changes.all.contains(.full))
            let directories = changes.all.reduce(into: Set<String>()) { union, change in
                if case .directories(let names) = change { union.formUnion(names) }
            }
            #expect(directories == Set(steps))
        }

        @Test func directoriesAddedRenamedAndRemovedReportTheirParent() async throws {
            let root = try testDirectory()
            defer { try? FileManager.default.removeItem(at: root) }
            try FileManager.default.createDirectory(
                at: root.appendingPathComponent("a/old"), withIntermediateDirectories: true)
            let changes = LockedLog<VaultChange>()
            let watcher = VaultWatcher(root: root, interval: 60) { changes.append($0) }
            defer { watcher.stop() }
            await watcher.waitUntilReady()

            try FileManager.default.createDirectory(
                at: root.appendingPathComponent("a/new"), withIntermediateDirectories: true)
            try await changes.wait(for: 1)
            try Data("nested".utf8).write(to: root.appendingPathComponent("a/new/deep.md"))
            #expect(await waitUntil { changes.all.contains { $0.names("a/new") } })
            let beforeRename = changes.all.count
            try FileManager.default.moveItem(
                at: root.appendingPathComponent("a/old"), to: root.appendingPathComponent("a/renamed"))
            try await changes.wait(for: beforeRename + 1)
            let beforeRemove = changes.all.count
            try FileManager.default.removeItem(at: root.appendingPathComponent("a/new"))
            // The removed file names `a/new`, which Core reads as missing; the directory names `a`.
            #expect(await waitUntil { changes.all.dropFirst(beforeRemove).contains { $0.names("a") } })

            #expect(changes.all.first == .directories(["a"]))
            #expect(changes.all[beforeRename] == .directories(["a"]))
            #expect(!changes.all.contains(.full))
        }

        @Test func rootEventsAskForAFullScan() async throws {
            let root = try testDirectory()
            defer { try? FileManager.default.removeItem(at: root) }
            try Data("top".utf8).write(to: root.appendingPathComponent("top.md"))
            let changes = LockedLog<VaultChange>()
            let watcher = VaultWatcher(root: root, interval: 60) { changes.append($0) }
            defer { watcher.stop() }
            await watcher.waitUntilReady()

            let handle = try FileHandle(forWritingTo: root.appendingPathComponent("top.md"))
            try handle.seekToEnd()
            try handle.write(contentsOf: Data(" edited".utf8))
            try handle.close()
            try await changes.wait(for: 1)
            try FileManager.default.createDirectory(
                at: root.appendingPathComponent("added"), withIntermediateDirectories: true)
            try await changes.wait(for: 2)
            #expect(changes.all == [.full, .full])
        }

        @Test func excludedDirectoriesStayQuietAndAStoppedStreamReportsNothing() async throws {
            let root = try testDirectory()
            defer { try? FileManager.default.removeItem(at: root) }
            for name in [".obsidian", "templates", "conflicts", "notes/.cache", "notes"] {
                try FileManager.default.createDirectory(
                    at: root.appendingPathComponent(name), withIntermediateDirectories: true)
            }
            try Data("{}".utf8).write(to: root.appendingPathComponent(".obsidian/workspace.json"))
            let changes = LockedLog<VaultChange>()
            let watcher = VaultWatcher(root: root, interval: 60) { changes.append($0) }
            defer { watcher.stop() }
            await watcher.waitUntilReady()

            try Data("{\"open\":1}".utf8).write(to: root.appendingPathComponent(".obsidian/workspace.json"))
            for name in ["templates", "conflicts", "notes/.cache"] {
                try Data("ignored".utf8).write(to: root.appendingPathComponent("\(name)/note.md"))
            }
            // Events arrive in order: an excluded one reported would come before or with this one.
            try Data("- [ ] Seen\n".utf8).write(to: root.appendingPathComponent("notes/seen.md"))
            try await changes.wait(for: 1)
            #expect(changes.all == [.directories(["notes"])])

            watcher.stop()
            try Data("- [ ] Stopped\n".utf8).write(to: root.appendingPathComponent("notes/stopped.md"))
            // Negative check: a live stream would report within two debounces of the clock watcher.
            let clock = try WatcherClock()
            defer { clock.stop() }
            await clock.waitDebounces()
            #expect(changes.all == [.directories(["notes"])])
        }

        @Test func writesJustBeforeTheStartAreNotReported() async throws {
            let root = try testDirectory()
            defer { try? FileManager.default.removeItem(at: root) }
            for name in ["notes", "other"] {
                try FileManager.default.createDirectory(
                    at: root.appendingPathComponent(name), withIntermediateDirectories: true)
            }
            let changes = LockedLog<VaultChange>()
            // FSEvents still delivers a write made just before the stream starts; the seam writes on
            // the watcher queue right before the start. An opening scan after `waitUntilReady` covers it.
            let watcher = VaultWatcher(
                root: root, interval: 60,
                initialScanWillBegin: {
                    // A new directory is the write FSEvents most often delivers late.
                    for number in 0..<3 {
                        try? put("early", at: root.appendingPathComponent("notes/new\(number)/a.md"))
                    }
                }, onChange: { changes.append($0) })
            defer { watcher.stop() }
            await watcher.waitUntilReady()

            // Events arrive in order: a reported early write would come before or with this one.
            try put("- [ ] After\n", at: root.appendingPathComponent("other/after.md"))
            try await changes.wait(for: 1)
            #expect(changes.all == [.directories(["other"])])
        }

        @Test func batchesWithinTheDebounceArriveAsOneChange() async throws {
            let root = try testDirectory()
            defer { try? FileManager.default.removeItem(at: root) }
            let changes = LockedLog<VaultChange>()
            let watcher = VaultWatcher(root: root, interval: 60) { changes.append($0) }
            defer { watcher.stop() }
            await watcher.waitUntilReady()
            let base = try realPath(root)

            // Two separate batches on the held queue reach the debounce back to back.
            watcher.testingSuspendEvents()
            watcher.testingDeliverFileEvents([event(base + "/a/one.md", kFSEventStreamEventFlagItemModified)])
            watcher.testingDeliverFileEvents([event(base + "/b/two.md", kFSEventStreamEventFlagItemModified)])
            watcher.testingResumeEvents()
            try await changes.wait(for: 1)
            watcher.testingDeliverFileEvents([event(base + "/c/three.md", kFSEventStreamEventFlagItemModified)])
            try await changes.wait(for: 2)
            #expect(changes.all == [.directories(["a", "b"]), .directories(["c"])])
        }

        @Test func eventFlagsAndPathsMapToTheDirectoryToRescan() throws {
            let root = "/private/var/vault/Günlük".split(separator: "/")
            func change(_ events: [FileEventStream.Event], threshold: Int = 200) -> VaultChange? {
                FileEventStream.change(for: events, rootComponents: root, threshold: threshold)
            }
            let file = kFSEventStreamEventFlagItemIsFile | kFSEventStreamEventFlagItemModified
            let base = "/private/var/vault/Günlük"
            #expect(change([event(base + "/notes/a.md", file)]) == .directories(["notes"]))
            #expect(change([event(base + "/notes/deep/a.md", file)]) == .directories(["notes/deep"]))
            // The folder name spelled in NFD still matches the NFC root.
            let decomposed = base.decomposedStringWithCanonicalMapping
            #expect(change([event(decomposed + "/notes/a.md", file)]) == .directories(["notes"]))
            // A directory's own attributes name it; adding, removing or renaming it names its parent.
            let directory = kFSEventStreamEventFlagItemIsDir
            #expect(
                change([event(base + "/notes/deep", directory | kFSEventStreamEventFlagItemXattrMod)])
                    == .directories(["notes/deep"]))
            for entry in [
                kFSEventStreamEventFlagItemCreated, kFSEventStreamEventFlagItemRemoved,
                kFSEventStreamEventFlagItemRenamed,
            ] {
                #expect(change([event(base + "/notes/deep", directory | entry)]) == .directories(["notes"]))
            }
            // Exclusions: hidden directories anywhere, `templates/` and `conflicts/` at the root only.
            #expect(change([event(base + "/.obsidian/workspace.json", file)]) == nil)
            #expect(change([event(base + "/notes/.cache/a.md", file)]) == nil)
            #expect(change([event(base + "/templates/person.md", file)]) == nil)
            #expect(change([event(base + "/conflicts/a.md", file)]) == nil)
            #expect(change([event(base + "/notes/templates/a.md", file)]) == .directories(["notes/templates"]))
            // A hidden file outside a hidden directory is read (`.hidden.md`).
            #expect(change([event(base + "/notes/.hidden.md", file)]) == .directories(["notes"]))
            // The root, the root itself, outside the root, lost events and too many directories.
            #expect(change([event(base + "/top.md", file)]) == .full)
            #expect(change([event(base, directory | kFSEventStreamEventFlagItemXattrMod)]) == .full)
            #expect(change([event(base + "/notes", directory | kFSEventStreamEventFlagItemCreated)]) == .full)
            #expect(change([event("/private/var/other/a.md", file)]) == .full)
            #expect(change([event(base + "/notes", kFSEventStreamEventFlagMustScanSubDirs)]) == .full)
            #expect(change([event(base + "/notes/a.md", file | kFSEventStreamEventFlagKernelDropped)]) == .full)
            let three = ["a", "b", "c"].map { event(base + "/\($0)/x.md", file) }
            #expect(change(three, threshold: 3) == .directories(["a", "b", "c"]))
            #expect(change(three, threshold: 2) == .full)
            #expect(
                change([event(base + "/templates/a.md", file), event(base + "/b/x.md", file)]) == .directories(["b"]))
        }
    }

    @MainActor
    struct FileEventRefreshTests {
        @Test func inPlaceEditReachesTheIndexWithoutTheFuse() async throws {
            let temp = try testDirectory()
            defer { try? FileManager.default.removeItem(at: temp) }
            let root = temp.appendingPathComponent("Vault", isDirectory: true)
            try put("- [ ] Seed task\n", at: root.appendingPathComponent("notes/seed.md"))
            let suite = try TestDefaults()
            defer { suite.clean() }
            let scopes = ScopeLog()
            // A manual ticker never ticks: only an event can refresh.
            let store = IndexStore(
                location: VaultLocation(defaults: suite.defaults, documentsURL: temp),
                supportURL: temp.appendingPathComponent("indexes"), watcherTicker: ManualTicker(),
                scopedUpdate: scopes.recordingUpdate())
            await store.start()
            #expect(store.counts.tasks == 1)

            let handle = try FileHandle(forWritingTo: root.appendingPathComponent("notes/seed.md"))
            try handle.seekToEnd()
            try handle.write(contentsOf: Data("- [ ] In place\n".utf8))
            try handle.close()
            await waitUntil { store.counts.tasks == 2 }
            await store.waitWhileRefreshInFlight()
            #expect(store.counts.tasks == 2)
            #expect(await scopes.all == [nil, ["notes"]])
            #expect(store.unwatchedDirectoryCount == 0)
        }
    }

    extension VaultChange {
        fileprivate func names(_ directory: String) -> Bool {
            if case .directories(let names) = self { return names.contains(directory) }
            return false
        }
    }

    private func event(_ path: String, _ flags: Int) -> FileEventStream.Event {
        FileEventStream.Event(path: path, flags: FSEventStreamEventFlags(flags))
    }

    private func realPath(_ url: URL) throws -> String {
        let resolved = try #require(realpath(url.path, nil))
        defer { free(resolved) }
        return String(cString: resolved)
    }

    private func put(_ text: String, at url: URL) throws {
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data(text.utf8).write(to: url)
    }
#endif
