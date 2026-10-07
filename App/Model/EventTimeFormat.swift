import Foundation
import VaultFormat

/// Presents vault event clock times for UI. Values are local wall-clock times with no time zone;
/// they must not shift with the device time zone.
enum EventTimeFormat {
    private static var referenceCalendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = .gmt
        return calendar
    }

    static func string(for time: EventTime, locale: Locale = .current) -> String {
        string(hour: time.hour, minute: time.minute, locale: locale)
    }

    static func string(hour: Int, minute: Int, locale: Locale = .current) -> String {
        let calendar = referenceCalendar
        guard
            let date = calendar.date(
                from: DateComponents(year: 2000, month: 1, day: 1, hour: hour, minute: minute))
        else {
            return String(format: "%02d:%02d", hour, minute)
        }
        let formatter = DateFormatter()
        formatter.calendar = calendar
        formatter.locale = locale
        formatter.timeZone = calendar.timeZone
        formatter.dateStyle = .none
        formatter.timeStyle = .short
        return formatter.string(from: date)
    }
}
