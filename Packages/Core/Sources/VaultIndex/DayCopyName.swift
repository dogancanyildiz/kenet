import VaultFormat

/// Pure path rule for the copies iCloud makes when two devices create the same day file.
///
/// A copy is `journal/YYYY-MM-DD N.md`: directly under the exact `journal/` folder, a valid day
/// written as the vault writes it, one space, and an ASCII number of at least 2 without a leading
/// zero. Matching uses UTF-8 bytes, so a decomposed or full-width digit never passes.
public enum DayCopyName {
    private static let folder = Array("journal/".utf8)
    private static let suffix = Array(".md".utf8)

    public static func isDayCopy(path: String) -> Bool {
        parse(path) != nil
    }

    /// The day whose file the copy duplicates, or `nil` when the path is not a copy.
    public static func day(ofCopy path: String) -> CalendarDate? {
        parse(path)?.day
    }

    /// The day file the copy belongs to, such as `journal/2026-10-02.md`.
    public static func dayPath(ofCopy path: String) -> String? {
        parse(path).map { "journal/" + $0.day.description + ".md" }
    }

    /// The copies among `paths` in merge order: by day, then by copy number, then by bytes.
    ///
    /// Several copies of one day are merged one at a time in this order, so that two devices that
    /// merge them separately combine the versions in the same sequence.
    public static func copies(in paths: some Sequence<String>) -> [String] {
        paths.compactMap { path in parse(path).map { (path, $0) } }
            .sorted { lhs, rhs in
                if lhs.1.day != rhs.1.day { return lhs.1.day < rhs.1.day }
                if lhs.1.number != rhs.1.number { return numberPrecedes(lhs.1.number, rhs.1.number) }
                return lhs.0.utf8.lexicographicallyPrecedes(rhs.0.utf8)
            }
            .map(\.0)
    }

    private struct Parsed {
        let day: CalendarDate
        let number: [UInt8]
    }

    private static func parse(_ path: String) -> Parsed? {
        let bytes = Array(path.utf8)
        // "journal/" + 10 date bytes + " " + at least one digit + ".md"
        guard bytes.count >= folder.count + 12 + suffix.count, bytes.starts(with: folder),
            bytes.reversed().starts(with: suffix.reversed())
        else { return nil }
        let name = bytes[folder.count..<(bytes.count - suffix.count)]
        let dateEnd = name.startIndex + 10
        let date = name[name.startIndex..<dateEnd]
        guard name[dateEnd] == UInt8(ascii: " "), let day = CalendarDate(String(decoding: date, as: UTF8.self)),
            day.description.utf8.elementsEqual(date)
        else { return nil }
        let number = Array(name[(dateEnd + 1)...])
        guard let first = number.first, first != UInt8(ascii: "0"),
            number.allSatisfy({ (UInt8(ascii: "0")...UInt8(ascii: "9")).contains($0) }),
            number.count > 1 || first != UInt8(ascii: "1")
        else { return nil }
        return Parsed(day: day, number: number)
    }

    /// Numeric order without overflow: digits carry no leading zero, so the shorter one is smaller.
    private static func numberPrecedes(_ lhs: [UInt8], _ rhs: [UInt8]) -> Bool {
        lhs.count != rhs.count ? lhs.count < rhs.count : lhs.lexicographicallyPrecedes(rhs)
    }
}
