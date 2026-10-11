import VaultFormat

/// A top-level entity scalar as written in the file. Values that are not `YYYY-MM-DD` are ignored.
public struct ImportantDateField: Sendable, Equatable {
    public let file: String
    public let key: String
    public let value: String

    public init(file: String, key: String, value: String) {
        self.file = file
        self.key = key
        self.value = value
    }
}

/// The next anniversary of one date field. Year 0, the source day itself, is never an anniversary.
public struct ImportantDate: Sendable, Equatable {
    public let date: CalendarDate
    /// Days from `today` to ``date``, zero when it falls today.
    public let daysUntil: Int
    /// `date.year - source.year`, at least 1.
    public let year: Int
    public let file: String
    public let key: String

    public init(date: CalendarDate, daysUntil: Int, year: Int, file: String, key: String) {
        self.date = date
        self.daysUntil = daysUntil
        self.year = year
        self.file = file
        self.key = key
    }
}

/// Upcoming anniversaries from entity date fields. No clock and no index types.
public enum ImportantDates {
    /// Today through the seventh day, today included. A nil window keeps the nearest date only.
    public static let windowDays = 7

    public static func select(
        today: CalendarDate, within windowDays: Int? = Self.windowDays, fields: [ImportantDateField]
    ) -> [ImportantDate] {
        var rows: [ImportantDate] = []
        for field in fields {
            guard let source = CalendarDate(field.value), let next = anniversary(of: source, on: today) else {
                continue
            }
            let days = next.date.ordinal - today.ordinal
            if let windowDays, days > windowDays { continue }
            rows.append(
                ImportantDate(
                    date: next.date, daysUntil: days, year: next.year, file: field.file, key: field.key))
        }
        rows.sort { lhs, rhs in
            if lhs.date != rhs.date { return lhs.date < rhs.date }
            if lhs.key != rhs.key { return lhs.key < rhs.key }
            return lhs.file < rhs.file
        }
        return rows
    }

    /// The next anniversary on or after `today`. A future source, or a first anniversary that has
    /// not arrived, produces nothing.
    private static func anniversary(of source: CalendarDate, on today: CalendarDate) -> (date: CalendarDate, year: Int)?
    {
        if source.year > today.year { return nil }
        guard let first = observed(source, in: source.year + 1), today >= first else { return nil }
        for year in today.year...today.year + 1 {
            guard let date = observed(source, in: year), date >= today else { continue }
            let age = year - source.year
            guard age >= 1 else { continue }
            return (date, age)
        }
        return nil
    }

    /// 29 February is observed on 28 February in a common year.
    private static func observed(_ source: CalendarDate, in year: Int) -> CalendarDate? {
        var day = source.day
        if source.month == 2, source.day == 29, CalendarDate.daysInMonth(year: year, month: 2) == 28 {
            day = 28
        }
        return CalendarDate(year: year, month: source.month, day: day)
    }
}
