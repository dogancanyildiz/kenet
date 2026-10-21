#if os(macOS)
    import CoreServices
    import Foundation

    /// One FSEvents stream over the vault root with file-level events (macOS only). Unlike a directory
    /// source it also reports a file written in place, and it holds no file descriptor.
    ///
    /// FSEvents may still deliver a write made a few milliseconds before the stream started. A sentinel
    /// file written just after the start, in a folder outside the vault that the same stream watches,
    /// marks the boundary: events arrive in order, so every vault event ahead of the sentinel's is
    /// dropped. A write made after `init` returns comes after the sentinel's event and is reported.
    final class FileEventStream: @unchecked Sendable {
        struct Event: Sendable {
            let path: String
            let flags: FSEventStreamEventFlags
        }

        /// Batches arriving within this window come in one callback.
        static let latency: TimeInterval = 0.3
        /// Events pass without the sentinel's event after this long; a late pre-start event then
        /// costs one extra refresh, nothing more.
        static let sentinelTimeout: TimeInterval = 2

        /// The vault root as FSEvents reports it (`/private/var`, not `/var`), split into components.
        let rootComponents: [Substring]
        private let handler: ([Event]) -> Void
        private var stream: FSEventStreamRef?
        private let sentinel: URL?
        private let sentinelComponents: [Substring]?
        private var awaitingSentinel = false

        /// Starts the stream on `queue`; `nil` when FSEvents refuses the stream. Call on `queue`;
        /// `handler` runs there. The stream retains this object until `invalidate()`.
        init?(root: URL, queue: DispatchQueue, handler: @escaping ([Event]) -> Void) {
            let rootPath = Self.realPath(root.path)
            rootComponents = rootPath.split(separator: "/")
            self.handler = handler
            let folder = FileManager.default.temporaryDirectory.appendingPathComponent(
                "journal-watch-" + UUID().uuidString, isDirectory: true)
            let sentinelPath = (try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true))
                .map { Self.realPath(folder.path) }
            sentinel = sentinelPath == nil ? nil : folder
            sentinelComponents = sentinelPath?.split(separator: "/")

            var context = FSEventStreamContext(
                version: 0, info: Unmanaged.passUnretained(self).toOpaque(),
                retain: { info in
                    guard let info else { return nil }
                    _ = Unmanaged<FileEventStream>.fromOpaque(info).retain()
                    return info
                },
                release: { info in
                    guard let info else { return }
                    Unmanaged<FileEventStream>.fromOpaque(info).release()
                }, copyDescription: nil)
            let flags = FSEventStreamCreateFlags(
                kFSEventStreamCreateFlagFileEvents | kFSEventStreamCreateFlagUseCFTypes)
            let paths = [rootPath] + (sentinelPath.map { [$0] } ?? [])
            guard
                let created = FSEventStreamCreate(
                    nil, fileEventCallback, &context, paths as CFArray,
                    FSEventStreamEventId(kFSEventStreamEventIdSinceNow), Self.latency, flags)
            else {
                removeSentinel()
                return nil
            }
            FSEventStreamSetDispatchQueue(created, queue)
            guard FSEventStreamStart(created) else {
                FSEventStreamInvalidate(created)
                FSEventStreamRelease(created)
                removeSentinel()
                return nil
            }
            stream = created
            // Without a sentinel every event passes, the latest pre-start write included.
            guard let sentinel, (try? Data().write(to: sentinel.appendingPathComponent("start"))) != nil else { return }
            awaitingSentinel = true
            queue.asyncAfter(deadline: .now() + Self.sentinelTimeout) { [weak self] in self?.endSentinelWait() }
        }

        /// Stops the stream; no handler call follows once this returns on `queue`.
        func invalidate() {
            guard let stream else { return }
            self.stream = nil
            FSEventStreamStop(stream)
            FSEventStreamInvalidate(stream)
            FSEventStreamRelease(stream)
            removeSentinel()
        }

        fileprivate func receive(_ events: [Event]) {
            guard stream != nil else { return }
            var vault: [Event] = []
            for event in events {
                guard let sentinelComponents, Self.components(of: event.path, under: sentinelComponents) != nil else {
                    vault.append(event)
                    continue
                }
                if awaitingSentinel {
                    // Everything ahead of the sentinel's first event predates the start.
                    vault.removeAll()
                    endSentinelWait()
                }
            }
            guard !awaitingSentinel, !vault.isEmpty else { return }
            handler(vault)
        }

        private func endSentinelWait() {
            guard awaitingSentinel else { return }
            awaitingSentinel = false
            removeSentinel()
        }

        private func removeSentinel() {
            if let sentinel { try? FileManager.default.removeItem(at: sentinel) }
        }

        /// The change a batch asks for, `nil` when every event falls in an excluded directory.
        /// A file event names the directory that holds the file; a directory added, removed or renamed
        /// names its parent, as a directory source would. An event in the root, on the root itself,
        /// outside the root or with a lost-events flag asks for the whole vault.
        static func change(
            for events: [Event], rootComponents: [Substring], threshold: Int = VaultChange.fullScanThreshold
        ) -> VaultChange? {
            let rescan = FSEventStreamEventFlags(
                kFSEventStreamEventFlagMustScanSubDirs | kFSEventStreamEventFlagUserDropped
                    | kFSEventStreamEventFlagKernelDropped | kFSEventStreamEventFlagEventIdsWrapped
                    | kFSEventStreamEventFlagRootChanged | kFSEventStreamEventFlagMount
                    | kFSEventStreamEventFlagUnmount)
            let entryChange = FSEventStreamEventFlags(
                kFSEventStreamEventFlagItemCreated | kFSEventStreamEventFlagItemRemoved
                    | kFSEventStreamEventFlagItemRenamed)
            let isDirectory = FSEventStreamEventFlags(kFSEventStreamEventFlagItemIsDir)
            var directories: Set<String> = []
            for event in events {
                guard event.flags & rescan == 0, let relative = components(of: event.path, under: rootComponents),
                    !relative.isEmpty
                else { return .full }
                // A directory whose own attributes changed is itself the directory to rescan.
                let ownAttributes = event.flags & isDirectory != 0 && event.flags & entryChange == 0
                let directory = ownAttributes ? relative : relative.dropLast()
                if directory.contains(where: { $0.hasPrefix(".") }) { continue }
                if let first = directory.first, first == "templates" || first == "conflicts" { continue }
                guard !directory.isEmpty else { return .full }
                directories.insert(directory.joined(separator: "/"))
            }
            if directories.isEmpty { return nil }
            return directories.count > threshold ? .full : .directories(directories)
        }

        /// The components of `path` below `base`, `nil` when `path` is not under it. Components compare
        /// as Swift strings, so an NFC and an NFD spelling of a folder name match; the returned names
        /// keep the event's own spelling, which is the one on disk.
        private static func components(of path: String, under base: [Substring]) -> ArraySlice<Substring>? {
            let parts = path.split(separator: "/")
            guard parts.count >= base.count, zip(parts, base).allSatisfy({ $0 == $1 }) else { return nil }
            return parts.dropFirst(base.count)
        }

        private static func realPath(_ path: String) -> String {
            guard let resolved = realpath(path, nil) else { return path }
            defer { free(resolved) }
            return String(cString: resolved)
        }
    }

    private let fileEventCallback: FSEventStreamCallback = { _, info, count, paths, flags, _ in
        guard let info else { return }
        let stream = Unmanaged<FileEventStream>.fromOpaque(info).takeUnretainedValue()
        let array = unsafeBitCast(paths, to: NSArray.self)
        var events: [FileEventStream.Event] = []
        events.reserveCapacity(count)
        for position in 0..<count {
            guard let path = array[position] as? String else { continue }
            events.append(FileEventStream.Event(path: path, flags: flags[position]))
        }
        stream.receive(events)
    }
#endif
