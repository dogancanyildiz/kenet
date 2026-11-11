/// The birthday a person file names (`docs/vault-format.md`, "Doğum günü alanı"). Read only; the
/// app never writes it. It feeds the calendar's "Doğum günü ekle" form and nothing else.
public struct PersonBirthday: Hashable, Sendable {
    public let month: Int
    public let day: Int
    /// Nil for the yearless form `--MM-DD`.
    public let year: Int?

    public init?(month: Int, day: Int, year: Int?) {
        // A yearless 29 February is a real birthday: validate it against a leap year.
        guard CalendarDate(year: year ?? 2000, month: month, day: day) != nil else { return nil }
        self.month = month
        self.day = day
        self.year = year
    }

    /// The keys read, as written in the format document; compared with ``nameComparisonFold``.
    public static let keys = ["doğum günü", "doğum_günü", "birthday"]

    /// `YYYY-MM-DD` or `--MM-DD`; anything else is nil.
    public static func parse(_ text: String) -> PersonBirthday? {
        if let date = CalendarDate(text) { return PersonBirthday(month: date.month, day: date.day, year: date.year) }
        let bytes = Array(text.utf8)
        guard bytes.count == 7, bytes[0] == 0x2D, bytes[1] == 0x2D, bytes[4] == 0x2D,
            let month = twoDigits(bytes[2], bytes[3]), let day = twoDigits(bytes[5], bytes[6])
        else { return nil }
        return PersonBirthday(month: month, day: day, year: nil)
    }

    /// Whether `key` is one of ``keys``, ignoring case with the Turkish `İ`/`ı` rule.
    public static func isBirthdayKey(_ key: String) -> Bool {
        let folded = nameComparisonFold(key)
        return keys.contains { nameComparisonFold($0) == folded }
    }

    /// The first readable birthday among the fields, in file order. Lists, mappings and raw
    /// values are not read.
    public static func find(in fields: [(key: String, value: FrontmatterValue)]) -> PersonBirthday? {
        for field in fields where isBirthdayKey(field.key) {
            guard case .scalar(let scalar) = field.value, let birthday = parse(scalar.text) else { continue }
            return birthday
        }
        return nil
    }

    /// The day the yearly event starts: the birth date itself, or for a yearless value (and a
    /// year still to come) this year's day (the latest leap year's for 29 February).
    public func firstDay(currentYear: Int) -> CalendarDate? {
        // A year after this one is a typo: read the value as yearless.
        if let year, year <= currentYear { return CalendarDate(year: year, month: month, day: day) }
        var candidate = currentYear
        while candidate > currentYear - 8 {
            if let date = CalendarDate(year: candidate, month: month, day: day) { return date }
            candidate -= 1
        }
        return nil
    }

    private static func twoDigits(_ high: UInt8, _ low: UInt8) -> Int? {
        guard (0x30...0x39).contains(high), (0x30...0x39).contains(low) else { return nil }
        return Int(high - 0x30) * 10 + Int(low - 0x30)
    }
}
