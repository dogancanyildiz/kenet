import Dispatch
import Foundation

/// What a watcher notification asks the index to look at.
enum VaultChange: Sendable, Equatable {
    /// Rescan the whole vault: the foreground fuse, foreground return, the root directory,
    /// a coverage change, or more directories than `fullScanThreshold`.
    case full
    /// Vault-relative directories whose entries changed; each one is rescanned with its subtree.
    case directories(Set<String>)

    /// Above this many changed directories one whole-vault scan replaces the list.
    static let fullScanThreshold = 200

    /// Joins two requests; `.full` absorbs everything, and too long a list becomes `.full`.
    func merging(_ other: VaultChange, threshold: Int = fullScanThreshold) -> VaultChange {
        guard case .directories(let left) = self, case .directories(let right) = other else { return .full }
        let union = left.union(right)
        return union.count > threshold ? .full : .directories(union)
    }
}

/// Repeating foreground fuse. Tests replace it with a manual clock.
protocol WatcherTicker: Sendable {
    /// Calls `tick` on `queue` every `interval` seconds until the returned closure cancels it.
    func schedule(
        every interval: TimeInterval, on queue: DispatchQueue, _ tick: @escaping @Sendable () -> Void
    ) -> @Sendable () -> Void
}

struct DispatchWatcherTicker: WatcherTicker {
    func schedule(
        every interval: TimeInterval, on queue: DispatchQueue, _ tick: @escaping @Sendable () -> Void
    ) -> @Sendable () -> Void {
        let timer = DispatchSource.makeTimerSource(queue: queue)
        timer.schedule(deadline: .now() + interval, repeating: interval)
        timer.setEventHandler(handler: tick)
        timer.resume()
        return { timer.cancel() }
    }
}

/// All mutable state is confined to queue. Public operations only enqueue work there, so the
/// caller (the main actor) never waits for a directory walk.
///
/// On the Mac one FSEvents stream with file events reports changes, edits written in place
/// included (`FileEventStream`). On iOS, and on the Mac when the stream cannot start, each directory
/// has a Dispatch source, which sees entries added, removed or renamed but not in-place edits.
final class VaultWatcher: @unchecked Sendable {
    /// Events are the main path; this fuse catches in-place edits a directory source cannot see and
    /// directories without a source.
    static let foregroundInterval: TimeInterval = 10

    private let queue = DispatchQueue(label: "journal.vault-watcher")
    private let root: URL
    private let interval: TimeInterval
    private let ticker: any WatcherTicker
    private let callback: @Sendable (VaultChange) -> Void
    private let directoryLimit: Int
    private let fullScanThreshold: Int
    private let coverageChanged: @Sendable (Int) -> Void
    private let descriptorClosed: @Sendable (Int32) -> Void
    private var unwatchedCount: Int?
    /// Every directory the walks found, watched or not, relative to the root ("" is the root).
    /// Relative paths are built from names: Foundation may report `/private/var` as `/var`.
    private var known: Set<String> = []
    private var sources: [String: DispatchSourceFileSystemObject] = [:]
    private var cancelTimer: (@Sendable () -> Void)?
    private var pending: DispatchWorkItem?
    private var pendingChange: VaultChange?
    private var stopped = false
    private var descriptorCount = 0
    #if os(macOS)
        private let prefersFileEvents: Bool
        private var fileEvents: FileEventStream?
    #endif

    /// The first walk, or on the Mac the event stream's start, runs on the watcher queue;
    /// `waitUntilReady()` awaits it. `initialScanWillBegin` is a test seam that runs on that queue
    /// just before. `fileEvents: false` keeps directory sources on the Mac too; iOS ignores it.
    init(
        root: URL, interval: TimeInterval = VaultWatcher.foregroundInterval, directoryLimit: Int = 256,
        fullScanThreshold: Int = VaultChange.fullScanThreshold,
        ticker: any WatcherTicker = DispatchWatcherTicker(),
        initialScanWillBegin: (@Sendable () -> Void)? = nil, fileEvents: Bool = true,
        onCoverageChange: @escaping @Sendable (Int) -> Void = { _ in },
        onDescriptorClosed: @escaping @Sendable (Int32) -> Void = { _ in },
        onChange: @escaping @Sendable (VaultChange) -> Void
    ) {
        self.root = root.resolvingSymlinksInPath()
        self.interval = interval
        self.ticker = ticker
        callback = onChange
        self.directoryLimit = max(1, directoryLimit)
        self.fullScanThreshold = fullScanThreshold
        coverageChanged = onCoverageChange
        descriptorClosed = onDescriptorClosed
        #if os(macOS)
            prefersFileEvents = fileEvents
        #endif
        queue.async { [weak self] in
            initialScanWillBegin?()
            guard let self, !self.stopped else { return }
            #if os(macOS)
                if self.prefersFileEvents, self.startFileEvents() { return }
            #endif
            self.reconcileDirectories()
        }
    }

    deinit {
        pending?.cancel()
        cancelTimer?()
        for source in sources.values { source.cancel() }
        #if os(macOS)
            if let fileEvents { queue.async { fileEvents.invalidate() } }
        #endif
    }

    /// Returns once the first walk has installed its directory sources, or on the Mac once the
    /// event stream has started: every later write is reported.
    func waitUntilReady() async {
        await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
            queue.async { continuation.resume() }
        }
    }

    func setForeground(_ foreground: Bool, triggerOnActivation: Bool = true) {
        queue.async { [self] in
            guard !stopped, foreground != (cancelTimer != nil) else { return }
            cancelTimer?()
            cancelTimer = nil
            if foreground {
                cancelTimer = ticker.schedule(every: interval, on: queue) { [weak self] in self?.trigger(.full) }
                if triggerOnActivation { trigger(.full) }
            }
        }
    }

    /// Work queued before this call finds `stopped` set and does nothing.
    func stop() {
        queue.async { [self] in
            stopped = true
            pending?.cancel()
            pending = nil
            pendingChange = nil
            cancelTimer?()
            cancelTimer = nil
            for source in sources.values { source.cancel() }
            sources.removeAll()
            #if os(macOS)
                fileEvents?.invalidate()
                fileEvents = nil
            #endif
        }
    }

    /// Test seam: holds the watcher queue so directory events wait and then arrive together.
    func testingSuspendEvents() { queue.suspend() }
    func testingResumeEvents() { queue.resume() }

    private func trigger(_ change: VaultChange) {
        guard !stopped else { return }
        pendingChange = pendingChange.map { $0.merging(change, threshold: fullScanThreshold) } ?? change
        pending?.cancel()
        let work = DispatchWorkItem { [weak self] in
            guard let self, !self.stopped, let change = self.pendingChange else { return }
            self.pendingChange = nil
            // The event stream covers the whole tree: no sources to walk for.
            if !self.usesFileEvents {
                switch change {
                case .full: self.reconcileDirectories()
                case .directories(let directories): self.reconcileDirectories(under: directories)
                }
            }
            self.callback(change)
        }
        pending = work
        queue.asyncAfter(deadline: .now() + .milliseconds(300), execute: work)
    }

    private var usesFileEvents: Bool {
        #if os(macOS)
            fileEvents != nil
        #else
            false
        #endif
    }

    /// Walks the whole tree.
    private func reconcileDirectories() {
        known = walk(from: "")
        syncSources()
    }

    /// Walks only the changed directories' subtrees: new subdirectories gain sources, and
    /// directories gone from those subtrees lose theirs.
    private func reconcileDirectories(under bases: Set<String>) {
        var found: Set<String> = []
        for base in bases { found.formUnion(walk(from: base)) }
        known = known.filter { path in
            found.contains(path) || !bases.contains { $0.isEmpty || path == $0 || path.hasPrefix($0 + "/") }
        }
        known.formUnion(found)
        syncSources()
    }

    private func walk(from start: String) -> Set<String> {
        var directories: Set<String> = []
        func visit(_ url: URL, relative: String) {
            guard let values = try? url.resourceValues(forKeys: [.isDirectoryKey, .isSymbolicLinkKey]),
                values.isDirectory == true, values.isSymbolicLink != true
            else { return }
            directories.insert(relative)
            let children =
                (try? FileManager.default.contentsOfDirectory(
                    at: url, includingPropertiesForKeys: [.isDirectoryKey, .isSymbolicLinkKey])) ?? []
            for child in children {
                let name = child.lastPathComponent
                if name.hasPrefix(".") || (relative.isEmpty && (name == "templates" || name == "conflicts")) {
                    continue
                }
                visit(child, relative: relative.isEmpty ? name : relative + "/" + name)
            }
        }
        visit(absoluteURL(start), relative: start)
        return directories
    }

    private func absoluteURL(_ relative: String) -> URL {
        relative.isEmpty ? root : root.appendingPathComponent(relative, isDirectory: true)
    }

    private func syncSources() {
        for path in Array(sources.keys) where !known.contains(path) {
            sources.removeValue(forKey: path)?.cancel()
        }
        // The empty root path sorts first: the root always gets the first descriptor.
        for path in known.sorted() where sources[path] == nil {
            guard descriptorCount < directoryLimit else { break }
            let descriptor = open(absoluteURL(path).path, O_EVTONLY)
            guard descriptor >= 0 else { continue }
            descriptorCount += 1
            let source = DispatchSource.makeFileSystemObjectSource(
                fileDescriptor: descriptor, eventMask: [.write, .delete, .rename, .extend, .attrib], queue: queue)
            // The root holds the vault's top level: a change there rescans everything.
            let change: VaultChange = path.isEmpty ? .full : .directories([path])
            source.setEventHandler { [weak self] in
                if let source = self?.sources[path], !source.data.intersection([.delete, .rename]).isEmpty {
                    self?.sources.removeValue(forKey: path)?.cancel()
                }
                self?.trigger(change)
            }
            let didClose = descriptorClosed
            source.setCancelHandler { [weak self] in
                close(descriptor)
                didClose(descriptor)
                guard let self else { return }
                self.descriptorCount -= 1
                // Retiring descriptors count against the limit until actually closed.
                if (self.unwatchedCount ?? 0) > 0 { self.trigger(.full) }
            }
            sources[path] = source
            source.resume()
        }
        let count = known.count - sources.count
        if unwatchedCount != count {
            unwatchedCount = count
            coverageChanged(count)
        }
    }
}

#if os(macOS)
    // MARK: FSEvents

    extension VaultWatcher {
        /// Test seam: hands a batch to the watcher as the event stream would.
        func testingDeliverFileEvents(_ events: [FileEventStream.Event]) {
            queue.async { [self] in receiveFileEvents(events) }
        }

        /// Test seam: the running event stream, read on the watcher queue.
        func testingFileEventStream() async -> FileEventStream? {
            await withCheckedContinuation { continuation in
                queue.async { [self] in continuation.resume(returning: fileEvents) }
            }
        }

        /// Starts the stream; false leaves the directory sources to do the work.
        fileprivate func startFileEvents() -> Bool {
            fileEvents = FileEventStream(root: root, queue: queue) { [weak self] events in
                self?.receiveFileEvents(events)
            }
            guard fileEvents != nil else { return false }
            // One stream covers every directory: nothing is left to the fuse alone.
            unwatchedCount = 0
            coverageChanged(0)
            return true
        }

        private func receiveFileEvents(_ events: [FileEventStream.Event]) {
            guard !stopped, let rootComponents = fileEvents?.rootComponents,
                let change = FileEventStream.change(
                    for: events, rootComponents: rootComponents, threshold: fullScanThreshold)
            else { return }
            trigger(change)
        }
    }
#endif
