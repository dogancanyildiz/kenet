import VaultFormat

extension VaultIndex {
    /// SQL that holds for the file row `alias` unless it is a day file under the legacy day folder
    /// whose date also has a day file under `diary/` (`LegacyVaultNames`). Date-based views add it,
    /// so a date held by both folders counts once, from `diary/` (`vault-format.md`, "Eski adlar ve
    /// geçiş"). Lists of lines, such as the task views, keep both files: neither line is lost.
    static func countsForItsDate(_ alias: String) -> String {
        let legacy = LegacyVaultNames.dayFolder + "/"
        let current = VaultLayout.dayFolder + "/"
        return """
            NOT (\(alias).kind = 'day' AND substr(\(alias).path, 1, \(legacy.count)) = '\(legacy)'
                AND EXISTS (SELECT 1 FROM files shadow WHERE shadow.kind = 'day' AND shadow.date = \(alias).date
                    AND substr(shadow.path, 1, \(current.count)) = '\(current)'))
            """
    }
}
