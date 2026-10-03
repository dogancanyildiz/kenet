import Dispatch
import Foundation

/// All mutable state is confined to queue; public operations synchronize with it.
final class VaultWatcher: @unchecked Sendable {
    private let queue = DispatchQueue(label: "journal.vault-watcher")
    private let root: URL
    private let interval: TimeInterval
    private let callback: @Sendable () -> Void
    private let directoryLimit: Int
    private let coverageChanged: @Sendable (Int) -> Void
    private let descriptorClosed: @Sendable (Int32) -> Void
    private var unwatchedCount: Int?
    private var sources: [String: DispatchSourceFileSystemObject] = [:]
    private var timer: DispatchSourceTimer?
    private var pending: DispatchWorkItem?
    private var stopped = false
    private var descriptorCount = 0

    init(
        root: URL, interval: TimeInterval = 5, directoryLimit: Int = 256,
        onCoverageChange: @escaping @Sendable (Int) -> Void = { _ in },
        onDescriptorClosed: @escaping @Sendable (Int32) -> Void = { _ in },
        onChange: @escaping @Sendable () -> Void
    ) {
        self.root = root.resolvingSymlinksInPath()
        self.interval = interval
        callback = onChange
        self.directoryLimit = max(1, directoryLimit)
        coverageChanged = onCoverageChange
        descriptorClosed = onDescriptorClosed
        queue.sync { reconcileDirectories() }
    }

    deinit {
        pending?.cancel()
        timer?.cancel()
        for source in sources.values { source.cancel() }
    }

    func setForeground(_ foreground: Bool, triggerOnActivation: Bool = true) {
        queue.sync {
            guard !stopped, foreground != (timer != nil) else { return }
            timer?.cancel()
            timer = nil
            if foreground {
                let timer = DispatchSource.makeTimerSource(queue: queue)
                timer.schedule(deadline: .now() + interval, repeating: interval)
                timer.setEventHandler { [weak self] in self?.trigger() }
                self.timer = timer
                timer.resume()
                if triggerOnActivation { trigger() }
            }
        }
    }

    func stop() {
        queue.sync {
            stopped = true
            pending?.cancel()
            pending = nil
            timer?.cancel()
            timer = nil
            for source in sources.values { source.cancel() }
            sources.removeAll()
        }
    }

    private func trigger() {
        guard !stopped else { return }
        pending?.cancel()
        let work = DispatchWorkItem { [weak self] in
            guard let self, !self.stopped else { return }
            self.reconcileDirectories()
            self.callback()
        }
        pending = work
        queue.asyncAfter(deadline: .now() + .milliseconds(300), execute: work)
    }

    private func reconcileDirectories() {
        var directories: Set<String> = []
        func visit(_ url: URL, isRoot: Bool) {
            guard let values = try? url.resourceValues(forKeys: [.isDirectoryKey, .isSymbolicLinkKey]),
                values.isDirectory == true, values.isSymbolicLink != true
            else { return }
            directories.insert(url.path)
            let children =
                (try? FileManager.default.contentsOfDirectory(
                    at: url, includingPropertiesForKeys: [.isDirectoryKey, .isSymbolicLinkKey])) ?? []
            for child in children {
                let name = child.lastPathComponent
                if name.hasPrefix(".") || (isRoot && (name == "templates" || name == "conflicts")) { continue }
                visit(child, isRoot: false)
            }
        }
        visit(root, isRoot: true)
        for path in Array(sources.keys) where !directories.contains(path) {
            sources.removeValue(forKey: path)?.cancel()
        }
        // Always reserve the first descriptor for the root, then use stable path order.
        let ordered = directories.sorted { left, right in
            if left == root.path { return right != root.path }
            if right == root.path { return false }
            return left < right
        }
        for path in ordered where sources[path] == nil {
            guard descriptorCount < directoryLimit else { break }
            let descriptor = open(path, O_EVTONLY)
            guard descriptor >= 0 else { continue }
            descriptorCount += 1
            let source = DispatchSource.makeFileSystemObjectSource(
                fileDescriptor: descriptor, eventMask: [.write, .delete, .rename, .extend, .attrib], queue: queue)
            source.setEventHandler { [weak self] in
                if let source = self?.sources[path], !source.data.intersection([.delete, .rename]).isEmpty {
                    self?.sources.removeValue(forKey: path)?.cancel()
                }
                self?.trigger()
            }
            let didClose = descriptorClosed
            source.setCancelHandler { [weak self] in
                close(descriptor)
                didClose(descriptor)
                guard let self else { return }
                self.descriptorCount -= 1
                // Retiring descriptors count against the limit until actually closed.
                if (self.unwatchedCount ?? 0) > 0 { self.trigger() }
            }
            sources[path] = source
            source.resume()
        }
        let count = directories.count - sources.count
        if unwatchedCount != count {
            unwatchedCount = count
            coverageChanged(count)
        }
    }
}
