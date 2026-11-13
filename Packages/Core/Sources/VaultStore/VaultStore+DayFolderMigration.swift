import Foundation
import VaultFormat
import VaultIndex

/// What one run of the day folder migration did (`vault-format.md`, "Eski adlar ve geçiş").
public struct DayFolderMigrationOutcome: Sendable, Equatable {
    /// Day files now under `diary/` with their day's name, such as `diary/2026-10-02.md`.
    public var moved: [String] = []
    /// Day copies written because `diary/` already held a different day file, such as
    /// `diary/2026-10-02 2.md`. The day copy merge or Diagnostics takes them up.
    public var copies: [String] = []
    /// Legacy files a resumed run only removed: `diary/` already held their migrated bytes.
    public var resumed: [String] = []
    /// Legacy day files that wait for iCloud's download; the next run moves them.
    public var waiting: [String] = []
    /// Legacy day files left in place after an error; the next run tries them again.
    public var failed: [String] = []
    /// Other entries of the legacy folder, never moved: notes, subfolders, names that are no day.
    public var leftInPlace: [String] = []
    /// Whether the legacy folder ended up empty and was removed.
    public var removedLegacyFolder = false

    public init() {}

    /// Whether the legacy folder was there and this run had anything to report.
    public var isEmpty: Bool {
        moved.isEmpty && copies.isEmpty && resumed.isEmpty && waiting.isEmpty && failed.isEmpty
            && leftInPlace.isEmpty && !removedLegacyFolder
    }
}

/// One legacy day file or day copy and where its day lives under `diary/`.
private struct LegacyDaySource {
    let path: String
    let url: URL
    let day: CalendarDate
}

/// Where one source goes: a free name under `diary/`, or an existing file that already holds it.
private enum LegacyDayTarget {
    case free(path: String, url: URL, isCopy: Bool)
    case done(path: String, url: URL)
}

extension VaultStore {
    /// Moves the day files and day copies of the legacy day folder to `diary/`, as `vault-format.md`
    /// describes under "Eski adlar ve geçiş".
    ///
    /// Only the exact legacy spelling is read; a case variant stays. Each file is one coordination
    /// boundary: a free target is claimed with `.move(source → target)`, a target that already holds
    /// the migrated bytes with `.merge(source into target)`. The migrated bytes differ from the file
    /// only in the diary heading's name and the day `type` value (`migratingLegacyDayNames`). A file
    /// that needs no change is moved as it is; any other is written exclusively, given the source's
    /// modification date and only then is the source removed. A target that exists with other bytes
    /// is never replaced: the source becomes the first free day copy of its day. A run that stopped
    /// half way therefore resumes: a target holding the migrated bytes only loses its source. A file
    /// waiting for download is skipped. The legacy folder is removed only when it is empty. The
    /// index learns every touched path once, after the files.
    public func migratingLegacyDayFolder() async throws -> DayFolderMigrationOutcome {
        try await perform { try self.migrateLegacyDayFolder() }
    }

    nonisolated func migrateLegacyDayFolder() throws -> DayFolderMigrationOutcome {
        var outcome = DayFolderMigrationOutcome()
        let legacy = LegacyVaultNames.dayFolder
        // Only the exact spelling: a case-insensitive volume would open a case variant as well.
        guard (try? FileManager.default.contentsOfDirectory(atPath: root.path))?.contains(legacy) == true else {
            return outcome
        }
        let folder = root.appendingPathComponent(legacy, isDirectory: true)
        let values = try folder.resourceValues(forKeys: [.isDirectoryKey, .isSymbolicLinkKey])
        guard values.isSymbolicLink != true, values.isDirectory == true else { return outcome }
        try ensureReservedFolderCase(forCanonicalFolder: VaultLayout.dayFolder)
        let (sources, waiting, others) = try legacyDaySources(in: folder)
        outcome.waiting = waiting
        outcome.leftInPlace = others
        var touched: [String] = []
        // Names under `diary/`, listed once and kept in step with this run's own writes.
        let diary = root.appendingPathComponent(VaultLayout.dayFolder, isDirectory: true)
        func listing() -> Set<String> { Set((try? FileManager.default.contentsOfDirectory(atPath: diary.path)) ?? []) }
        var names = listing()
        for source in sources {
            do {
                switch try migrateLegacyDay(source, names: &names) {
                case .free(let path, _, let isCopy):
                    if isCopy { outcome.copies.append(path) } else { outcome.moved.append(path) }
                    touched += [source.path, path]
                case .done(let path, _):
                    outcome.resumed.append(source.path)
                    touched += [source.path, path]
                }
            } catch VaultStoreError.awaitingDownload {
                outcome.waiting.append(source.path)
                names = listing()
            } catch {
                outcome.failed.append(source.path)
                names = listing()
            }
        }
        if (try? FileManager.default.contentsOfDirectory(atPath: folder.path))?.isEmpty == true {
            try? fileCoordination.coordinate(.delete(folder)) { _ in
                // Something may have arrived since the listing; only an empty folder goes.
                guard (try FileManager.default.contentsOfDirectory(atPath: folder.path)).isEmpty else { return }
                try removeFile(folder)
                outcome.removedLegacyFolder = true
            }
        }
        if !touched.isEmpty {
            do {
                try index.update(paths: Set(touched), vaultRoot: root)
            } catch {
                throw VaultStoreError.indexUpdateFailed(path: touched[0], underlying: error)
            }
        }
        return outcome
    }

    /// The legacy folder's day files in name order, then its day copies in merge order; the day
    /// names that wait for a download; and every other entry.
    private nonisolated func legacyDaySources(in folder: URL) throws -> (
        sources: [LegacyDaySource], waiting: [String], others: [String]
    ) {
        let legacy = LegacyVaultNames.dayFolder
        let names = try FileManager.default.contentsOfDirectory(atPath: folder.path)
            .sorted { $0.utf8.lexicographicallyPrecedes($1.utf8) }
        let present = Set(names)
        var days: [LegacyDaySource] = []
        var copies: [String: LegacyDaySource] = [:]
        var waiting: [String] = []
        var others: [String] = []
        for name in names {
            let path = legacy + "/" + name
            let url = folder.appendingPathComponent(name)
            if let original = PlaceholderName.originalName(ofPlaceholder: name) {
                let originalPath = legacy + "/" + original
                if !present.contains(original),
                    VaultLayout.day(ofDayPath: originalPath) != nil || DayCopyName.isLegacyDayCopy(path: originalPath)
                {
                    waiting.append(originalPath)
                    continue
                }
                others.append(path)
                continue
            }
            let values = try? url.resourceValues(forKeys: [.isRegularFileKey, .isSymbolicLinkKey])
            guard values?.isSymbolicLink != true, values?.isRegularFile == true else {
                others.append(path)
                continue
            }
            if let day = VaultLayout.day(ofDayPath: path) {
                days.append(LegacyDaySource(path: path, url: url, day: day))
            } else if let day = DayCopyName.day(ofLegacyCopy: path) {
                // Keyed by the name the copy would have under `diary/`, to reuse the merge order.
                copies[VaultLayout.dayFolder + "/" + name] = LegacyDaySource(path: path, url: url, day: day)
            } else {
                others.append(path)
            }
        }
        let ordered = DayCopyName.copies(in: copies.keys).compactMap { copies[$0] }
        return (days + ordered, waiting, others)
    }

    /// Moves one source under one coordination boundary and reports where it went.
    private nonisolated func migrateLegacyDay(_ source: LegacyDaySource, names: inout Set<String>) throws
        -> LegacyDayTarget
    {
        let migrated = Data(RawDocument(bytes: try readFile(source.url)).migratingLegacyDayNames().serialized())
        let target = try legacyDayTarget(for: source, migrated: migrated, names: names)
        switch target {
        case .done(_, let url):
            try fileCoordination.coordinate(.merge(source: source.url, into: url)) { _ in
                guard FileManager.default.fileExists(atPath: source.url.path) else { return }
                // The target must still hold the source's migrated bytes, read inside the boundary.
                guard try readFile(url) == migrated,
                    Data(RawDocument(bytes: try readFile(source.url)).migratingLegacyDayNames().serialized())
                        == migrated
                else { throw VaultStoreError.staleTarget }
                try setModificationDate(of: url, from: source.url)
                try removeFile(source.url)
            }
        case .free(_, let url, _):
            try fileCoordination.coordinate(.move(source: source.url, destination: url)) { access in
                guard FileManager.default.fileExists(atPath: source.url.path) else {
                    throw VaultStoreError.staleTarget
                }
                // Claimed from outside the boundary: the name must still be free.
                if FileManager.default.fileExists(atPath: url.path) { throw VaultStoreError.staleTarget }
                try rejectPendingDownload(at: url, path: VaultLayout.dayFolder + "/" + url.lastPathComponent)
                let original = try readFile(source.url)
                let bytes = Data(RawDocument(bytes: [UInt8](original)).migratingLegacyDayNames().serialized())
                access.itemWillMove(from: source.url, to: url)
                if bytes == original {
                    try moveFile(source.url, url)
                } else {
                    try atomicWrite(bytes, to: url, exclusive: true)
                    try setModificationDate(of: url, from: source.url)
                    try removeFile(source.url)
                }
                access.itemDidMove(from: source.url, to: url)
            }
            names.insert(url.lastPathComponent)
        }
        return target
    }

    /// The day file when its name is free; else the target or a day copy that already holds the
    /// migrated bytes; else the first free day copy name. A name with a placeholder sibling is
    /// neither free nor read.
    private nonisolated func legacyDayTarget(for source: LegacyDaySource, migrated: Data, names: Set<String>) throws
        -> LegacyDayTarget
    {
        let dayPath = VaultLayout.dayPath(source.day)
        let dayURL = try checkedURL(dayPath, writing: true)
        let directory = dayURL.deletingLastPathComponent()
        for number in 1...1000 {
            let name = source.day.description + (number == 1 ? "" : " " + String(number)) + ".md"
            let url = directory.appendingPathComponent(name)
            let path = VaultLayout.dayFolder + "/" + name
            if names.contains(name) {
                if (try? readFile(url)) == migrated { return .done(path: path, url: url) }
                continue
            }
            if names.contains(PlaceholderName.placeholderName(for: name)) { continue }
            return .free(path: path, url: url, isCopy: number > 1)
        }
        throw VaultStoreError.nameTaken
    }

    /// Gives the target the source's exact modification date, which a day copy merge compares.
    private nonisolated func setModificationDate(of target: URL, from source: URL) throws {
        let attributes = try FileManager.default.attributesOfItem(atPath: source.path)
        guard let date = attributes[.modificationDate] as? Date else { return }
        try FileManager.default.setAttributes([.modificationDate: date], ofItemAtPath: target.path)
    }
}
