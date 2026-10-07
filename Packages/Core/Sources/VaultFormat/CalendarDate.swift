/// A calendar day without a time or a time zone, written as `YYYY-MM-DD` in the vault.
public struct CalendarDate: Hashable, Sendable, Comparable, CustomStringConvertible {
    /// The year, from 100 to 9999. Earlier years are not read the same way by every YAML reader.
    public let year: Int
    /// The month, from 1 to 12.
    public let month: Int
    /// The day of the month, starting at 1.
    public let day: Int

    /// Creates a date, or returns `nil` when that day does not exist in the Gregorian calendar.
    public init?(year: Int, month: Int, day: Int) {
        guard (100...9999).contains(year), (1...12).contains(month) else { return nil }
        guard (1...Self.daysInMonth(year: year, month: month)).contains(day) else { return nil }
        self.year = year
        self.month = month
        self.day = day
    }

    /// Parses a date written exactly as `YYYY-MM-DD`, or returns `nil` for anything else.
    public init?(_ text: some StringProtocol) {
        self.init(utf8: text.utf8)
    }

    init?(utf8 bytes: some Collection<UInt8>) {
        let bytes = Array(bytes)
        guard bytes.count == 10, bytes[4] == Syntax.dash, bytes[7] == Syntax.dash else { return nil }
        guard
            let year = Self.number(bytes[0..<4]),
            let month = Self.number(bytes[5..<7]),
            let day = Self.number(bytes[8..<10])
        else { return nil }
        self.init(year: year, month: month, day: day)
    }

    /// The date as `YYYY-MM-DD`.
    public var description: String {
        Self.padded(year, to: 4) + "-" + Self.padded(month, to: 2) + "-" + Self.padded(day, to: 2)
    }

    public static func < (lhs: CalendarDate, rhs: CalendarDate) -> Bool {
        (lhs.year, lhs.month, lhs.day) < (rhs.year, rhs.month, rhs.day)
    }

    public static func daysInMonth(year: Int, month: Int) -> Int {
        switch month {
        case 2:
            let isLeapYear = year % 4 == 0 && (year % 100 != 0 || year % 400 == 0)
            return isLeapYear ? 29 : 28
        case 4, 6, 9, 11:
            return 30
        default:
            return 31
        }
    }

    private static func number(_ digits: ArraySlice<UInt8>) -> Int? {
        var value = 0
        for digit in digits {
            guard Syntax.isDigit(digit) else { return nil }
            value = value * 10 + Int(digit - UInt8(ascii: "0"))
        }
        return value
    }

    private static func padded(_ value: Int, to width: Int) -> String {
        let digits = String(value)
        return String(repeating: "0", count: max(width - digits.count, 0)) + digits
    }
}
