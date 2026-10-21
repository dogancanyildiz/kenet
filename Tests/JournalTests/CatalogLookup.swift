import Foundation

/// What the built app finds in its String Catalog: a key has an entry for a language when the
/// app's compiled table for that language answers it.
enum CatalogLookup {
    static func hasTranslation(_ key: String, language: String) -> Bool {
        guard let path = Bundle.main.path(forResource: language, ofType: "lproj"),
            let bundle = Bundle(path: path)
        else { return false }
        let missing = "\u{1}missing"
        return bundle.localizedString(forKey: key, value: missing, table: nil) != missing
    }
}
