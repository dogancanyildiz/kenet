import Foundation
import VaultFormat
import VaultIndex

/// What merging one day copy into its day file did.
public struct DayCopyMergeOutcome: Sendable, Equatable {
    public enum Kind: Sendable, Equatable {
        /// The day file was missing; the copy took its name.
        case renamed
        /// The two versions were byte for byte the same; only the copy was removed.
        case identical
        /// The versions were merged into the day file and the copy was removed.
        case merged
    }

    public let kind: Kind
    /// The day file that now holds both versions, such as `journal/2026-10-02.md`.
    public let dayPath: String
    /// Where each preserved version lives under `conflicts/`, the older version first. A version
    /// already saved there byte for byte by an earlier, interrupted merge is reported, not rewritten.
    public let conflictPaths: [String]
    /// The merge gave up and kept the newer version, preserving the older one (`MergeResult.fellBack`).
    public let fellBack: Bool
}

/// The steps of a day copy merge that change the disk, in order; a test seam for failures.
enum DayCopyMergeStep: Sendable, Equatable {
    case conflictCopy(String)
    case dayFile
}

extension VaultStore {
    /// Merges an iCloud day copy (`journal/2026-10-02 2.md`) into its day file, as `vault-format.md`
    /// describes under "Senkronizasyon çakışması".
    ///
    /// Everything runs in one `.move(copy → day)` coordination boundary, the only intent that holds
    /// both files for writing: both are read, preserved versions are created exclusively under
    /// `conflicts/`, the day file is replaced atomically, the copy is removed last and the index is
    /// updated. A missing day file is not created: the copy is moved to its name. A failure before
    /// the day file is replaced removes the conflict copies this call created, so neither version
    /// changes. If only removing the copy fails, the day file already holds the merge; calling again
    /// merges to the same content and reuses the saved conflict copies.
    public func mergingDayCopy(_ copyPath: String) async throws -> DayCopyMergeOutcome {
        try await perform { try self.mergeDayCopy(copyPath) }
    }

    nonisolated func mergeDayCopy(_ copyPath: String) throws -> DayCopyMergeOutcome {
        guard let dayPath = DayCopyName.dayPath(ofCopy: copyPath), let day = DayCopyName.day(ofCopy: copyPath) else {
            throw VaultStoreError.invalidPath
        }
        let copyURL = try checkedURL(copyPath, writing: true)
        let dayURL = try checkedURL(dayPath, writing: true)
        return try fileCoordination.coordinate(.move(source: copyURL, destination: dayURL)) { access in
            guard FileManager.default.fileExists(atPath: copyURL.path) else {
                try rejectPendingDownload(at: copyURL, path: copyPath)
                throw VaultStoreError.staleTarget
            }
            let copy = MergeVersion(
                bytes: Array(try readFile(copyURL)), modificationTime: try modificationTime(copyURL))
            guard FileManager.default.fileExists(atPath: dayURL.path) else {
                try rejectPendingDownload(at: dayURL, path: dayPath)
                try dayCopyStep(.dayFile)
                access.itemWillMove(from: copyURL, to: dayURL)
                try moveFile(copyURL, dayURL)
                access.itemDidMove(from: copyURL, to: dayURL)
                try updateIndexAfterDayCopy(dayPath: dayPath, copyPath: copyPath)
                return DayCopyMergeOutcome(kind: .renamed, dayPath: dayPath, conflictPaths: [], fellBack: false)
            }
            let current = MergeVersion(
                bytes: Array(try readFile(dayURL)), modificationTime: try modificationTime(dayURL))
            let merge = ConflictMerge.merge(current, copy)
            let saved = try preserveConflictVersions(merge.preserved, day: day)
            do {
                if merge.bytes != current.bytes {
                    try dayCopyStep(.dayFile)
                    try atomicWrite(Data(merge.bytes), to: dayURL, exclusive: false)
                }
            } catch {
                saved.rollBack()
                throw error
            }
            do {
                try removeFile(copyURL)
            } catch {
                if merge.bytes == current.bytes {
                    saved.rollBack()
                } else {
                    // The day file already holds both versions; keep the index in step with it.
                    try updateIndexAfterDayCopy(dayPath: dayPath, copyPath: copyPath)
                }
                throw error
            }
            try updateIndexAfterDayCopy(dayPath: dayPath, copyPath: copyPath)
            return DayCopyMergeOutcome(
                kind: current.bytes == copy.bytes ? .identical : .merged, dayPath: dayPath, conflictPaths: saved.paths,
                fellBack: merge.fellBack)
        }
    }

    /// Whole seconds since 1970 in UTC, the unit of the conflict copy name.
    private nonisolated func modificationTime(_ url: URL) throws -> Int {
        let attributes = try FileManager.default.attributesOfItem(atPath: url.path)
        guard let date = attributes[.modificationDate] as? Date else { throw CocoaError(.fileReadUnknown) }
        return Int(date.timeIntervalSince1970.rounded(.down))
    }

    private nonisolated func updateIndexAfterDayCopy(dayPath: String, copyPath: String) throws {
        do {
            try index.update(paths: [dayPath, copyPath], vaultRoot: root)
        } catch {
            throw VaultStoreError.indexUpdateFailed(path: dayPath, underlying: error)
        }
    }

    /// Writes each version to `conflicts/<day> (conflict <UTC time>).md`, numbering the name
    /// (`… 2).md`) when it is taken and never replacing another file.
    private nonisolated func preserveConflictVersions(_ versions: [MergeVersion], day: CalendarDate) throws
        -> SavedConflicts
    {
        var saved = SavedConflicts()
        guard !versions.isEmpty else { return saved }
        do {
            let directory = root.appendingPathComponent("conflicts")
            if (try? directory.resourceValues(forKeys: [.isSymbolicLinkKey]).isSymbolicLink) == true {
                throw VaultStoreError.invalidPath
            }
            try ensureReservedFolderCase(forCanonicalFolder: "conflicts")
            if !FileManager.default.fileExists(atPath: directory.path) { saved.createdDirectory = directory }
            for version in versions {
                saved.paths.append(try preserve(version, day: day, in: directory, saved: &saved))
            }
            return saved
        } catch {
            saved.rollBack()
            throw error
        }
    }

    private nonisolated func preserve(
        _ version: MergeVersion, day: CalendarDate, in directory: URL, saved: inout SavedConflicts
    ) throws -> String {
        let stem = day.description + " (conflict " + ConflictStamp.utc(version.modificationTime)
        let names = try? FileManager.default.contentsOfDirectory(atPath: directory.path)
        for number in 1...1000 {
            let name = stem + (number == 1 ? "" : " " + String(number)) + ").md"
            let url = directory.appendingPathComponent(name)
            if FileManager.default.fileExists(atPath: url.path) {
                if (try? Data(contentsOf: url)) == Data(version.bytes) { return "conflicts/" + name }
                continue
            }
            if names?.contains(PlaceholderName.placeholderName(for: name)) == true { continue }
            try dayCopyStep(.conflictCopy("conflicts/" + name))
            do {
                try atomicWrite(Data(version.bytes), to: url, exclusive: true)
            } catch VaultStoreError.nameTaken {
                continue
            }
            saved.created.append(url)
            return "conflicts/" + name
        }
        throw VaultStoreError.nameTaken
    }
}

/// Conflict copies one merge created, so that a failure before the day file is replaced can
/// remove them again. Copies that already existed are never removed.
private struct SavedConflicts {
    var paths: [String] = []
    var created: [URL] = []
    var createdDirectory: URL?

    func rollBack() {
        for url in created { try? FileManager.default.removeItem(at: url) }
        if let createdDirectory,
            (try? FileManager.default.contentsOfDirectory(atPath: createdDirectory.path))?
                .isEmpty == true
        {
            try? FileManager.default.removeItem(at: createdDirectory)
        }
    }
}

/// `YYYYMMDDTHHMMSSZ` for whole seconds since 1970, computed without a calendar or locale.
enum ConflictStamp {
    static func utc(_ seconds: Int) -> String {
        let days = seconds >= 0 ? seconds / 86_400 : -((-seconds + 86_399) / 86_400)
        let time = seconds - days * 86_400
        // Days to a proleptic Gregorian date (H. Hinnant, "chrono-Compatible Low-Level Date Algorithms").
        let shifted = days + 719_468
        let era = (shifted >= 0 ? shifted : shifted - 146_096) / 146_097
        let dayOfEra = shifted - era * 146_097
        let yearOfEra = (dayOfEra - dayOfEra / 1_460 + dayOfEra / 36_524 - dayOfEra / 146_096) / 365
        let dayOfYear = dayOfEra - (365 * yearOfEra + yearOfEra / 4 - yearOfEra / 100)
        let monthIndex = (5 * dayOfYear + 2) / 153
        let day = dayOfYear - (153 * monthIndex + 2) / 5 + 1
        let month = monthIndex < 10 ? monthIndex + 3 : monthIndex - 9
        let year = yearOfEra + era * 400 + (month <= 2 ? 1 : 0)
        return padded(year, 4) + padded(month, 2) + padded(day, 2) + "T" + padded(time / 3_600, 2)
            + padded(time % 3_600 / 60, 2) + padded(time % 60, 2) + "Z"
    }

    private static func padded(_ value: Int, _ width: Int) -> String {
        let text = String(value)
        return String(repeating: "0", count: max(0, width - text.count)) + text
    }
}
