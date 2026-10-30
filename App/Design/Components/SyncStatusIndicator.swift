import SwiftUI

/// The small, quiet line that says iCloud sync is under way (docs/screens.md, "Kasa eşitlenirken").
/// It follows the synced-folder band: an `InfoBand` in the info tone, without a dismiss button,
/// and nothing at all while idle. The content below stays on screen.
struct SyncStatusIndicator: View {
    let status: SyncStatus

    var body: some View {
        if status != .idle {
            InfoBand(kind: .info, verbatim: status.message)
                .background(Color.ink.paper)
                .accessibilityElement(children: .ignore)
                .accessibilityLabel(Text(verbatim: VoiceOverCopy.syncStatusLabel(status)))
                .accessibilityIdentifier("indicator.syncStatus")
        }
    }
}
