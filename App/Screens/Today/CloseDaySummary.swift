import Foundation

/// Numbers shown at the top of the close-day sheet.
struct CloseDaySummary: Equatable, Sendable {
    var events: Int
    var completedTasks: Int
    var remainingTasks: Int
}
