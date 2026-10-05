/// Canonical top-level vault folder names and case-variant detection for prepare/import.
public enum VaultLayout {
    /// Standard folders the app creates and recognizes by exact spelling.
    public static let standardFolders = ["journal", "people", "places", "goals", "notes", "templates"]

    /// Physical root folder names that match a standard folder ignoring ASCII case but differ in spelling.
    ///
    /// Reserved folder identity is exact (`journal/`, not `Journal/`). Case-insensitive file systems
    /// would otherwise redirect writes into the wrong physical name; case-sensitive ones would create
    /// a second folder. Prepare reports these; writes are refused only when targeting that canonical folder.
    public static func caseVariantFolders(among names: [String]) -> [String] {
        names.filter { name in
            standardFolders.contains { canonical in
                name.lowercased() == canonical && name != canonical
            }
        }.sorted()
    }

    /// The canonical spelling for a case-variant folder name, if any.
    public static func expectedFolder(forVariant name: String) -> String? {
        standardFolders.first { name.lowercased() == $0 && name != $0 }
    }
}
