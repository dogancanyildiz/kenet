import Foundation

/// Quick-entry mode: event vs task (owner change 2 in `docs/design.md`).
enum QuickEntryMode: String, CaseIterable, Sendable {
    case event
    case task

    /// String Catalog key for the mode word.
    var catalogKey: String {
        switch self {
        case .event: "Olay"
        case .task: "Görev"
        }
    }
}
