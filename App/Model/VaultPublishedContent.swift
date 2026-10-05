import Foundation
import VaultFormat
import VaultIndex

/// Snapshot-derived screen model and counts, built together so write and refresh share one path.
struct VaultPublishedContent: Sendable {
    let content: VaultReadModel
    let counts: IndexCounts

    /// Test seam: wraps `VaultReadModel` construction. The probe must run `body` exactly once.
    nonisolated(unsafe) static var buildProbe: (@Sendable (_ body: () -> Void) -> Void)?

    static func from(snapshot: IndexSnapshot, today: CalendarDate = LocalDay.today()) -> VaultPublishedContent {
        var published: VaultPublishedContent!
        let build = {
            published = VaultPublishedContent(
                content: VaultReadModel(snapshot: snapshot, today: today),
                counts: IndexCounts(snapshot: snapshot))
        }
        if let buildProbe {
            buildProbe(build)
        } else {
            build()
        }
        return published
    }

    static func load(from index: VaultIndex, today: CalendarDate = LocalDay.today()) throws -> VaultPublishedContent {
        from(snapshot: try index.snapshot(), today: today)
    }
}
