import Foundation
import VaultFormat
import VaultStore

// MARK: - Day folder migration

extension IndexStore {
    /// After a refresh: moves the day files of a vault written before 2026-11-13 from the legacy day
    /// folder to `diary/` (`VaultStore.migratingLegacyDayFolder`, `vault-format.md` "Eski adlar ve
    /// geçiş"). It runs in any writable vault, local or iCloud, as one write through the write queue.
    /// The run starts only when the legacy folder's listing differs from the one the last run of
    /// this vault saw: a folder left with notes or with files waiting for a download does not start
    /// a run after every refresh, while a file another device adds starts one. Opening the vault
    /// again starts over, so a stopped run resumes there.
    func scheduleDayFolderMigration() {
        guard canAddEvent, let root = vaultURL, sync.root == root, sync.folderMigrationTask == nil,
            let listing = Self.legacyDayFolderListing(in: root), listing != sync.migratedLegacyListing
        else { return }
        sync.migratedLegacyListing = listing
        let epoch = sync.epoch
        sync.folderMigrationTask = Task { [weak self] in
            await self?.migrateDayFolder(in: root, epoch: epoch)
        }
    }

    /// Test seam: returns once no day folder migration is running.
    func waitForDayFolderMigration() async {
        while let task = sync.folderMigrationTask {
            await task.value
            if sync.folderMigrationTask == task { sync.folderMigrationTask = nil }
        }
    }

    /// The names under the exact legacy day folder in byte order, or `nil` when the vault root has
    /// no such folder. A case variant of its name never counts.
    nonisolated static func legacyDayFolderListing(in root: URL) -> [String]? {
        let manager = FileManager.default
        guard (try? manager.contentsOfDirectory(atPath: root.path))?.contains(LegacyVaultNames.dayFolder) == true
        else { return nil }
        let folder = root.appendingPathComponent(LegacyVaultNames.dayFolder, isDirectory: true)
        let values = try? folder.resourceValues(forKeys: [.isDirectoryKey, .isSymbolicLinkKey])
        guard values?.isSymbolicLink != true, values?.isDirectory == true else { return nil }
        return ((try? manager.contentsOfDirectory(atPath: folder.path)) ?? [])
            .sorted { $0.utf8.lexicographicallyPrecedes($1.utf8) }
    }

    private func migrateDayFolder(in root: URL, epoch: UUID) async {
        var outcome = DayFolderMigrationOutcome()
        var failed = false
        do {
            try await performEdit { writer in
                outcome = try await writer.migratingLegacyDayFolder()
                return []
            }
        } catch VaultStoreError.indexUpdateFailed {
            // The files moved; the refresh below indexes them.
        } catch {
            failed = true
        }
        guard vaultURL == root, sync.epoch == epoch else { return }
        sync.migratedLegacyListing = Self.legacyDayFolderListing(in: root)
        var report = DayCopyMergeReport()
        report.movedDays = outcome.moved.count
        report.copiedDays = outcome.copies.count
        // A run that could not start (a `Diary/` case variant, a read-only vault) moved nothing.
        report.unmovedDays = failed ? max(1, sync.migratedLegacyListing?.count ?? 0) : outcome.failed.count
        if !report.isEmpty {
            var total = sync.mergeReport ?? DayCopyMergeReport()
            total.movedDays += report.movedDays
            total.copiedDays += report.copiedDays
            total.unmovedDays += report.unmovedDays
            sync.mergeReport = total
        }
        sync.folderMigrationTask = nil
        // The moved days and the new day copies; the copies then merge as any other.
        await refresh(directories: [VaultLayout.dayFolder, LegacyVaultNames.dayFolder])
    }
}
