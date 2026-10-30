import Foundation
import Observation

/// What iCloud sync is doing in the open vault, for the small indicator on the main screen
/// (`SyncStatusIndicator`; docs/screens.md, "Kasa eşitlenirken").
enum SyncStatus: Equatable, Sendable {
    case idle
    /// Originals iCloud has not brought to this device yet.
    case downloading(Int)
    /// Day copies being merged into their day files now.
    case mergingCopies(Int)

    /// Only an iCloud vault reports sync. A merge in progress outranks downloads still waiting.
    static func resolve(isCloudVault: Bool, pendingDownloads: Int, mergingCopies: Int) -> SyncStatus {
        guard isCloudVault else { return .idle }
        if mergingCopies > 0 { return .mergingCopies(mergingCopies) }
        if pendingDownloads > 0 { return .downloading(pendingDownloads) }
        return .idle
    }

    /// The indicator's sentence; empty when idle.
    var message: String { message(locale: .current) }

    func message(locale: Locale) -> String {
        switch self {
        case .idle: ""
        case .downloading(let count): String(localized: "\(count) dosya iCloud’dan iniyor.", locale: locale)
        case .mergingCopies(let count): String(localized: "\(count) gün kopyası birleştiriliyor.", locale: locale)
        }
    }
}

/// What the app may do to sync files on its own. Decision 2026-10-13: the app does not merge day
/// copies in a real vault before the two-device trial, so the merge is off by default and has no
/// switch in Settings; code and tests turn it on.
struct SyncPolicy: Sendable, Equatable {
    var mergesDayCopies = false

    static let standard = SyncPolicy()
}

/// The open vault's sync lists as the last refresh published them (`RebuildResult.pendingDownloads`,
/// `RebuildResult.dayCopies`) and what the app did with them. Lists of another vault never count:
/// `root` names the vault they belong to.
@MainActor @Observable
final class SyncState {
    private(set) var root: URL?
    /// Changes with every reset: a request or merge started before it no longer counts.
    @ObservationIgnored private(set) var epoch = UUID()
    /// Vault-relative originals that are only iCloud placeholders here, in UTF-8 byte order.
    var pendingDownloads: [String] = []
    /// Day copies on disk, in merge order (`DayCopyName.copies`).
    var dayCopies: [String] = []
    /// Download requests the system refused; Diagnostics shows the number.
    var downloadFailures = 0
    /// Day copies of the running merge not yet done.
    var mergingCopies = 0
    /// What the last merge did, until the band is dismissed.
    var mergeReport: DayCopyMergeReport?
    /// Placeholders already asked for; each is asked for once while it stays a placeholder.
    @ObservationIgnored var requestedDownloads: Set<String> = []
    /// Day copies a merge already took up in this vault; a failed one is not tried again.
    @ObservationIgnored var attemptedCopies: Set<String> = []
    @ObservationIgnored var mergeTask: Task<Void, Never>?
    /// The last download request sent; requests go out one after another, nothing waits for them.
    @ObservationIgnored var downloadTask: Task<Void, Never>?

    /// The lists a refresh starts from (`IndexUpdate.read`).
    var lists: SyncLists { SyncLists(pendingDownloads: pendingDownloads, dayCopies: dayCopies) }

    /// Starts over for a vault opened (again) or for none.
    func reset(for root: URL?) {
        self.root = root
        epoch = UUID()
        pendingDownloads = []
        dayCopies = []
        downloadFailures = 0
        mergingCopies = 0
        mergeReport = nil
        requestedDownloads = []
        attemptedCopies = []
        mergeTask = nil
        downloadTask = nil
    }

    func dismissMergeReport() { mergeReport = nil }
}
