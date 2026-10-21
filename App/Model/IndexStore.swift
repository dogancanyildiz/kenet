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
    /// Registered vault could not be opened; no writer is active and writes must not go elsewhere.
    private(set) var isVaultInaccessible = false
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
    /// Vault is open and writable. Background refresh or an in-flight write does not clear this;
    /// those callers wait on the write queue instead of being rejected.
    var canAddEvent: Bool { writer != nil && !isVaultReadOnly }
    private(set) var notice: String?
    private(set) var pendingSelection: URL?
    private(set) var unwatchedDirectoryCount = 0
    @ObservationIgnored private let location: VaultLocation
    @ObservationIgnored private let supportURL: URL
    /// Index refresh; the fourth argument lists the changed directories, `nil` for the whole vault.
    @ObservationIgnored private let update:
        @Sendable (VaultIndex, URL, Bool, Set<String>?, EntityTypeCatalog, Bool, [SkippedPath], VaultReadModel)
            async throws -> IndexUpdate
    @ObservationIgnored private let watcherDirectoryLimit: Int
    @ObservationIgnored private let watcherTicker: any WatcherTicker
    /// False keeps directory sources on the Mac too (`VaultWatcher`); iOS always uses them.
    @ObservationIgnored private let watcherFileEvents: Bool
    /// Test seam: runs on the watcher queue just before its first directory walk.
    @ObservationIgnored var testingWatcherInitialScan: (@Sendable () -> Void)?
    /// iCloud's unresolved versions for Diagnostics (`computeConflictedFiles`); a fake in tests.
    @ObservationIgnored private let conflictVersions: any ConflictVersionSource
    @ObservationIgnored private var index: VaultIndex?
    @ObservationIgnored private var writer: VaultStore?
    @ObservationIgnored private var watcher: VaultWatcher?
    @ObservationIgnored private var foreground = false
    @ObservationIgnored private var pendingRefresh = false
    @ObservationIgnored private var pendingRebuild = false
    /// Directories the pending refresh rescans; `nil` rescans the whole vault.
    @ObservationIgnored private var pendingDirectories: Set<String>?
    /// A failed refresh may have left changes anywhere: the next refresh scans the whole vault.
    @ObservationIgnored private var needsFullRefresh = false
    @ObservationIgnored private var refreshInFlight = false
    /// Bumped when a write publishes so an overlapping refresh can discard its stale snapshot.
    @ObservationIgnored private var contentEpoch = 0
    @ObservationIgnored private var generation = UUID()
    /// Serializes user writes so a busy vault queues instead of dropping Enter.
    @ObservationIgnored private var writeBusy = false
    @ObservationIgnored private var writeWaiters: [(id: UUID, continuation: CheckedContinuation<Void, any Error>)] = []
    /// True from vault identity reset until the opening refresh finishes (or open aborts).
    @ObservationIgnored private var isOpening = false

    init(
        location: VaultLocation = VaultLocation(), supportURL: URL? = nil,
        watcherDirectoryLimit: Int = 256,
        watcherTicker: any WatcherTicker = DispatchWatcherTicker(), watcherFileEvents: Bool = true,
        conflictVersions: any ConflictVersionSource = SystemConflictVersionSource(),
        update:
            (
                @Sendable (
                    VaultIndex, URL, Bool, EntityTypeCatalog, Bool, [SkippedPath], VaultReadModel
                ) async throws -> IndexUpdate
            )? = nil,
        scopedUpdate:
            (
                @Sendable (
                    VaultIndex, URL, Bool, Set<String>?, EntityTypeCatalog, Bool, [SkippedPath], VaultReadModel
                ) async throws -> IndexUpdate
            )? = nil
    ) {
        self.location = location
        requiresOnboarding = location.needsFirstLaunch
        if let scopedUpdate {
            self.update = scopedUpdate
        } else if let update {
            // A whole-vault update also covers a directory request.
            self.update = { index, root, rebuild, _, previous, skip, skipped, previousContent in
                try await update(index, root, rebuild, previous, skip, skipped, previousContent)
            }
        } else {
            self.update = { index, root, rebuild, directories, previous, skip, skipped, previousContent in
                try await IndexUpdate.read(
                    index: index, root: root, rebuild: rebuild, previousTypes: previous,
                    skipUnchanged: skip, previousSkipped: skipped, previousContent: previousContent,
                    directories: directories)
            }
        }
        self.watcherDirectoryLimit = watcherDirectoryLimit
        self.watcherTicker = watcherTicker
        self.watcherFileEvents = watcherFileEvents
        self.conflictVersions = conflictVersions
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
        // A second automatic start in the same session must not re-resolve into Documents/Vault.
        if isVaultInaccessible { return }
        if let vaultURL {
            if requiresOnboarding { await open(vaultURL) }
            return
        }
        do {
            switch try location.resolve() {
            case .available(let url, let resolvedNotice):
                notice = resolvedNotice
                isVaultInaccessible = false
                await open(url)
            case .inaccessible:
                enterInaccessibleState()
            }
        } catch { report(error) }
    }

    /// Re-resolves the saved bookmark (or legacy Documents/Vault) without creating a new local vault.
    func retryVaultAccess() async {
        do {
            switch try location.resolveSavedVault() {
            case .available(let url, let resolvedNotice):
                notice = resolvedNotice
                errorText = nil
                isVaultInaccessible = false
                await open(url)
            case .inaccessible:
                enterInaccessibleState()
                errorText = String(localized: "Klasöre hâlâ erişilemiyor.")
            }
        } catch {
            enterInaccessibleState()
            errorText = String(localized: "Klasöre hâlâ erişilemiyor.")
        }
    }

    /// Background callbacks must reopen security scope and finish indexing before any write.
    func prepareForIntent() async throws {
        guard !isVaultInaccessible else { throw VaultStoreError.staleTarget }
        if vaultURL == nil { await open(try location.existingVaultForIntent()) }
        try await prepareForBackground()
    }

    func prepareForBackground() async throws {
        guard !isVaultInaccessible else { throw VaultStoreError.staleTarget }
        if let vaultURL {
            try location.resumeBackgroundAccess(to: vaultURL)
        } else {
            let root = try location.resolveForBackground()
            await open(root)
        }
        // Drain in-flight and queued writes before the intent write; do not abandon them mid-file.
        for _ in 0..<400 {
            if !isProcessing && !refreshInFlight && !writeBusy && writeWaiters.isEmpty { break }
            try await Task.sleep(for: .milliseconds(20))
        }
        guard canAddEvent, lastUpdated != nil, !writeBusy, writeWaiters.isEmpty else {
            throw VaultStoreError.staleTarget
        }
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
            isVaultInaccessible = false
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
        // No vault selected: nothing to write to, as when the vault is not writable.
        guard !text.allSatisfy(\.isWhitespace), let root = vaultURL else { return false }
        do {
            return try await withWriteSlot {
                try await awaitEditTurn(in: root)
                guard canAddEvent, let writer, let index else { return false }
                isProcessing = true
                isWriting = true
                entryErrorText = nil
                var saved = false
                do {
                    try await writer.addingEvent(on: day, text: text, time: time)
                    saved = true
                    try await publishAfterWrite(from: index, changedPaths: ["journal/\(day).md"])
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
        } catch {
            entryErrorText = EntryWriteError.message(for: error)
            return false
        }
    }

    /// Disk reads belong to the selected vault, never to the index's paragraph projection. Like
    /// every on-demand read here, the read follows the query contract (`answer(seam:_:)`).
    func dayDocument(for day: CalendarDate) async throws -> RawDocument {
        guard let writer else { throw VaultStoreError.staleTarget }
        let document = try await answer(seam: \.testingQueryDidFinish) {
            do { return try await writer.dayDocument(for: day) } catch CocoaError.fileReadNoSuchFile {
                return RawDocument(bytes: [])
            }
        }
        guard !document.isReadOnly else { throw EditError.readOnlyDocument }
        return document
    }

    func document(at path: String) async throws -> RawDocument {
        guard let writer else { throw VaultStoreError.staleTarget }
        return try await answer(seam: \.testingQueryDidFinish) { try await writer.document(at: path) }
    }

    /// Empty with no index open.
    func search(_ query: String) async throws -> [SearchResult] {
        try await indexQuery(seam: \.testingQueryDidFinish, whenClosed: .empty([])) { try $0.searchResults(query) }
    }

    /// Summary history is queried on demand and belongs to this vault generation.
    func computeSummary(
        period: SummaryPeriod, day: CalendarDate, from: CalendarDate, to: CalendarDate, today: CalendarDate? = nil
    ) async throws -> PeriodSummary {
        try await indexQuery(seam: \.testingQueryDidFinish, whenClosed: .stale) {
            PeriodSummary.compute(
                period: period, containing: day, data: try $0.summaryInput(from: from, to: to), today: today)
        }
    }

    /// Same month-day history is queried on demand and belongs to this vault generation.
    func computeOnThisDay(_ today: CalendarDate) async throws -> OnThisDay? {
        try await indexQuery(seam: \.testingQueryDidFinish, whenClosed: .stale) {
            OnThisDay.select(today: today, data: try $0.onThisDayInput(for: today))
        }
    }

    /// Anniversary fields are queried on demand and belong to this vault generation.
    /// A nil window is the entity page: the nearest date, with no day limit.
    func computeImportantDates(_ today: CalendarDate, within windowDays: Int? = ImportantDates.windowDays) async throws
        -> [ImportantDate]
    {
        try await indexQuery(seam: \.testingQueryDidFinish, whenClosed: .stale) {
            let fields = try $0.anniversaryFields().map {
                ImportantDateField(file: $0.file, key: $0.key, value: $0.value)
            }
            return ImportantDates.select(today: today, within: windowDays, fields: fields)
        }
    }

    /// Incoming wikilinks to a day are queried on demand and belong to this vault generation.
    func computeDayBacklinks(_ day: CalendarDate) async throws -> [DayBacklink] {
        try await indexQuery(seam: \.testingQueryDidFinish, whenClosed: .stale) {
            try $0.dayBacklinks(for: day)
        }
    }

    /// Full history is read on demand for detail screens and dates outside the bounded snapshot.
    func goalHistory(key: String? = nil) async throws -> [String: [GoalLog]] {
        try await indexQuery(seam: \.testingQueryDidFinish, whenClosed: .stale) {
            Dictionary(grouping: try $0.goalLogs(key: key), by: \.key)
                .mapValues { $0.compactMap(GoalLog.init(indexed:)) }
        }
    }

    /// Shared file-first edit lifecycle. A saved-but-unindexed edit must never be retried.
    /// Caller-supplied `path` is treated as an estimate: if that path cannot be loaded after the
    /// write, the read model marks itself for a full reconcile on the next publish.
    func performEdit(
        path: String, operation: (VaultStore) async throws -> Void
    ) async throws {
        try await performEdit(estimatedPaths: [path]) {
            try await operation($0)
            return [path]
        }
    }

    /// Like `performEdit(path:)` but the operation reports the paths it actually changed
    /// (for example after filename sanitization in `creatingGoal`).
    /// The edit belongs to the vault selected when this is called.
    func performEdit(
        estimatedPaths: Set<String> = [],
        operation: (VaultStore) async throws -> Set<String>
    ) async throws {
        try await performEdit(in: vaultURL, estimatedPaths: estimatedPaths, operation: operation)
    }

    /// `root` is the vault the edit belongs to. A vault selected since, even while the edit waited
    /// for its turn or for a refresh, is never written: `staleTarget`, and nothing is written.
    private func performEdit(
        in root: URL?, estimatedPaths: Set<String>,
        operation: (VaultStore) async throws -> Set<String>
    ) async throws {
        try await withWriteSlot {
            try await awaitEditTurn(in: root)
            guard canAddEvent, let writer, let index else { throw VaultStoreError.staleTarget }
            isProcessing = true
            isWriting = true
            var saved = false
            var changedPaths: Set<String> = []
            var failure: (any Error)?
            do {
                changedPaths = try await operation(writer)
                saved = true
                let forceFull = changedPaths.contains { $0 == ".app/types.json" || $0.hasPrefix(".app/") }
                try await publishAfterWrite(
                    from: index, changedPaths: changedPaths, forceFull: forceFull,
                    estimatedPaths: estimatedPaths)
            } catch {
                let reportPath = changedPaths.sorted().first ?? estimatedPaths.sorted().first ?? ""
                failure = saved ? VaultStoreError.indexUpdateFailed(path: reportPath, underlying: error) : error
                if case VaultStoreError.staleTarget = error { queueRefresh(rebuild: false, directories: nil) }
            }
            await finishEntityWrite()
            if let failure { throw failure }
        }
    }

    func renameEntity(at path: String, to name: String, qualifier: String?) async throws -> RenameResult {
        let root = vaultURL
        return try await withWriteSlot {
            try await awaitEditTurn(in: root)
            guard canAddEvent, let writer, let index else { throw VaultStoreError.staleTarget }
            isProcessing = true
            isWriting = true
            do {
                let result = try await writer.renamingEntity(at: path, to: name, qualifier: qualifier)
                do {
                    var changed = Set(result.updatedFiles)
                    changed.insert(result.path)
                    changed.insert(path)
                    var deleted: Set<String> = []
                    if path != result.path { deleted.insert(path) }
                    try await publishAfterWrite(
                        from: index, changedPaths: changed, deletedPaths: deleted)
                } catch {
                    entryErrorText = String(localized: "Varlık kaydedildi, indeks güncellenemedi.")
                    queueRefresh(rebuild: true, directories: nil)
                }
                if result.failures.contains(where: { if case .index = $0.reason { true } else { false } }) {
                    queueRefresh(rebuild: true, directories: nil)
                }
                await finishEntityWrite()
                return result
            } catch {
                queueRefresh(rebuild: false, directories: nil)
                await finishEntityWrite()
                throw error
            }
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
        // One vault throughout: place signatures are taken under `root` and the files are read by
        // `writer`. A vault opened meanwhile gets a new writer; publishing this reload would leave
        // the previous vault's entities and places on screen until the next write.
        let writer = writer
        let root = vaultURL
        let types: EntityTypeCatalog? = if let writer { await writer.entityTypes() } else { nil }
        let kinds = Set((types ?? entityTypes).allTypes.map(\.id))
        let values = try await Task.detached {
            let entities = try index.knownEntities(kinds: kinds)
            return (entities, try index.entityUsage(), PlaceDocumentCache.signatures(of: entities, in: root))
        }.value
        var places: [NearbyPlace] = []
        var coordinates: [MapPlace] = []
        if let writer {
            for entity in values.0 where entity.kind == .place {
                if let document = await placeDocument(entity.file, signature: values.2[entity.file], from: writer) {
                    if let coordinate = PlaceCoordinate(document: document) {
                        coordinates.append(MapPlace(entity: entity, coordinate: coordinate))
                    }
                    if let place = NearbyPlace(entity: entity, document: document) { places.append(place) }
                }
            }
        }
        try await testingRecognitionReloadDidLoad?()
        guard writer === self.writer else { return }
        if let types { entityTypes = types }
        knownEntities = values.0
        entityUsage = values.1
        if writer != nil { placeDocuments.keep(only: values.2.keys) }
        nearbyPlaces = places
        mapPlaces = coordinates
    }

    func createEntity(
        kind: VaultEntityKind, name: String, qualifier: String?, aliases: [String]? = nil
    ) async throws -> KnownEntity {
        let root = vaultURL
        return try await withWriteSlot {
            try await awaitEditTurn(in: root)
            guard canAddEvent, let writer else { throw VaultStoreError.staleTarget }
            isProcessing = true
            isWriting = true
            do {
                let entity = try await persistEntity(
                    writer: writer, kind: kind, name: name, qualifier: qualifier, aliases: aliases)
                await finishEntityWrite()
                return entity
            } catch {
                await finishEntityWrite()
                throw error
            }
        }
    }

    private func finishEntityWrite() async {
        isProcessing = false
        isWriting = false
        if pendingRefresh && pendingSelection == nil { await refresh(rebuild: pendingRebuild) }
        await applyPendingSelection()
    }

    private func persistEntity(
        writer: VaultStore, kind: VaultEntityKind, name: String, qualifier: String?, aliases: [String]?
    ) async throws -> KnownEntity {
        let path: String
        var indexFailed = false
        do {
            path = try await writer.creatingEntity(kind: kind, name: name, qualifier: qualifier, aliases: aliases)
        } catch VaultStoreError.indexUpdateFailed(let savedPath, _) {
            // The entity already exists on disk. Never offer to create it again.
            path = savedPath
            indexFailed = true
        }
        let entity = KnownEntity(
            file: path, kind: KnownEntity.Kind(rawValue: kind.rawValue)!, name: name, qualifier: qualifier,
            aliases: aliases ?? [])
        // Saved in the vault `writer` belongs to; a vault opened meanwhile never lists it, nor
        // shows its index error or rebuilds for it.
        guard writer === self.writer else { return entity }
        if indexFailed {
            entryErrorText = String(localized: "Varlık kaydedildi, indeks güncellenemedi.")
            queueRefresh(rebuild: true, directories: nil)
        }
        knownEntities.append(entity)
        do {
            if let index {
                try await publishAfterWrite(from: index, changedPaths: [path])
            } else {
                try await reloadRecognition()
            }
            if writer === self.writer, !knownEntities.contains(where: { $0.file == path }) {
                knownEntities.append(entity)
            }
        } catch { entryErrorText = String(localized: "Varlık kaydedildi, indeks güncellenemedi.") }
        return entity
    }

    /// Read model off the main actor; only assignment happens on IndexStore.
    private func publishAfterWrite(
        from index: VaultIndex, changedPaths: Set<String>, deletedPaths: Set<String> = [],
        forceFull: Bool = false, estimatedPaths: Set<String> = []
    ) async throws {
        let previous = content
        let writer = self.writer
        do {
            let published = try await Task.detached {
                try VaultPublishedContent.applying(
                    previous: previous, index: index, changedPaths: changedPaths,
                    deletedPaths: deletedPaths, forceFull: forceFull,
                    estimatedPaths: estimatedPaths)
            }.value
            // `open` replaces `writer`. This publish belongs to the vault that started it.
            guard writer === self.writer else { return }
            content = published.content
            counts = published.counts
            try await reloadRecognition()
            guard writer === self.writer else { return }
            lastUpdated = Date()
            contentEpoch += 1
        } catch {
            guard writer === self.writer else { return }
            // Index may already include the write; keep a reconcile flag so the next publish
            // cannot skip or patch on top of a drifted model. Recognition can fail after the
            // content is already replaced: screens watch `lastUpdated`, so it has to move too.
            var marked = content
            marked.markNeedsFullReconcile()
            content = marked
            lastUpdated = Date()
            contentEpoch += 1
            throw error
        }
    }

    func waitWhileRefreshInFlight() async {
        while (refreshInFlight || isOpening) && !Task.isCancelled {
            try? await Task.sleep(for: .milliseconds(10))
        }
    }

    /// FIFO write gate. A cancelled waiter is removed so it cannot hold the queue.
    private func withWriteSlot<T>(_ body: () async throws -> T) async throws -> T {
        let requested = generation
        try await acquireWriteSlot()
        do {
            // Cancellation after handoff still owns the slot; release before rethrowing.
            try Task.checkCancellation()
            // A waiter handed the slot across a vault switch must not write into the new vault.
            guard generation == requested else { throw CancellationError() }
            let value = try await body()
            releaseWriteSlot()
            return value
        } catch {
            releaseWriteSlot()
            throw error
        }
    }

    private func acquireWriteSlot() async throws {
        try Task.checkCancellation()
        if !writeBusy {
            writeBusy = true
            return
        }
        let id = UUID()
        try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, any Error>) in
                writeWaiters.append((id: id, continuation: continuation))
            }
        } onCancel: {
            Task { @MainActor in
                if let index = writeWaiters.firstIndex(where: { $0.id == id }) {
                    let waiter = writeWaiters.remove(at: index)
                    waiter.continuation.resume(throwing: CancellationError())
                }
            }
        }
        // Continuations that resume normally already own the slot; do not check cancellation here.
    }

    /// Test seam: occupy the write slot without running a body.
    func testingOccupyWriteSlot() {
        precondition(!writeBusy && writeWaiters.isEmpty)
        writeBusy = true
    }

    /// Test seam: hand the slot to the next waiter (or clear busy).
    func testingReleaseWriteSlot() {
        releaseWriteSlot()
    }

    private func releaseWriteSlot() {
        if writeWaiters.isEmpty {
            writeBusy = false
        } else {
            let next = writeWaiters.removeFirst()
            next.continuation.resume()
        }
    }

    private func failQueuedWriters() {
        let waiters = writeWaiters
        writeWaiters = []
        for waiter in waiters { waiter.continuation.resume(throwing: CancellationError()) }
    }

    private func applyPendingSelection() async {
        guard let selected = pendingSelection else { return }
        pendingSelection = nil
        await select(selected)
    }

    private func enterInaccessibleState() {
        watcher?.stop()
        watcher = nil
        generation = UUID()
        pendingRefresh = false
        pendingRebuild = false
        pendingDirectories = nil
        needsFullRefresh = false
        refreshInFlight = false
        contentEpoch = 0
        failQueuedWriters()
        isOpening = false
        isVaultInaccessible = true
        unwatchedDirectoryCount = 0
        vaultURL = nil
        index = nil
        writer = nil
        entryErrorText = nil
        content = .empty
        indexingFileCount = nil
        isVaultReadOnly = false
        knownEntities = []
        entityTypes = EntityTypeCatalog()
        nearbyPlaces = []
        mapPlaces = []
        entityUsage = []
        counts = IndexCounts()
        skippedPaths = []
        lastUpdated = nil
        errorText = nil
        notice = nil
        isProcessing = false
        isWriting = false
    }

    private func open(_ url: URL) async {
        watcher?.stop()
        watcher = nil
        generation = UUID()
        let current = generation
        pendingRefresh = false
        pendingRebuild = false
        pendingDirectories = nil
        needsFullRefresh = false
        refreshInFlight = false
        contentEpoch = 0
        // Vault identity changed: queued writes must not run against the previous root.
        // `writeBusy` is left alone: `open` can run inside a write body (pending selection),
        // and clearing it there would let two writes run at once.
        failQueuedWriters()
        isOpening = true
        defer { if generation == current { isOpening = false } }
        isVaultInaccessible = false
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
                try IndexSupportDirectory.prepare(at: support)
                let identity = url.resolvingSymlinksInPath().standardizedFileURL.path
                let digest = SHA256.hash(data: Data(identity.utf8)).map { String(format: "%02x", $0) }.joined()
                return try VaultIndex(databaseURL: support.appendingPathComponent(digest + ".sqlite"))
            }.value
            guard generation == current else { return }
            index = opened
            writer = VaultStore(vaultRoot: url, index: opened, fileCoordination: SystemFileCoordination())
        } catch {
            if generation == current { report(error) }
        }
        if index != nil {
            indexingFileCount = try? await Task.detached { try VaultImportScanner.markdownFiles(in: url).count }.value
            guard generation == current else { return }
        }
        guard index != nil else {
            isProcessing = false
            await applyPendingSelection()
            return
        }
        // The first directory walk, on the Mac the event stream's start, runs on the watcher queue;
        // the main actor only awaits it.
        let watcher = VaultWatcher(
            root: url, directoryLimit: watcherDirectoryLimit, ticker: watcherTicker,
            initialScanWillBegin: testingWatcherInitialScan, fileEvents: watcherFileEvents,
            onCoverageChange: { [weak self] count in
                Task { @MainActor [weak self] in
                    guard let self, self.generation == current else { return }
                    self.unwatchedDirectoryCount = count
                }
            },
            onChange: { [weak self] change in
                Task { @MainActor [weak self] in
                    guard let self, self.generation == current else { return }
                    switch change {
                    case .full: await self.refresh()
                    case .directories(let directories): await self.refresh(directories: directories)
                    }
                }
            })
        self.watcher = watcher
        // Sources are in place before the opening refresh scans, so no edit falls between them.
        // `isProcessing` stays up meanwhile: refresh requests queue behind the opening refresh.
        await watcher.waitUntilReady()
        guard generation == current else { return }
        isProcessing = false
        // The explicit opening refresh also serves as the initial foreground refresh.
        watcher.setForeground(foreground, triggerOnActivation: false)
        await refresh()
        guard generation == current else { return }
        indexingFileCount = nil
        if lastUpdated != nil { requiresOnboarding = false }
    }

    /// `directories` (vault-relative) limits the scan to those subtrees; `nil` scans the whole vault.
    func refresh(rebuild: Bool = false, directories: Set<String>? = nil) async {
        guard let index, let root = vaultURL else { return }
        if isProcessing || refreshInFlight {
            queueRefresh(rebuild: rebuild, directories: directories)
            return
        }
        let current = generation
        refreshInFlight = true
        var full = rebuild
        var scope = directories.flatMap { $0.count > VaultChange.fullScanThreshold ? nil : $0 }
        var holdsProcessing = false
        // Skip only after a successful publish; rebuild never skips (see IndexUpdate).
        var allowSkip = lastUpdated != nil && errorText == nil
        // First load keeps the busy indicator up for the whole update.
        if lastUpdated == nil {
            isProcessing = true
            holdsProcessing = true
        }
        repeat {
            pendingRefresh = false
            pendingRebuild = false
            pendingDirectories = nil
            if full || needsFullRefresh { scope = nil }
            let epochAtStart = contentEpoch
            do {
                let result = try await update(
                    index, root, full, scope, entityTypes, allowSkip, skippedPaths, content)
                guard generation == current else { return }
                if scope == nil { needsFullRefresh = false }
                if contentEpoch != epochAtStart {
                    // A write published while Core work was in flight; discard and rescan.
                    allowSkip = false
                    queueRefresh(rebuild: false, directories: scope)
                } else if result.hasChanges {
                    if !holdsProcessing {
                        isProcessing = true
                        holdsProcessing = true
                    }
                    content = result.content
                    counts = result.counts
                    skippedPaths = result.skippedPaths
                    try await reloadRecognition()
                    // A vault opened while recognition loaded owns `lastUpdated` and `errorText`.
                    guard generation == current else { return }
                    lastUpdated = Date()
                    errorText = nil
                    allowSkip = true
                }
            } catch {
                // A vault opened meanwhile owns `isProcessing` and `errorText`; taking the busy
                // flag here would leave it up with no refresh left to clear it.
                guard generation == current else { return }
                if !holdsProcessing {
                    isProcessing = true
                    holdsProcessing = true
                }
                report(error)
                allowSkip = false
                needsFullRefresh = true
            }
            full = pendingRebuild
            scope = pendingDirectories
        } while pendingRefresh && pendingSelection == nil && generation == current
        guard generation == current else { return }
        refreshInFlight = false
        if holdsProcessing { isProcessing = false }
        await applyPendingSelection()
    }

    // MARK: - Unlinked mentions

    /// Plain spellings of one entity in day event and task lines. Reads the vault off the main actor.
    func computeUnlinkedMentions(of entity: KnownEntity) async throws -> [UnlinkedMention] {
        guard let root = vaultURL else { throw VaultStoreError.staleTarget }
        return try await indexQuery(seam: \.testingQueryDidFinish, whenClosed: .stale) {
            try $0.unlinkedMentions(of: entity, vaultRoot: root)
        }
    }

    /// Writes one approved spelling, then publishes the index. A stale line is not written.
    /// `root` is the vault the row was read from: a vault selected since, even while this write
    /// waited its turn, is never written from another vault's row.
    func linkUnlinkedMention(_ mention: UnlinkedMention, to entity: KnownEntity, readFrom root: URL?) async throws {
        try await performEdit(in: root, estimatedPaths: [mention.file]) { writer in
            _ = try await writer.linkingMention(mention, to: entity)
            return [mention.file]
        }
    }

    // MARK: - Meeting cadence

    /// Cadence scalars keyed by file. Files without one of the three fields are absent.
    func personCadences() async throws -> [String: PersonCadence] {
        let fields = try await indexQuery(seam: \.testingQueryDidFinish, whenClosed: .stale) { try $0.cadenceFields() }
        var grouped: [String: [PersonCadenceField]] = [:]
        for field in fields {
            grouped[field.file, default: []].append(
                PersonCadenceField(key: field.key, kind: field.kind, value: field.value))
        }
        return grouped.mapValues(PersonCadence.parse)
    }

    // MARK: - Cadence reminders

    /// People as of `today`: latest encounter on or before that day, plus the indexed cadence.
    func cadenceReminderPeople(today: CalendarDate) async throws -> [CadenceReminderPerson] {
        let cadences = try await personCadences()
        let encounters = try await computeLastEncounters(asOf: today)
        return content.entities.filter { $0.kind == "person" }.map { entity in
            CadenceReminderPerson(
                id: entity.id, name: entity.name, lastDay: encounters[entity.id],
                cadence: cadences[entity.id] ?? .none)
        }
    }

    // MARK: - Weekly review

    /// Source data of the days in the range; counted by the review itself, whose week follows the
    /// device calendar rather than the summary's fixed Monday week.
    func weeklyReviewInput(from: CalendarDate, to: CalendarDate) async throws -> SummaryInput {
        try await indexQuery(seam: \.testingQueryDidFinish, whenClosed: .stale) {
            try $0.summaryInput(from: from, to: to)
        }
    }

    // MARK: - Journal append

    /// Adds text below the day's Journal; no existing byte changes. The lines are text, never
    /// structure (see `VaultStore.appendingJournal`). Blank lines write nothing and create no file.
    /// The text belongs to the vault selected when this is called: a vault selected while the
    /// write waits its turn is not written (`staleTarget`, nothing written).
    func appendToJournal(on day: CalendarDate, lines: [String]) async throws {
        guard lines.contains(where: { !$0.allSatisfy(\.isWhitespace) }) else { return }
        try await performEdit(path: "journal/\(day).md") { writer in
            try await writer.appendingJournal(on: day, lines: lines)
        }
    }

    // MARK: - Graph query

    /// Test seam: runs after the graph query returns, before its generation is checked.
    @ObservationIgnored var testingGraphQueryDidFinish: (@MainActor () async throws -> Void)?

    /// Graph nodes from the read model's entities, link counts queried from the index on demand.
    /// Belongs to this vault generation; with no index open, as with an empty read model, it is empty.
    func computeGraphInput() async throws -> GraphInput {
        let seam: QuerySeam = \.testingGraphQueryDidFinish
        let mentions: GraphMentions? = try await indexQuery(seam: seam, whenClosed: .empty(nil)) {
            try $0.graphMentions(kinds: GraphInput.kinds)
        }
        guard let mentions else { return GraphInput() }
        return GraphInput(entities: content.entities, mentions: mentions)
    }

    // MARK: - Entity timeline query

    /// Test seam: runs after an entity timeline or last-encounter query returns, before its
    /// generation is checked.
    @ObservationIgnored var testingEntityTimelineQueryDidFinish: (@MainActor () async throws -> Void)?

    /// Day-file events and Journal paragraphs linking to `path`, newest day first, queried from the
    /// index on demand. Belongs to this vault generation; with no index open it is empty.
    func computeEntityTimeline(for path: String) async throws -> [EntityTimelineDay] {
        try await indexQuery(seam: \.testingEntityTimelineQueryDidFinish, whenClosed: .empty([])) {
            EntityTimeline.days(from: try $0.entityTimeline(for: path))
        }
    }

    /// Each linked file's latest encounter on or before `day`, counted from the same blocks as the
    /// timeline. Belongs to this vault generation; with no index open it is empty.
    func computeLastEncounters(asOf day: CalendarDate) async throws -> [String: CalendarDate] {
        try await indexQuery(seam: \.testingEntityTimelineQueryDidFinish, whenClosed: .empty([:])) {
            try $0.lastEncounters(asOf: day)
        }
    }

    // MARK: - Edit turn

    /// Test seam: runs once an edit's turn has come, before it checks that its vault is still selected.
    @ObservationIgnored var testingEditTurnDidArrive: (@MainActor () async -> Void)?

    /// Every write's turn: once the write slot is held and any refresh is over, `root` (the vault
    /// selected when the write was asked for) must still be selected. A vault selected meanwhile is
    /// never written: `staleTarget`, before anything is read or written.
    private func awaitEditTurn(in root: URL?) async throws {
        await waitWhileRefreshInFlight()
        await testingEditTurnDidArrive?()
        guard let root, vaultURL == root else { throw VaultStoreError.staleTarget }
    }

    // MARK: - Goal status query

    /// Test seam: runs after the goal-status query returns, before its generation is checked.
    @ObservationIgnored var testingGoalStatusQueryDidFinish: (@MainActor () async throws -> Void)?

    /// Goal status queried from the index on demand. Belongs to this vault generation; with no
    /// index open, as with an empty read model, it is empty.
    func computeGoalStatuses(today: CalendarDate) async throws -> [GoalStatusRow] {
        try await indexQuery(seam: \.testingGoalStatusQueryDidFinish, whenClosed: .empty([])) {
            try $0.goalStatuses(today: today)
        }
    }

    // MARK: - Day queries

    /// Test seam: runs after a day-list or single-day query returns, before its generation is checked.
    @ObservationIgnored var testingDayQueryDidFinish: (@MainActor () async throws -> Void)?

    /// Day files dated `from` through `to` (an end left `nil` is open), newest first: the day list
    /// and the calendar's density. Belongs to this vault generation; with no index open it is empty.
    /// A caller cancelled meanwhile gets `CancellationError`: the detached query runs on, so a
    /// screen's `.task(id:)` replaced by a newer request would otherwise write its older answer
    /// over the newer one.
    func computeDaySummaries(from: CalendarDate? = nil, to: CalendarDate? = nil) async throws -> [DayOverview] {
        try await indexQuery(seam: \.testingDayQueryDidFinish, whenClosed: .empty([])) {
            try $0.daySummaries(from: from, to: to).map(DayOverview.init(entry:))
        }
    }

    /// One day's events and Journal paragraphs and headings in source order; a date without a day
    /// file is empty. Belongs to this vault generation; with no index open it is empty. A caller
    /// cancelled meanwhile gets `CancellationError`, as above.
    func computeDay(on date: CalendarDate) async throws -> DaySummary {
        try await indexQuery(seam: \.testingDayQueryDidFinish, whenClosed: .empty(DaySummary(empty: date))) {
            DaySummary(contents: try $0.day(on: date), date: date)
        }
    }

    // MARK: - Place documents

    /// Place files read for coordinates after every write and refresh, kept while unchanged on disk.
    @ObservationIgnored private var placeDocuments = PlaceDocumentCache()

    /// The disk bytes of one place file: from the cache while the file's signature is unchanged,
    /// otherwise a coordinated read. A failed read is not kept, so the next reload reads again.
    private func placeDocument(
        _ path: String, signature: PlaceDocumentCache.Signature?, from writer: VaultStore
    ) async -> RawDocument? {
        if let signature, let document = placeDocuments.document(at: path, signature: signature) { return document }
        guard let document = try? await writer.document(at: path) else { return nil }
        if let signature { placeDocuments.store(document, at: path, signature: signature) }
        return document
    }

    // MARK: - Task queries

    /// Test seam: runs after a task query returns, before its generation is checked.
    @ObservationIgnored var testingTaskQueryDidFinish: (@MainActor () async throws -> Void)?

    /// Open tasks in `scope` around `today` for the Tasks list (and the entity filter's open work).
    /// Every task query belongs to this vault generation (an answer outliving its vault throws
    /// `staleTarget`) and is empty with no index open. A caller cancelled meanwhile gets
    /// `CancellationError`: the detached query runs on, so a screen's `.task(id:)` replaced by a
    /// newer request would otherwise write its older answer over the newer one.
    func computeTaskGroups(today: CalendarDate, scope: TaskScope = .all) async throws -> TaskRowGroups {
        try await taskQuery(TaskRowGroups()) { TaskRowGroups(try $0.taskGroups(today: today, scope: scope)) }
    }

    /// Done tasks in `scope`, newest completion first, at most `limit`.
    func computeCompletedTasks(limit: Int, scope: TaskScope = .all) async throws -> [TaskRow] {
        try await taskQuery([]) { try $0.completedTasks(limit: limit, scope: scope).map(TaskRow.init(entry:)) }
    }

    /// Every task of the project `name` (any spelling of its key), by file and line.
    func computeProjectTasks(_ name: String) async throws -> [TaskRow] {
        try await taskQuery([]) { try $0.tasks(inProject: name).map(TaskRow.init(entry:)) }
    }

    /// The timeline's tasks in `scope` whose span meets `from` through `to`, and its undated ones.
    func computeTimelineTasks(
        from: CalendarDate, to: CalendarDate, today: CalendarDate, scope: TaskScope = .all
    ) async throws -> [TaskRow] {
        try await taskQuery([]) {
            try $0.timelineTasks(from: from, to: to, today: today, scope: scope).map(TaskRow.init(entry:))
        }
    }

    /// The board's tasks in `scope`: open ones, ones done from `from` through `to`, cancelled when asked.
    func computeBoardTasks(
        doneFrom from: CalendarDate, to: CalendarDate, includeCancelled: Bool, scope: TaskScope = .all
    ) async throws -> [TaskRow] {
        try await taskQuery([]) {
            try $0.boardTasks(doneFrom: from, to: to, includeCancelled: includeCancelled, scope: scope)
                .map(TaskRow.init(entry:))
        }
    }

    /// Every task a day page (and the close-day flow) may list for `day`, in the read model's order.
    func computeDayTasks(on day: CalendarDate) async throws -> [TaskRow] {
        try await taskQuery([]) { try $0.dayTasks(on: day).map(TaskRow.init(entry:)).sorted(by: TaskRow.sourceOrder) }
    }

    /// Open tasks due by `last` or written undated from `first` through `last` (the weekly review).
    func computeOpenTasks(dueBy last: CalendarDate, orWrittenFrom first: CalendarDate) async throws -> [TaskRow] {
        try await taskQuery([]) { try $0.openTasks(dueBy: last, orWrittenFrom: first).map(TaskRow.init(entry:)) }
    }

    /// The task a screen selected, as the index has it now; nil once it is gone.
    func computeTask(id: String) async throws -> TaskRow? {
        try await taskQuery(nil) { try $0.task(id: id).map(TaskRow.init(entry:)) }
    }

    /// Open tasks per project key (``VaultIndex/projectKey(_:)``).
    func computeOpenTaskCounts() async throws -> [String: Int] {
        try await taskQuery([:]) { index in
            var counts: [String: Int] = [:]
            for (project, count) in try index.openTaskCounts() {
                counts[VaultIndex.projectKey(project), default: 0] += count
            }
            return counts
        }
    }

    private func taskQuery<Value: Sendable>(
        _ empty: Value, _ body: @escaping @Sendable (VaultIndex) throws -> Value
    ) async throws -> Value {
        try await indexQuery(seam: \.testingTaskQueryDidFinish, whenClosed: .empty(empty), body)
    }

    // MARK: - Stale reloads and cancelled queries

    /// Test seam: runs after an on-demand query without a seam of its own returns (summary,
    /// on-this-day, important dates, day backlinks, unlinked mentions, search, goal history,
    /// cadences, weekly review input, task flow, year calendar, a document read), before its
    /// generation is checked. Throwing stands for a failed query. Like every on-demand query here,
    /// a caller cancelled meanwhile gets `CancellationError` instead of the answer.
    @ObservationIgnored var testingQueryDidFinish: (@MainActor () async throws -> Void)?

    /// Test seam: runs once recognition has loaded, before it checks that its vault is still open.
    /// Throwing stands for a failed reload.
    @ObservationIgnored var testingRecognitionReloadDidLoad: (@MainActor () async throws -> Void)?
}

/// Place documents, each kept with the file signature taken before it was read. A file changed
/// after its signature was taken is read again next time; it is never served stale. Device and
/// inode are part of the signature, so another vault's file or a file moved onto the path misses.
struct PlaceDocumentCache {
    /// Identity, size and change times of a file; any write, replacement or move changes one of them.
    struct Signature: Equatable, Sendable {
        let device: Int64
        let inode: UInt64
        let size: Int64
        let modified: [Int]
        let changed: [Int]

        init?(_ url: URL) {
            var info = stat()
            guard url.withUnsafeFileSystemRepresentation({ $0.map { stat($0, &info) } ?? -1 }) == 0 else {
                return nil
            }
            device = Int64(info.st_dev)
            inode = UInt64(info.st_ino)
            size = Int64(info.st_size)
            modified = [Int(info.st_mtimespec.tv_sec), Int(info.st_mtimespec.tv_nsec)]
            changed = [Int(info.st_ctimespec.tv_sec), Int(info.st_ctimespec.tv_nsec)]
        }
    }

    private var entries: [String: (signature: Signature, document: RawDocument)] = [:]

    /// Signatures of the place files under `root`; a file that cannot be examined has none.
    static func signatures(of entities: [KnownEntity], in root: URL?) -> [String: Signature] {
        guard let root else { return [:] }
        var result: [String: Signature] = [:]
        for entity in entities where entity.kind == .place {
            result[entity.file] = Signature(root.appendingPathComponent(entity.file))
        }
        return result
    }

    /// Drops every file that is no longer a place with a signature.
    mutating func keep(only paths: Dictionary<String, Signature>.Keys) {
        entries = entries.filter { paths.contains($0.key) }
    }

    func document(at path: String, signature: Signature) -> RawDocument? {
        guard let entry = entries[path], entry.signature == signature else { return nil }
        return entry.document
    }

    mutating func store(_ document: RawDocument, at path: String, signature: Signature) {
        entries[path] = (signature, document)
    }
}

// MARK: - Project names and notification days

extension IndexStore {
    /// One name per project across every task (`VaultIndex.taskProjects()`): the Mac sidebar, the
    /// board and timeline project columns, the filter menu and the quick entry's suggestions.
    /// A task query: generation, cancellation and its test seam as above.
    func computeProjects() async throws -> [String] {
        try await taskQuery([]) { try $0.taskProjects() }
    }

    /// What the notification planner reads for the days `first` through `last`: open tasks per
    /// due day through `last`, the rows of those due within the days, and the days whose file has
    /// events or Journal paragraphs and headings. A task query, as above.
    func computeNotificationDays(from first: CalendarDate, through last: CalendarDate) async throws
        -> NotificationVaultDays
    {
        try await taskQuery(NotificationVaultDays()) { index in
            var days = NotificationVaultDays()
            let groups = try index.taskGroups(today: first)
            for entry in groups.overdue + groups.today + groups.upcoming {
                guard let due = entry.block.dueDate.flatMap(CalendarDate.init), due <= last else { continue }
                days.openTaskCounts[due, default: 0] += 1
                if due >= first { days.dueTasks.append(TaskRow(entry: entry)) }
            }
            days.writtenDays = Set(
                try index.daySummaries(from: first, to: last).filter { $0.eventCount > 0 || $0.journalCount > 0 }
                    .map(\.date))
            return days
        }
    }
}

// MARK: - Synced folder and copy files

extension IndexStore {
    /// The sync service that holds the open vault (`SyncedFolderKind`); `nil` for a local folder.
    var syncedFolder: SyncedFolderKind? { vaultURL.flatMap(SyncedFolderKind.detect(url:)) }

    /// Copies the vault keeps beside their originals, for Diagnostics: day copies under `journal/`,
    /// read from disk because they are never indexed, then entity copies from the index. Nothing
    /// is merged or moved. A task query, as above. An unreadable `journal/` (a symlink, no
    /// permission) hides only the day copies, not the entity copies.
    func computeCopyFiles() async throws -> [CopyFile] {
        guard let root = vaultURL else { return [] }
        return try await taskQuery([]) { index in
            let dayCopies = (try? VaultIndex.dayCopies(vaultRoot: root)) ?? []
            return try dayCopies + index.entityCopies()
        }
    }
}

// MARK: - Year writing calendar

extension IndexStore {
    /// The Özetler year map. It reads only the day rows the year's "Yazılan gün" counts, so the
    /// map's counter and the number agree. Belongs to this vault generation; with no index open it is empty.
    func computeYearWritingCalendar(year: Int, today: CalendarDate?) async throws -> YearWritingCalendar {
        let empty = YearWritingCalendar.compute(days: [], year: year, today: today)
        guard let start = CalendarDate(year: year, month: 1, day: 1),
            let end = CalendarDate(year: year, month: 12, day: 31)
        else { return empty }
        return try await indexQuery(seam: \.testingQueryDidFinish, whenClosed: .empty(empty)) {
            YearWritingCalendar.compute(days: try $0.summaryDays(from: start, to: end), year: year, today: today)
        }
    }
}

// MARK: - Definition deletion

extension IndexStore {
    func deleteEntity(path: String) async throws {
        try await deleteDefinition(path: path) { try await $0.deletingEntity(path: path) }
    }

    func deleteGoal(path: String) async throws {
        try await deleteDefinition(path: path) { try await $0.deletingGoal(path: path) }
    }

    private func deleteDefinition(
        path: String, operation: (VaultStore) async throws -> Void
    ) async throws {
        let root = vaultURL
        try await withWriteSlot {
            try await awaitEditTurn(in: root)
            guard canAddEvent, let writer, let index else { throw VaultStoreError.staleTarget }
            isProcessing = true
            isWriting = true
            do {
                do {
                    try await operation(writer)
                } catch VaultStoreError.indexUpdateFailed {
                    // The file is gone. Reconcile from disk; never offer a second deletion.
                    queueRefresh(rebuild: true, directories: nil)
                    entryErrorText = String(localized: "Dosya silindi, indeks güncellenemedi.")
                }
                do {
                    try await publishAfterWrite(from: index, changedPaths: [], deletedPaths: [path])
                } catch {
                    queueRefresh(rebuild: true, directories: nil)
                    entryErrorText = String(localized: "Dosya silindi, indeks güncellenemedi.")
                }
                await finishEntityWrite()
            } catch {
                await finishEntityWrite()
                throw error
            }
        }
    }
}

// MARK: - Task flow inventory

extension IndexStore {
    /// The task flow needs all historical tasks, without day, mention or goal queries.
    func summaryTasks() async throws -> [SummaryInput.Task] {
        try await indexQuery(seam: \.testingQueryDidFinish, whenClosed: .stale) {
            try $0.summaryTasks()
        }
    }
}

// MARK: - Entity type gallery

extension IndexStore {
    /// A new type and its starter template (`VaultStore.creatingEntityType`). When only the
    /// template could not be written, the saved definition is still published, then the error is
    /// thrown.
    func createEntityType(_ type: EntityTypeDefinition) async throws {
        var templateFailure: EntityTypeTemplateError?
        try await performEdit(path: ".app/types.json") { writer in
            do {
                try await writer.creatingEntityType(type)
            } catch let error as EntityTypeTemplateError {
                templateFailure = error
            }
        }
        if let templateFailure { throw templateFailure }
    }
}

// MARK: - Goal definitions, reserved keys, goal logs and notification goals

extension IndexStore {
    /// Valid goal definitions in the goal list's name order, each with the file its place link
    /// resolves to (`VaultIndex.goalDefinitionsByName()`). A task query: generation, cancellation
    /// and its test seam as above.
    func computeGoalDefinitions() async throws -> [GoalDefinitionRow] {
        try await taskQuery([]) { try $0.goalDefinitionsByName() }
    }

    /// Every goal key a definition holds, valid or not: the new-goal form's key preview. A task query, as above.
    func computeReservedGoalKeys() async throws -> Set<String> {
        try await taskQuery([]) { try $0.reservedGoalKeys() }
    }

    /// Goal logs dated `from` through `through` by key, in file order; of `keys` only, when given.
    /// A task query, as above.
    func computeGoalLogs(
        from: CalendarDate, through: CalendarDate, keys: Set<String>? = nil
    ) async throws -> [String: [GoalLog]] {
        try await taskQuery([:]) { try $0.goalLogsByKey(from: from, through: through, keys: keys) }
    }

    /// What the daily goal reminder reads for the days `first` through `last`: the daily
    /// definitions and their logs on those days. A task query, as above.
    func computeNotificationGoals(from first: CalendarDate, through last: CalendarDate) async throws
        -> NotificationGoals
    {
        try await taskQuery(NotificationGoals()) { try $0.notificationGoals(from: first, through: last) }
    }
}

// MARK: - Sync conflicts

extension IndexStore {
    /// Files iCloud keeps unresolved conflicting versions of, for Diagnostics: every indexed file
    /// and every day copy is asked through `ConflictVersionSource`. Only an iCloud Drive vault is
    /// asked; any other vault returns nothing without touching a file. Nothing is merged, kept or
    /// removed. A task query: it belongs to this vault generation.
    func computeConflictedFiles() async throws -> [ConflictedFile] {
        guard let root = vaultURL, syncedFolder == .iCloudDrive else { return [] }
        let source = conflictVersions
        return try await taskQuery([]) { index in
            let dayCopies = ((try? VaultIndex.dayCopies(vaultRoot: root)) ?? []).map(\.copy)
            var files: [ConflictedFile] = []
            for path in try index.files().map(\.path) + dayCopies {
                let versions = source.unresolvedConflicts(at: root.appendingPathComponent(path))
                if !versions.isEmpty { files.append(ConflictedFile(path: path, versions: versions)) }
            }
            return ConflictedFile.sorted(files)
        }
    }

    /// The versions a day copy merge saved under `conflicts/`, read from disk because they are
    /// never indexed (`VaultIndex.conflictCopies`). Any vault, synced or not. A task query.
    func computeConflictCopies() async throws -> [CopyFile] {
        guard let root = vaultURL else { return [] }
        return try await taskQuery([]) { _ in try VaultIndex.conflictCopies(vaultRoot: root) }
    }
}

// MARK: - Directory refresh queue

extension IndexStore {
    /// Joins a refresh request with the pending one. A whole-vault request absorbs directory
    /// lists, and too many directories become a whole-vault request.
    fileprivate func queueRefresh(rebuild: Bool, directories: Set<String>?) {
        let request: VaultChange = directories.map { .directories($0) } ?? .full
        let pending: VaultChange? =
            pendingRefresh ? (pendingDirectories.map { .directories($0) } ?? .full) : nil
        switch pending.map({ $0.merging(request) }) ?? request {
        case .full: pendingDirectories = nil
        case .directories(let merged): pendingDirectories = merged
        }
        pendingRebuild = pendingRebuild || rebuild
        pendingRefresh = true
    }
}

// MARK: - Query contract

extension IndexStore {
    /// A query test seam: runs once the read returns, before its generation is checked.
    typealias QuerySeam = KeyPath<IndexStore, (@MainActor () async throws -> Void)?>

    /// The contract of every on-demand read a screen or service awaits (architecture.md "Sorgu
    /// kalıbı"): `read` belongs to the vault generation open when it starts. Once it returns, the
    /// test seam runs; then a vault opened meanwhile throws `staleTarget` and a caller cancelled
    /// meanwhile gets `CancellationError`. The read itself runs on: the checks only keep an older
    /// answer from landing over a newer one, or over another vault's screen.
    private func answer<Value>(seam: QuerySeam, _ read: () async throws -> Value) async throws -> Value {
        let current = generation
        let value = try await read()
        try await self[keyPath: seam]?()
        guard generation == current else { throw VaultStoreError.staleTarget }
        try Task.checkCancellation()
        return value
    }

    /// An index query on a background task, under `answer`'s checks. With no index open the
    /// answer is `whenClosed`: an empty value, or `staleTarget` where the query has no empty answer.
    private func indexQuery<Value: Sendable>(
        seam: QuerySeam, whenClosed: ClosedIndexAnswer<Value>,
        _ body: @escaping @Sendable (VaultIndex) throws -> Value
    ) async throws -> Value {
        guard let index else {
            switch whenClosed {
            case .empty(let value): return value
            case .stale: throw VaultStoreError.staleTarget
            }
        }
        return try await answer(seam: seam) { try await Task.detached { try body(index) }.value }
    }
}

/// What an index query answers while no index is open.
private enum ClosedIndexAnswer<Value> {
    /// The query's empty answer: no rows, no days, no tasks.
    case empty(Value)
    /// `staleTarget`: the query has no empty answer.
    case stale
}
