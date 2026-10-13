/// A sync copy the app leaves in place: the copy's path, its folder, and the file it duplicates.
public struct CopyFile: Sendable, Equatable {
    /// The copy's folder relative to the vault root; empty at the root.
    public let folder: String
    /// The copy's vault-relative path, such as `people/Elif 2.md`.
    public let copy: String
    /// The path of the file the copy duplicates, such as `people/Elif.md`.
    public let original: String

    public init(folder: String, copy: String, original: String) {
        self.folder = folder
        self.copy = copy
        self.original = original
    }
}

/// Pure path rule for the copies iCloud makes when two devices write the same entity file.
///
/// A copy is `Folder/Name N.md`: a non-empty name, one space, and an ASCII number of at least 2
/// without a leading zero, in the same folder as the entity file `Folder/Name.md`. The number alone
/// does not make a copy: `people/Kaan 2.md` without `people/Kaan.md` is an entity named "Kaan 2".
/// The original is found with the vault's name comparison (NFC, default lowercase mapping).
public enum EntityCopyName {
    private static let suffix = Array(".md".utf8)

    /// The path the copy would duplicate (`people/Elif.md` for `people/Elif 2.md`), or `nil` when
    /// the name carries no copy number. Syntax only: the path is a copy when that file exists.
    public static func originalPath(ofCopy path: String) -> String? {
        parse(path)?.original
    }

    /// The paths among `paths` that copy one of `originals`, by original and then copy number.
    public static func copies(in paths: some Sequence<String>, originals: some Sequence<String>) -> [CopyFile] {
        var byKey: [String: String] = [:]
        for original in originals {
            let key = comparisonKey(original)
            if let kept = byKey[key], kept.utf8.lexicographicallyPrecedes(original.utf8) { continue }
            byKey[key] = original
        }
        return paths.compactMap { path -> (CopyFile, [UInt8])? in
            guard let parsed = parse(path), let original = byKey[comparisonKey(parsed.original)] else { return nil }
            return (CopyFile(folder: parsed.folder, copy: path, original: original), parsed.number)
        }
        .sorted { lhs, rhs in
            if lhs.0.original != rhs.0.original {
                return lhs.0.original.utf8.lexicographicallyPrecedes(rhs.0.original.utf8)
            }
            if lhs.1 != rhs.1 { return numberPrecedes(lhs.1, rhs.1) }
            return lhs.0.copy.utf8.lexicographicallyPrecedes(rhs.0.copy.utf8)
        }
        .map(\.0)
    }

    private struct Parsed {
        let folder: String
        let original: String
        let number: [UInt8]
    }

    private static func parse(_ path: String) -> Parsed? {
        let bytes = Array(path.utf8)
        guard bytes.count > suffix.count, bytes.reversed().starts(with: suffix.reversed()) else { return nil }
        let stem = bytes[..<(bytes.count - suffix.count)]
        let slash = stem.lastIndex(of: UInt8(ascii: "/"))
        let nameStart = slash.map { $0 + 1 } ?? stem.startIndex
        guard let space = stem[nameStart...].lastIndex(of: UInt8(ascii: " ")), space > nameStart else { return nil }
        let number = Array(stem[(space + 1)...])
        guard let first = number.first, first != UInt8(ascii: "0"),
            number.allSatisfy({ (UInt8(ascii: "0")...UInt8(ascii: "9")).contains($0) }),
            number.count > 1 || first != UInt8(ascii: "1")
        else { return nil }
        let folder = slash.map { String(decoding: stem[..<$0], as: UTF8.self) } ?? ""
        let original = String(decoding: stem[..<space], as: UTF8.self) + ".md"
        return Parsed(folder: folder, original: original, number: number)
    }

    /// Numeric order without overflow: digits carry no leading zero, so the shorter one is smaller.
    private static func numberPrecedes(_ lhs: [UInt8], _ rhs: [UInt8]) -> Bool {
        lhs.count != rhs.count ? lhs.count < rhs.count : lhs.lexicographicallyPrecedes(rhs)
    }
}
