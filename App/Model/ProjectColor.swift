import SwiftUI

/// Stable project color shared by the task board and timeline.
enum ProjectColor {
    /// No `warning`: amber means "carried over" (devreden) on the task row, board and timeline;
    /// a project drawn in it read as overdue (fark3, decisions.md 2026-11-11).
    private static let palette: [Color] = [
        .ink.accent, .ink.person, .ink.place, .ink.control,
    ]

    static func color(for project: String?) -> Color {
        guard let project, !project.isEmpty else { return .ink.control }
        return palette[index(for: project)]
    }

    /// FNV-1a avoids Swift's process-randomized `String.hashValue`.
    nonisolated static func index(for project: String) -> Int {
        let hash = project.utf8.reduce(UInt64(14_695_981_039_346_656_037)) {
            ($0 ^ UInt64($1)) &* 1_099_511_628_211
        }
        return Int(hash % 4)
    }
}
