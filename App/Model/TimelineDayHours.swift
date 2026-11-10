import Foundation

/// Visible hour bounds for the day timeline (screens.md "Gün ölçeği"): 09:00–18:00 by default;
/// the day's earliest and latest timed record widen it.
enum TimelineDayHours {
    static let standard = 9...18

    static func range(for dates: [Date], calendar: Calendar) -> ClosedRange<Int> {
        range(forHours: dates.map { calendar.component(.hour, from: $0) })
    }

    static func range(forHours hours: [Int]) -> ClosedRange<Int> {
        let first = min(standard.lowerBound, hours.min() ?? standard.lowerBound)
        let last = max(standard.upperBound, hours.max() ?? standard.upperBound)
        return first...last
    }
}
