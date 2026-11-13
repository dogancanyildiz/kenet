/// Canonical top-level vault folder names and case-variant detection for prepare/import.
public enum VaultLayout {
    /// Standard folders the app creates and recognizes by exact spelling.
    public static let standardFolders = ["diary", "people", "places", "goals", "notes", "templates"]

    /// Physical root folder names that match a standard folder ignoring ASCII case but differ in spelling.
    ///
    /// Reserved folder identity is exact (`diary/`, not `Diary/`). Case-insensitive file systems
    /// would otherwise redirect writes into the wrong physical name; case-sensitive ones would create
    /// a second folder. Prepare reports these; writes are refused only when targeting that canonical folder.
    public static func caseVariantFolders(among names: [String]) -> [String] {
        names.filter { name in
            standardFolders.contains { canonical in
                name.lowercased() == canonical && name != canonical
            }
        }.sorted()
    }

    /// The folder of day files, `diary/`.
    public static let dayFolder = "diary"
    /// The `type` value a new day file gets.
    public static let dayType = "diary"

    /// The day file path writers use, such as `diary/2026-10-02.md`.
    public static func dayPath(_ date: CalendarDate) -> String {
        dayFolder + "/" + date.description + ".md"
    }

    /// The path the same day had before the vault was migrated (`LegacyVaultNames.dayFolder`).
    public static func legacyDayPath(_ date: CalendarDate) -> String {
        LegacyVaultNames.dayFolder + "/" + date.description + ".md"
    }

    /// The day of a day file path directly under the exact `diary/` folder or the legacy day
    /// folder, named `YYYY-MM-DD.md`; `nil` for every other path.
    public static func day(ofDayPath path: String) -> CalendarDate? {
        for folder in [dayFolder, LegacyVaultNames.dayFolder] {
            let prefix = folder + "/"
            guard path.hasPrefix(prefix), path.hasSuffix(".md") else { continue }
            let stem = path.dropFirst(prefix.count).dropLast(3)
            guard !stem.contains("/"), let date = CalendarDate(stem) else { return nil }
            return date
        }
        return nil
    }

    /// Whether the path is a day file under the legacy day folder.
    public static func isLegacyDayPath(_ path: String) -> Bool {
        path.hasPrefix(LegacyVaultNames.dayFolder + "/") && day(ofDayPath: path) != nil
    }

    /// The canonical spelling for a case-variant folder name, if any.
    static func expectedFolder(forVariant name: String) -> String? {
        standardFolders.first { name.lowercased() == $0 && name != $0 }
    }
}
