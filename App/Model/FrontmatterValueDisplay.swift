import Foundation
import VaultFormat

/// Formats frontmatter values for reading UI (no raw wikilink markup).
enum FrontmatterValueDisplay {
    static func text(_ value: FrontmatterValue, locale: Locale = .autoupdatingCurrent) -> String {
        switch value {
        case .scalar(let scalar):
            scalarText(scalar, locale: locale)
        case .list(let items, _):
            items.map { scalarText($0, locale: locale) }.filter { !$0.isEmpty }.joined(separator: ", ")
        case .mapping(let entries):
            entries.map { entry in
                let label = FrontmatterKeyLabel.display(entry.key)
                let body = scalarText(entry.value, locale: locale)
                return body.isEmpty ? label : "\(label): \(body)"
            }.joined(separator: "\n")
        case .raw(let text):
            VaultDisplayText.wikilinksOnly(text)
        }
    }

    private static func scalarText(_ scalar: FrontmatterScalar, locale: Locale) -> String {
        switch scalar.kind {
        case .empty:
            return ""
        case .boolean(let value):
            return String(localized: value ? "Evet" : "Hayır", locale: locale)
        case .date(let day):
            return LocalDay.instant(for: day).formatted(
                .dateTime.day().month(.abbreviated).year().locale(locale))
        case .number, .text:
            // Frontmatter: strip wikilinks only — never block ids (`x ^2` stays).
            return VaultDisplayText.wikilinksOnly(scalar.text)
        }
    }
}
