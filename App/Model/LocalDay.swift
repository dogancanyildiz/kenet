import Foundation
import VaultFormat

/// Vault dates use the Gregorian calendar in the user's current time zone.
enum LocalDay {
    static func today(at instant: Date = Date(), timeZone: TimeZone = .current) -> CalendarDate {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = timeZone
        let components = calendar.dateComponents([.year, .month, .day], from: instant)
        return CalendarDate(year: components.year!, month: components.month!, day: components.day!)!
    }

    static func clock(at instant: Date = Date(), timeZone: TimeZone = .current) -> LineClock {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = timeZone
        let components = calendar.dateComponents([.hour, .minute], from: instant)
        return try! LineClock(hour: components.hour!, minute: components.minute!)
    }

    static func instant(for day: CalendarDate, time: EventTime? = nil, timeZone: TimeZone = .current) -> Date {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = timeZone
        return calendar.date(
            from: DateComponents(
                year: day.year, month: day.month, day: day.day, hour: time?.hour ?? 12,
                minute: time?.minute ?? 0))!
    }
}
