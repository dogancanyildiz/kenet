import SwiftUI

/// Stable project color shared by the task board and timeline.
enum ProjectColor {
    private static let palette: [Color] = [
        .ink.accent, .ink.person, .ink.place, .ink.warning, .ink.control,
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
        return Int(hash % 5)
    }
}
