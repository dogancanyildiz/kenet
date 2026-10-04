import CryptoKit
import EntityRecognition
import Foundation
import GoalTracking
import Observation
import VaultFormat
import VaultIndex
import VaultStore

struct IndexCounts: Sendable {
    var filesByKind: [String: Int] = [:]
    var events = 0
    var tasks = 0
    var entities = 0
    var links = 0
    var unresolvedLinks = 0
    var files: Int { filesByKind.values.reduce(0, +) }

    init() {}

    init(snapshot: IndexSnapshot) {
        for file in snapshot.files { filesByKind[file.kind, default: 0] += 1 }
        events = snapshot.blocks.filter { $0.kind == "event" }.count
        tasks = snapshot.blocks.filter { $0.kind == "task" }.count
        entities = snapshot.entities.count
        links = snapshot.links.count
        unresolvedLinks = snapshot.links.filter { $0.resolvedFile == nil }.count
    }
}

@MainActor @Observable
final class IndexStore {
    private(set) var vaultURL: URL?
    private(set) var content = VaultReadModel.empty
    private(set) var knownEntities: [KnownEntity] = []
    private(set) var entityUsage: [EntityUsage] = []
    private(set) var counts = IndexCounts()
    private(set) var skippedPaths: [SkippedPath] = []
    private(set) var lastUpdated: Date?
    private(set) var isProcessing = false
    private(set) var errorText: String?
    private(set) var entryErrorText: String?
    private(set) var isWriting = false
    var canAddEvent: Bool { writer != nil && !isProcessing }
    private(set) var notice: String?
    private(set) var pendingSelection: URL?
    private(set) var unwatchedDirectoryCount = 0
    @ObservationIgnored private let location: VaultLocation
    @ObservationIgnored private let supportURL: URL
    @ObservationIgnored private let update: @Sendable (VaultIndex, URL, Bool) async throws -> IndexUpdate
    @ObservationIgnored private let watcherDirectoryLimit: Int
    @ObservationIgnored private var index: VaultIndex?
    @ObservationIgnored private var writer: VaultStore?
    @ObservationIgnored private var watcher: VaultWatcher?
    @ObservationIgnored private var foreground = false
    @ObservationIgnored private var pendingRefresh = false
    @ObservationIgnored private var pendingRebuild = false
    @ObservationIgnored private var generation = UUID()

    init(
        location: VaultLocation = VaultLocation(), supportURL: URL? = nil,
        watcherDirectoryLimit: Int = 256,
        update: @escaping @Sendable (VaultIndex, URL, Bool) async throws -> IndexUpdate = IndexUpdate.read
    ) {
        self.location = location
        self.update = update
        self.watcherDirectoryLimit = watcherDirectoryLimit
        self.supportURL =
            supportURL
            ?? FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Journal/Indexes", isDirectory: true)
    }

    func startAutomatically(
        environment: [String: String] = ProcessInfo.processInfo.environment,
        arguments: [String] = ProcessInfo.processInfo.arguments
    ) async {
        guard AppLaunchPolicy.allowsAutomaticStart(environment: environment, arguments: arguments) else { return }
        await start()
    }

    func start() async {
        guard vaultURL == nil else { return }
        do {
            let resolved = try location.resolve()
            notice = resolved.notice
            await open(resolved.url)
        } catch { report(error) }
    }

    func select(_ url: URL) async {
        if isProcessing {
            pendingSelection = url
            return
        }
        do {
            let selected = try location.select(url)
            notice = nil
            await open(selected)
        } catch { report(error) }
    }

    func setForeground(_ active: Bool) {
        foreground = active
        watcher?.setForeground(active)
    }

    func report(_ error: Error) {
        errorText = String(localized: "İşlem başarısız: \(error.localizedDescription)")
    }

    func reportTaskEntryError(_ message: String?) { entryErrorText = message }

    /// Returns true once bytes are saved, including a failed index update; callers must not resend them.
    @discardableResult
    func addEvent(on day: CalendarDate = LocalDay.today(), text: String, time: LineClock?) async -> Bool {
        guard !text.allSatisfy(\.isWhitespace) else { return false }
        guard canAddEvent, let writer, let index else { return false }
        isProcessing = true
        isWriting = true
        entryErrorText = nil
        var saved = false
        do {
            try await writer.addingEvent(on: day, text: text, time: time)
            saved = true
            let snapshot = try await Task.detached { try index.snapshot() }.value
            content = VaultReadModel(snapshot: snapshot)
            counts = IndexCounts(snapshot: snapshot)
            try await reloadRecognition()
            lastUpdated = Date()
        } catch {
            if case VaultStoreError.indexUpdateFailed = error { saved = true }
            entryErrorText =
                saved
                ? EntryWriteError.savedWithoutIndex : EntryWriteError.message(for: error)
        }
        isWriting = false
        isProcessing = false
        if pendingRefresh && pendingSelection == nil { await refresh(rebuild: pendingRebuild) }
        await applyPendingSelection()
        return saved
    }

    /// Disk reads belong to the selected vault, never to the index's paragraph projection.
    func dayDocument(for day: CalendarDate) async throws -> RawDocument {
        guard let writer else { throw VaultStoreError.staleTarget }
        let current = generation
        let document: RawDocument
        do { document = try await writer.dayDocument(for: day) } catch CocoaError.fileReadNoSuchFile {
            document = RawDocument(bytes: [])
        }
        guard generation == current else { throw VaultStoreError.staleTarget }
        guard !document.isReadOnly else { throw EditError.readOnlyDocument }
        return document
    }

    func document(at path: String) async throws -> RawDocument {
        guard let writer else { throw VaultStoreError.staleTarget }
        let current = generation
        let document = try await writer.document(at: path)
        guard generation == current else { throw VaultStoreError.staleTarget }
        return document
    }

    func search(_ query: String) async throws -> [SearchResult] {
        guard let index else { return [] }
        let current = generation
        let results = try await Task.detached { try index.searchResults(query) }.value
        guard generation == current else { throw VaultStoreError.staleTarget }
        return results
    }

    /// Full history is read on demand for detail screens and dates outside the bounded snapshot.
    func goalHistory(key: String? = nil) async throws -> [String: [GoalLog]] {
        guard let index else { throw VaultStoreError.staleTarget }
        let current = generation
        let logs = try await Task.detached {
            Dictionary(grouping: try index.goalLogs(key: key), by: \.key)
                .mapValues { $0.compactMap(GoalLog.init(indexed:)) }
        }.value
        guard generation == current else { throw VaultStoreError.staleTarget }
        return logs
    }

    /// Shared file-first edit lifecycle. A saved-but-unindexed edit must never be retried.
    func performEdit(
        path: String, operation: @Sendable (VaultStore) async throws -> Void
    ) async throws {
        guard canAddEvent, let writer, let index else { throw VaultStoreError.staleTarget }
        isProcessing = true
        isWriting = true
        var saved = false
        var failure: (any Error)?
        do {
            try await operation(writer)
            saved = true
            let snapshot = try await Task.detached { try index.snapshot() }.value
            content = VaultReadModel(snapshot: snapshot)
            counts = IndexCounts(snapshot: snapshot)
            try await reloadRecognition()
            lastUpdated = Date()
        } catch {
            failure = saved ? VaultStoreError.indexUpdateFailed(path: path, underlying: error) : error
            if case VaultStoreError.staleTarget = error { pendingRefresh = true }
        }
        await finishEntityWrite()
        if let failure { throw failure }
    }

    func renameEntity(at path: String, to name: String, qualifier: String?) async throws -> RenameResult {
        guard canAddEvent, let writer, let index else { throw VaultStoreError.staleTarget }
        isProcessing = true
        isWriting = true
        do {
            let result = try await writer.renamingEntity(at: path, to: name, qualifier: qualifier)
            do {
                let snapshot = try await Task.detached { try index.snapshot() }.value
                content = VaultReadModel(snapshot: snapshot)
                counts = IndexCounts(snapshot: snapshot)
                try await reloadRecognition()
                lastUpdated = Date()
            } catch {
                entryErrorText = String(localized: "Varlık kaydedildi, indeks güncellenemedi.")
                pendingRefresh = true
                pendingRebuild = true
            }
            if result.failures.contains(where: { if case .index = $0.reason { true } else { false } }) {
                pendingRefresh = true
                pendingRebuild = true
            }
            await finishEntityWrite()
            return result
        } catch {
            pendingRefresh = true
            await finishEntityWrite()
            throw error
        }
    }

    private func reloadRecognition() async throws {
        guard let index else { return }
        let values = try await Task.detached { (try index.knownEntities(), try index.entityUsage()) }.value
        knownEntities = values.0
        entityUsage = values.1
    }

    func createEntity(kind: VaultEntityKind, name: String, qualifier: String?) async throws -> KnownEntity {
        guard canAddEvent, let writer else { throw VaultStoreError.staleTarget }
        isProcessing = true
        isWriting = true
        do {
            let entity = try await persistEntity(writer: writer, kind: kind, name: name, qualifier: qualifier)
            await finishEntityWrite()
            return entity
        } catch {
            await finishEntityWrite()
            throw error
        }
    }

    private func finishEntityWrite() async {
        isProcessing = false
        isWriting = false
        if pendingRefresh && pendingSelection == nil { await refresh(rebuild: pendingRebuild) }
        await applyPendingSelection()
    }

    private func persistEntity(
        writer: VaultStore, kind: VaultEntityKind, name: String, qualifier: String?
    ) async throws -> KnownEntity {
        let path: String
        do {
            path = try await writer.creatingEntity(kind: kind, name: name, qualifier: qualifier)
        } catch VaultStoreError.indexUpdateFailed(let savedPath, _) {
            // The entity already exists on disk. Never offer to create it again.
            path = savedPath
            entryErrorText = String(localized: "Varlık kaydedildi, indeks güncellenemedi.")
            pendingRefresh = true
            pendingRebuild = true
        }
        let entity = KnownEntity(
            file: path, kind: kind == .person ? .person : .place, name: name, qualifier: qualifier)
        knownEntities.append(entity)
        do {
            try await reloadRecognition()
            if let index {
                let snapshot = try await Task.detached { try index.snapshot() }.value
                content = VaultReadModel(snapshot: snapshot)
                counts = IndexCounts(snapshot: snapshot)
                lastUpdated = Date()
            }
            if !knownEntities.contains(where: { $0.file == path }) { knownEntities.append(entity) }
        } catch { entryErrorText = String(localized: "Varlık kaydedildi, indeks güncellenemedi.") }
        return entity
    }

    private func applyPendingSelection() async {
        guard let selected = pendingSelection else { return }
        pendingSelection = nil
        await select(selected)
    }

    private func open(_ url: URL) async {
        watcher?.stop()
        watcher = nil
        generation = UUID()
        let current = generation
        pendingRefresh = false
        pendingRebuild = false
        unwatchedDirectoryCount = 0
        vaultURL = url
        index = nil
        writer = nil
        entryErrorText = nil
        content = .empty
        knownEntities = []
        entityUsage = []
        counts = IndexCounts()
        skippedPaths = []
        lastUpdated = nil
        errorText = nil
        isProcessing = true
        let support = supportURL
        do {
            let opened = try await Task.detached {
                try FileManager.default.createDirectory(at: support, withIntermediateDirectories: true)
                let identity = url.resolvingSymlinksInPath().standardizedFileURL.path
                let digest = SHA256.hash(data: Data(identity.utf8)).map { String(format: "%02x", $0) }.joined()
                return try VaultIndex(databaseURL: support.appendingPathComponent(digest + ".sqlite"))
            }.value
            guard generation == current else { return }
            index = opened
            writer = VaultStore(vaultRoot: url, index: opened)
        } catch {
            if generation == current { report(error) }
        }
        isProcessing = false
        guard index != nil else {
            await applyPendingSelection()
            return
        }
        watcher = VaultWatcher(
            root: url, directoryLimit: watcherDirectoryLimit,
            onCoverageChange: { [weak self] count in
                Task { @MainActor [weak self] in
                    guard let self, self.generation == current else { return }
                    self.unwatchedDirectoryCount = count
                }
            },
            onChange: { [weak self] in
                Task { @MainActor [weak self] in
                    guard let self, self.generation == current else { return }
                    await self.refresh()
                }
            })
        // The explicit opening refresh also serves as the initial foreground refresh.
        watcher?.setForeground(foreground, triggerOnActivation: false)
        await refresh()
    }

    func refresh(rebuild: Bool = false) async {
        guard let index, let root = vaultURL else { return }
        if isProcessing {
            pendingRefresh = true
            pendingRebuild = pendingRebuild || rebuild
            return
        }
        let current = generation
        isProcessing = true
        var full = rebuild
        repeat {
            pendingRefresh = false
            pendingRebuild = false
            do {
                let result = try await update(index, root, full)
                guard generation == current else { break }
                content = result.content
                counts = result.counts
                skippedPaths = result.skippedPaths
                try await reloadRecognition()
                lastUpdated = Date()
                errorText = nil
            } catch {
                if generation == current { report(error) }
            }
            full = pendingRebuild
        } while pendingRefresh && pendingSelection == nil && generation == current
        guard generation == current else { return }
        isProcessing = false
        await applyPendingSelection()
    }
}
