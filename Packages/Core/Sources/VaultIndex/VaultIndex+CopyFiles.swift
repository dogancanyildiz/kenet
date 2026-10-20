import Foundation
import GRDB
import VaultFormat

extension VaultIndex {
    /// Indexed entity copies (`EntityCopyName`): a copy is any indexed file whose original is an
    /// indexed entity file in the same folder. Copies stay indexed as their own files; this only lists them.
    public func entityCopies() throws -> [CopyFile] {
        try database.read { db in
            let paths = try String.fetchAll(db, sql: "SELECT path FROM files")
            let entities = try String.fetchAll(db, sql: "SELECT file FROM entities")
            return EntityCopyName.copies(in: paths, originals: entities)
        }
    }

    /// Day copies directly under the exact `journal/` folder on disk, in `DayCopyName.copies` merge
    /// order. They are never indexed, so this lists that one folder instead of reading the index.
    public static func dayCopies(vaultRoot: URL) throws -> [CopyFile] {
        let names = try FileManager.default.contentsOfDirectory(atPath: vaultRoot.path)
        // Only the exact spelling: on a case-insensitive volume `Journal/` would also open as `journal`.
        guard names.contains("journal") else { return [] }
        return try VaultScanner.scan(vaultRoot, scopes: [.shallow("journal")]).result.dayCopies.compactMap { copy in
            DayCopyName.dayPath(ofCopy: copy).map { CopyFile(folder: "journal", copy: copy, original: $0) }
        }
    }
}

extension VaultIndex {
    /// Conflict copies directly under the exact `conflicts/` folder on disk, in `ConflictCopyName`
    /// order, each with the day file it was saved from. They are never indexed, so this lists that
    /// one folder; links, folders and names outside the rule are left out. Nothing is read or changed.
    public static func conflictCopies(vaultRoot: URL) throws -> [CopyFile] {
        let names = try FileManager.default.contentsOfDirectory(atPath: vaultRoot.path)
        // Only the exact spelling, as for `journal/`: a case-insensitive volume would open `Conflicts/` too.
        guard names.contains("conflicts") else { return [] }
        let directory = vaultRoot.appendingPathComponent("conflicts")
        let keys: Set<URLResourceKey> = [.isDirectoryKey, .isSymbolicLinkKey]
        let folder = try directory.resourceValues(forKeys: keys)
        guard folder.isDirectory == true, folder.isSymbolicLink != true else { return [] }
        let paths = try FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: Array(keys))
            .filter { url in
                guard let values = try? url.resourceValues(forKeys: keys) else { return false }
                return values.isDirectory != true && values.isSymbolicLink != true
            }
            .map { "conflicts/" + $0.lastPathComponent }
        return ConflictCopyName.copies(in: paths).compactMap { copy in
            ConflictCopyName.dayPath(ofCopy: copy).map { CopyFile(folder: "conflicts", copy: copy, original: $0) }
        }
    }
}

/// Pure path rule for the versions a day copy merge saves (`vault-format.md`, "Çakışma kopyası").
///
/// A copy is `conflicts/YYYY-MM-DD (conflict YYYYMMDDTHHMMSSZ).md`, or with ` N` before the closing
/// parenthesis when the name was taken: directly under the exact `conflicts/` folder, a valid day
/// written as the vault writes it, a valid UTC time in whole seconds, and an ASCII number of at least
/// 2 without a leading zero. Matching uses UTF-8 bytes, so a decomposed or full-width digit never passes.
public enum ConflictCopyName {
    private static let folder = Array("conflicts/".utf8)
    private static let marker = Array(" (conflict ".utf8)
    private static let suffix = Array(").md".utf8)

    public static func isConflictCopy(path: String) -> Bool {
        parse(path) != nil
    }

    /// The day file the copy was saved from, such as `journal/2026-10-02.md`.
    public static func dayPath(ofCopy path: String) -> String? {
        parse(path).map { "journal/" + $0.day.description + ".md" }
    }

    /// The copies among `paths`: by day, then by saved time, then unnumbered before numbered by number.
    public static func copies(in paths: some Sequence<String>) -> [String] {
        paths.compactMap { path in parse(path).map { (path, $0) } }
            .sorted { lhs, rhs in
                if lhs.1.day != rhs.1.day { return lhs.1.day < rhs.1.day }
                if lhs.1.stamp != rhs.1.stamp { return lhs.1.stamp.lexicographicallyPrecedes(rhs.1.stamp) }
                if lhs.1.number != rhs.1.number { return numberPrecedes(lhs.1.number, rhs.1.number) }
                return lhs.0.utf8.lexicographicallyPrecedes(rhs.0.utf8)
            }
            .map(\.0)
    }

    private struct Parsed {
        let day: CalendarDate
        /// `YYYYMMDDTHHMMSSZ`; fixed width, so byte order is time order.
        let stamp: [UInt8]
        /// Empty for the first name of a series.
        let number: [UInt8]
    }

    private static func parse(_ path: String) -> Parsed? {
        let bytes = Array(path.utf8)
        // folder + 10 date bytes + marker + 16 stamp bytes + suffix
        guard bytes.count >= folder.count + 10 + marker.count + 16 + suffix.count, bytes.starts(with: folder),
            bytes.reversed().starts(with: suffix.reversed())
        else { return nil }
        let name = Array(bytes[folder.count..<(bytes.count - suffix.count)])
        let date = name[0..<10]
        guard let day = CalendarDate(String(decoding: date, as: UTF8.self)), day.description.utf8.elementsEqual(date),
            name[10..<(10 + marker.count)].elementsEqual(marker)
        else { return nil }
        let rest = name[(10 + marker.count)...]
        let stamp = Array(rest.prefix(16))
        guard stamp.count == 16, isStamp(stamp) else { return nil }
        let tail = Array(rest.dropFirst(16))
        if tail.isEmpty { return Parsed(day: day, stamp: stamp, number: []) }
        guard tail.first == UInt8(ascii: " ") else { return nil }
        let number = Array(tail.dropFirst())
        guard let first = number.first, first != UInt8(ascii: "0"), number.allSatisfy(isDigit),
            number.count > 1 || first != UInt8(ascii: "1")
        else { return nil }
        return Parsed(day: day, stamp: stamp, number: number)
    }

    /// `YYYYMMDDTHHMMSSZ` with a real calendar day and a time of day below 24:00:00.
    private static func isStamp(_ stamp: [UInt8]) -> Bool {
        guard stamp[8] == UInt8(ascii: "T"), stamp[15] == UInt8(ascii: "Z"),
            stamp[0..<8].allSatisfy(isDigit), stamp[9..<15].allSatisfy(isDigit)
        else { return false }
        func value(_ range: Range<Int>) -> Int {
            stamp[range].reduce(0) { $0 * 10 + Int($1 - UInt8(ascii: "0")) }
        }
        return CalendarDate(year: value(0..<4), month: value(4..<6), day: value(6..<8)) != nil
            && value(9..<11) < 24 && value(11..<13) < 60 && value(13..<15) < 60
    }

    private static func isDigit(_ byte: UInt8) -> Bool {
        (UInt8(ascii: "0")...UInt8(ascii: "9")).contains(byte)
    }

    /// Numeric order without overflow; the unnumbered first name sorts before any number.
    private static func numberPrecedes(_ lhs: [UInt8], _ rhs: [UInt8]) -> Bool {
        lhs.count != rhs.count ? lhs.count < rhs.count : lhs.lexicographicallyPrecedes(rhs)
    }
}
