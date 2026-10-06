import Foundation
import VaultFormat

/// Formats frontmatter values for reading UI (no raw wikilink markup).
enum FrontmatterValueDisplay {
    static func text(_ value: FrontmatterValue) -> String {
        switch value {
        case .scalar(let scalar):
            scalarText(scalar)
        case .list(let items, _):
            items.map(scalarText).filter { !$0.isEmpty }.joined(separator: ", ")
        case .mapping(let entries):
            entries.map { entry in
                let label = FrontmatterKeyLabel.display(entry.key)
                let body = scalarText(entry.value)
                return body.isEmpty ? label : "\(label): \(body)"
            }.joined(separator: "\n")
        case .raw(let text):
            VaultDisplayText.multiline(text)
        }
    }

    private static func scalarText(_ scalar: FrontmatterScalar) -> String {
        switch scalar.kind {
        case .empty:
            return ""
        case .boolean(let value):
            return String(localized: value ? "Evet" : "Hayır")
        case .date(let day):
            return day.description
        case .number, .text:
            return VaultDisplayText.line(scalar.text)
        }
    }
}
