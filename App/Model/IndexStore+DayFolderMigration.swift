import Foundation
import VaultFormat
import VaultIndex
import VaultStore

// MARK: - Day folder migration

extension IndexStore {
    /// How many files a batch moves; each batch is one turn of the write queue.
    static let dayFolderMigrationBatch = 50

    /// After a refresh: counts the legacy day folder's day files, day copies and the ones waiting
    /// for download, for the offer on the main screen (`vault-format.md`, "Eski adlar ve geçiş").
    /// Nothing moves until the user confirms (decision 2026-11-13): another device or Obsidian may
    /// still write there. A read-only vault gets no offer. The folder is read off the main actor.
    func updateLegacyDayFolderOffer() async {
        guard let root = vaultURL, sync.root == root else { return }
        let epoch = sync.epoch
        let count = canAddEvent ? await Self.countLegacyDayFiles(in: root) : 0
        guard vaultURL == root, sync.epoch == epoch else { return }
        if sync.legacyDayFiles != count { sync.legacyDayFiles = count }
    }

    nonisolated static func countLegacyDayFiles(in root: URL) async -> Int {
        await Task.detached { legacyDayFileCount(in: root) }.value
    }

    /// Whether the main screen offers to move the legacy day folder now.
    var offersLegacyDayFolderMove: Bool {
        sync.legacyDayFiles > 0 && !sync.legacyOfferDismissed && sync.folderMigrationTask == nil && canAddEvent
    }

    /// "Sonra": the offer leaves until the vault is opened again.
    func dismissLegacyDayFolderOffer() { sync.legacyOfferDismissed = true }

    /// The user confirmed: moves the legacy day folder in batches, each one write through the write
    /// queue, so edits and queued share entries run between them. The band then says what moved,
    /// what became a day copy and what stayed, by name.
    func moveLegacyDayFolder() {
        guard canAddEvent, let root = vaultURL, sync.root == root, sync.folderMigrationTask == nil else { return }
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

    /// The day files, day copies and download placeholders of either directly under the exact
    /// legacy day folder; 0 when the vault root has no such folder. A case variant never counts.
    nonisolated static func legacyDayFileCount(in root: URL) -> Int {
        let manager = FileManager.default
        let legacy = LegacyVaultNames.dayFolder
        guard (try? manager.contentsOfDirectory(atPath: root.path))?.contains(legacy) == true else { return 0 }
        let folder = root.appendingPathComponent(legacy, isDirectory: true)
        let values = try? folder.resourceValues(forKeys: [.isDirectoryKey, .isSymbolicLinkKey])
        guard values?.isSymbolicLink != true, values?.isDirectory == true else { return 0 }
        return ((try? manager.contentsOfDirectory(atPath: folder.path)) ?? []).filter { name in
            let path = legacy + "/" + (PlaceholderName.originalName(ofPlaceholder: name) ?? name)
            return VaultLayout.day(ofDayPath: path) != nil || DayCopyName.isLegacyDayCopy(path: path)
        }.count
    }

    private func migrateDayFolder(in root: URL, epoch: UUID) async {
        var outcome = DayFolderMigrationOutcome()
        var stopped = false
        repeat {
            var batch = DayFolderMigrationOutcome()
            let skipping = outcome.attempted
            do {
                try await performEdit { writer in
                    batch = try await writer.migratingLegacyDayBatch(
                        limit: Self.dayFolderMigrationBatch, skipping: skipping)
                    // Core updated the index; the refresh after the run publishes every moved day.
                    return []
                }
            } catch VaultStoreError.indexUpdateFailed {
                // The batch's files moved and its outcome is kept; the refresh below publishes them.
            } catch {
                // Could not start (a `Diary/` case variant, a read-only vault, another vault opened).
                stopped = true
            }
            outcome.add(batch)
        } while !stopped && !outcome.finished && vaultURL == root && sync.epoch == epoch
        guard vaultURL == root, sync.epoch == epoch else { return }
        let left = await Self.countLegacyDayFiles(in: root)
        guard vaultURL == root, sync.epoch == epoch else { return }
        // This run's numbers replace the last run's; a day copy merge's numbers stay beside them.
        var report = sync.mergeReport ?? DayCopyMergeReport()
        report.movedDays = outcome.moved.count
        report.copiedDays = outcome.copies.count
        report.unmovedDays = stopped ? left : outcome.failed.count + outcome.waiting.count
        report.unmovedNames = stopped ? [] : outcome.failed + outcome.waiting
        sync.mergeReport = report.isEmpty ? nil : report
        // Counted before the run ends, so the offer does not come back for a moment after a full move.
        sync.legacyDayFiles = left
        sync.folderMigrationTask = nil
        // The moved days and the new day copies; the copies then merge as any other.
        await refresh(directories: [VaultLayout.dayFolder, LegacyVaultNames.dayFolder])
    }
}
