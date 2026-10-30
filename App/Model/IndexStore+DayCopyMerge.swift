import Foundation
import VaultIndex
import VaultStore

/// What one merge run over the scan's day copies did, for the band on the main screen.
struct DayCopyMergeReport: Equatable, Sendable {
    /// Copies now part of their day file, including one whose index update failed afterwards.
    var merged = 0
    /// Copies left in place; Diagnostics still lists them.
    var failed = 0

    var isEmpty: Bool { merged == 0 && failed == 0 }

    /// The band's sentences, in this order: merged, failed.
    var message: String {
        var parts: [String] = []
        if merged > 0 { parts.append(String(localized: "\(merged) gün kopyası birleştirildi.")) }
        if failed > 0 {
            parts.append(String(localized: "\(failed) gün kopyası birleştirilemedi; Tanılama’da duruyor."))
        }
        return parts.joined(separator: " ")
    }
}

// MARK: - Day copy merges

extension IndexStore {
    /// After a refresh: merges the day copies the scan found, one by one in the scan's order, when
    /// `syncPolicy.mergesDayCopies` allows it (off by default, decision 2026-10-13) and the vault is
    /// the iCloud vault and writable. With the policy off nothing is merged and Diagnostics lists
    /// the copies as before. Each copy is one write through the write queue (`mergingDayCopy`), so
    /// it waits for refreshes and other writes and publishes its day file. A copy a run took up is
    /// not taken up again in this vault, except one waiting for iCloud's download: the next
    /// refresh tries it again. A failed copy never stops the others.
    func scheduleDayCopyMerge(excluding waiting: Set<String> = []) {
        guard syncPolicy.mergesDayCopies, isCloudVault, canAddEvent, let root = vaultURL, sync.root == root,
            sync.mergeTask == nil
        else { return }
        let copies = sync.dayCopies.filter { !sync.attemptedCopies.contains($0) && !waiting.contains($0) }
        guard !copies.isEmpty else { return }
        sync.attemptedCopies.formUnion(copies)
        sync.mergingCopies = copies.count
        sync.mergeTask = Task { [weak self] in
            await self?.mergeDayCopies(copies, in: root)
        }
    }

    /// Test seam: returns once no merge is running, including one a finished run started.
    func waitForDayCopyMerges() async {
        while let task = sync.mergeTask { await task.value }
    }

    private func mergeDayCopies(_ copies: [String], in root: URL) async {
        var report = DayCopyMergeReport()
        var waiting: Set<String> = []
        for copy in copies {
            guard vaultURL == root, sync.root == root else { break }
            do {
                let estimated = DayCopyName.dayPath(ofCopy: copy).map { Set([$0]) } ?? []
                try await performEdit(estimatedPaths: estimated) { writer in
                    let outcome = try await writer.mergingDayCopy(copy)
                    return [outcome.dayPath]
                }
                report.merged += 1
            } catch VaultStoreError.awaitingDownload {
                waiting.insert(copy)
            } catch VaultStoreError.indexUpdateFailed {
                // The day file holds both versions; the next refresh indexes it.
                report.merged += 1
            } catch {
                report.failed += 1
            }
            if sync.root == root { sync.mergingCopies = max(0, sync.mergingCopies - 1) }
        }
        guard sync.root == root else { return }
        sync.attemptedCopies.subtract(waiting)
        sync.mergingCopies = 0
        if !report.isEmpty {
            // A band not dismissed yet adds this run's numbers.
            var total = sync.mergeReport ?? DayCopyMergeReport()
            total.merged += report.merged
            total.failed += report.failed
            sync.mergeReport = total
        }
        sync.mergeTask = nil
        // Copies found while this run merged; the ones waiting for a download wait for a refresh.
        scheduleDayCopyMerge(excluding: waiting)
    }
}
