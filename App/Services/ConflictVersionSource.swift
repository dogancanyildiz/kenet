import Foundation
import VaultIndex
import VaultStore

/// Where the unresolved conflicting versions of a vault file come from. The app only lists them:
/// nothing here merges, keeps or removes a version.
protocol ConflictVersionSource: Sendable {
    /// The versions iCloud keeps beside the file at `url`; empty when there are none or they cannot be read.
    func unresolvedConflicts(at url: URL) -> [ConflictVersion]
}

/// Reads iCloud's conflicting versions through `NSFileVersion`.
///
/// The ubiquity flag `ubiquitousItemHasUnresolvedConflictsKey` is read first, so a file without
/// conflicts costs one resource lookup. Only a flagged file is asked for its versions, inside a
/// coordinated read (`SystemFileCoordination`), as `NSFileVersion` expects. Synchronous: call it
/// off the main actor.
struct SystemConflictVersionSource: ConflictVersionSource {
    func unresolvedConflicts(at url: URL) -> [ConflictVersion] {
        let flag = try? url.resourceValues(forKeys: [.ubiquitousItemHasUnresolvedConflictsKey])
        guard flag?.ubiquitousItemHasUnresolvedConflicts == true else { return [] }
        let versions = try? SystemFileCoordination().coordinate(.read(url)) { _ in
            NSFileVersion.unresolvedConflictVersionsOfItem(at: url) ?? []
        }
        return (versions ?? []).map { version in
            ConflictVersion(
                modificationTime: version.modificationDate.map { Int($0.timeIntervalSince1970.rounded(.down)) } ?? 0,
                deviceName: version.localizedNameOfSavingComputer)
        }
    }
}
