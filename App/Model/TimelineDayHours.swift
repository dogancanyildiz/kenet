import Foundation

/// Visible hour bounds for a day timeline, including the standard working-day range.
enum TimelineDayHours {
    static func range(for dates: [Date], calendar: Calendar) -> ClosedRange<Int> {
        let hours = dates.map { calendar.component(.hour, from: $0) }
        return range(forHours: hours)
    }

    static func range(forHours hours: [Int]) -> ClosedRange<Int> {
        min(8, hours.min() ?? 8)...max(20, hours.max() ?? 20)
    }
}
