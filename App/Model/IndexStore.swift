import CryptoKit
import EntityRecognition
import Foundation
import GoalTracking
import Observation
import Summaries
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
    var requiresOnboarding: Bool
    var importModel: VaultImportModel?
    private(set) var isInspectingImport = false
    private(set) var indexingFileCount: Int?
    private(set) var isVaultReadOnly = false
    private(set) var vaultURL: URL?
    private(set) var content = VaultReadModel.empty
    private(set) var knownEntities: [KnownEntity] = []
    private(set) var entityTypes = EntityTypeCatalog()
    private(set) var nearbyPlaces: [NearbyPlace] = []
    private(set) var mapPlaces: [MapPlace] = []
    private(set) var entityUsage: [EntityUsage] = []
    private(set) var counts = IndexCounts()
    private(set) var skippedPaths: [SkippedPath] = []
    private(set) var lastUpdated: Date? {
        didSet {
            onSnapshotChange?(lastUpdated == nil ? nil : content, vaultURL)
            onGeofenceSnapshotChange?()
        }
    }
    @ObservationIgnored var onGeofenceSnapshotChange: (() -> Void)?
    @ObservationIgnored var onSnapshotChange: ((VaultReadModel?, URL?) -> Void)?
    private(set) var isProcessing = false
    private(set) var errorText: String?
    private(set) var entryErrorText: String?
    private(set) var isWriting = false
    var canAddEvent: Bool { writer != nil && !isProcessing && !isVaultReadOnly }
    private(set) var notice: String?
    private(set) var pendingSelection: URL?
    private(set) var unwatchedDirectoryCount = 0
    @ObservationIgnored private let location: VaultLocation
    @ObservationIgnored private let supportURL: URL
    @ObservationIgnored private let update:
        @Sendable (VaultIndex, URL, Bool, EntityTypeCatalog, Bool) async throws -> IndexUpdate
    @ObservationIgnored private let watcherDirectoryLimit: Int
    @ObservationIgnored private var index: VaultIndex?
    @ObservationIgnored private var writer: VaultStore?
    @ObservationIgnored private var watcher: VaultWatcher?
    @ObservationIgnored private var foreground = false
    @ObservationIgnored private var pendingRefresh = false
    @ObservationIgnored private var pendingRebuild = false
    @ObservationIgnored private var refreshInFlight = false
    @ObservationIgnored private var generation = UUID()

    init(
        location: VaultLocation = VaultLocation(), supportURL: URL? = nil,
        watcherDirectoryLimit: Int = 256,
        update:
            @escaping @Sendable (VaultIndex, URL, Bool, EntityTypeCatalog, Bool) async throws -> IndexUpdate =
            IndexUpdate.read
    ) {
        self.location = location
        requiresOnboarding = location.needsFirstLaunch
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
        guard !requiresOnboarding else { return }
        await start()
    }

    func start() async {
        if let vaultURL {
            if requiresOnboarding { await open(vaultURL) }
            return
        }
        do {
            let resolved = try location.resolve()
            notice = resolved.notice
            await open(resolved.url)
        } catch { report(error) }
    }

    /// Background callbacks must reopen security scope and finish indexing before any write.
    func prepareForIntent() async throws {
        if vaultURL == nil { await open(try location.existingVaultForIntent()) }
        try await prepareForBackground()
    }

    func prepareForBackground() async throws {
        if let vaultURL {
            try location.resumeBackgroundAccess(to: vaultURL)
        } else {
            let root = try location.resolveForBackground()
            await open(root)
        }
        for _ in 0..<400 {
            if !isProcessing { break }
            try await Task.sleep(for: .milliseconds(20))
        }
        guard canAddEvent, lastUpdated != nil else { throw VaultStoreError.staleTarget }
        await refresh()
        guard canAddEvent, errorText == nil else { throw VaultStoreError.staleTarget }
    }

    func inspectSelection(_ url: URL) async {
        guard !isInspectingImport, importModel == nil else { return }
        isInspectingImport = true
        defer { isInspectingImport = false }
        do {
            let model = try await VaultImportModel(root: url)
            if model.report.needsPreparation { importModel = model } else { await select(url) }
        } catch { report(error) }
    }

    func finishImport(_ model: VaultImportModel) async {
        guard importModel?.id == model.id, !model.isApplying else { return }
        await select(model.report.root)
        if vaultURL == model.report.root, lastUpdated != nil, errorText == nil { importModel = nil }
    }

    func select(_ url: URL) async {
        if isProcessing || refreshInFlight {
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

    /// Summary history is queried on demand and belongs to this vault generation.
    func computeSummary(period: SummaryPeriod, day: CalendarDate, from: CalendarDate, to: CalendarDate) async throws
        -> PeriodSummary
    {
        guard let index else { throw VaultStoreError.staleTarget }
        let current = generation
        let result = try await Task.detached {
            PeriodSummary.compute(period: period, containing: day, data: try index.summaryInput(from: from, to: to))
        }.value
        guard generation == current else { throw VaultStoreError.staleTarget }
        return result
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

    func saveEntityType(_ type: EntityTypeDefinition, replacing expected: EntityTypeDefinition?) async throws {
        try await performEdit(path: ".app/types.json") { try await $0.savingEntityType(type, replacing: expected) }
    }

    func deleteEntityType(_ type: EntityTypeDefinition) async throws {
        try await performEdit(path: ".app/types.json") { try await $0.deletingEntityType(type) }
    }

    private func reloadRecognition() async throws {
        guard let index else { return }
        if let writer { entityTypes = await writer.entityTypes() }
        let kinds = Set(entityTypes.allTypes.map(\.id))
        let values = try await Task.detached { (try index.knownEntities(kinds: kinds), try index.entityUsage()) }.value
        knownEntities = values.0
        entityUsage = values.1
        var places: [NearbyPlace] = []
        var coordinates: [MapPlace] = []
        if let writer {
            for entity in values.0 where entity.kind == .place {
                if let document = try? await writer.document(at: entity.file) {
                    if let coordinate = PlaceCoordinate(document: document) {
                        coordinates.append(MapPlace(entity: entity, coordinate: coordinate))
                    }
                    if let place = NearbyPlace(entity: entity, document: document) { places.append(place) }
                }
            }
        }
        nearbyPlaces = places
        mapPlaces = coordinates
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
            file: path, kind: KnownEntity.Kind(rawValue: kind.rawValue)!, name: name, qualifier: qualifier)
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
        refreshInFlight = false
        unwatchedDirectoryCount = 0
        vaultURL = url
        index = nil
        writer = nil
        entryErrorText = nil
        content = .empty
        indexingFileCount = nil
        isVaultReadOnly = !VaultImportScanner.supportsSettings(at: url)
        if isVaultReadOnly {
            notice = String(localized: "Kasa sürümü okunamıyor veya desteklenmiyor. Kasa salt okunur açıldı.")
        }
        knownEntities = []
        entityTypes = EntityTypeCatalog()
        nearbyPlaces = []
        mapPlaces = []
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
        if index != nil {
            indexingFileCount = try? await Task.detached { try VaultImportScanner.markdownFiles(in: url).count }.value
            guard generation == current else { return }
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
        guard generation == current else { return }
        indexingFileCount = nil
        if lastUpdated != nil { requiresOnboarding = false }
    }

    func refresh(rebuild: Bool = false) async {
        guard let index, let root = vaultURL else { return }
        if isProcessing || refreshInFlight {
            pendingRefresh = true
            pendingRebuild = pendingRebuild || rebuild
            return
        }
        let current = generation
        refreshInFlight = true
        var full = rebuild
        var published = false
        // First load keeps the busy indicator up for the whole update.
        if lastUpdated == nil {
            isProcessing = true
            published = true
        }
        repeat {
            pendingRefresh = false
            pendingRebuild = false
            do {
                let result = try await update(index, root, full, entityTypes, lastUpdated != nil)
                guard generation == current else { return }
                if !result.hasChanges {
                    full = pendingRebuild
                    continue
                }
                if !published {
                    isProcessing = true
                    published = true
                }
                content = result.content
                counts = result.counts
                skippedPaths = result.skippedPaths
                try await reloadRecognition()
                lastUpdated = Date()
                errorText = nil
            } catch {
                if !published {
                    isProcessing = true
                    published = true
                }
                if generation == current { report(error) }
            }
            full = pendingRebuild
        } while pendingRefresh && pendingSelection == nil && generation == current
        guard generation == current else { return }
        refreshInFlight = false
        if published { isProcessing = false }
        await applyPendingSelection()
    }
}
