import Foundation

/// Localized labels for known technical frontmatter keys. Display only.
enum FrontmatterKeyLabel {
    /// Returns a localized label for a known technical key, or `nil` when the key should be shown raw.
    static func localized(_ key: String) -> String? {
        switch key {
        case "aliases": String(localized: "Takma adlar")
        case "type": String(localized: "Tip")
        case "lat": String(localized: "Enlem")
        case "lon": String(localized: "Boylam")
        case "created": String(localized: "Oluşturulma")
        case "name": String(localized: "Ad")
        case "qualifier": String(localized: "Ayırt edici")
        default: nil
        }
    }

    /// Label for reading UI: known technical keys are localized; others keep their vault key.
    static func display(_ key: String) -> String {
        localized(key) ?? key
    }
}
