import Foundation
import VaultFormat

enum EntityTypedField {
    static func supports(_ value: FrontmatterValue?, kind: EntityTypeField.Kind) -> Bool {
        guard let value else { return true }
        guard case .scalar(let scalar) = value else { return false }
        if scalar.kind == .empty || (scalar.kind == .text && scalar.text.isEmpty) { return true }
        switch (kind, scalar.kind) {
        case (.text, .text), (.link, .text), (.number, .number), (.boolean, .boolean), (.date, .date): return true
        default: return false
        }
    }

    static func literal(_ text: String, kind: EntityTypeField.Kind) throws -> FrontmatterLiteral {
        if text.isEmpty { return .text("") }
        switch kind {
        case .text: return .text(text)
        case .date:
            guard let day = CalendarDate(text) else { throw EntityTypeError.invalidDefinition }
            return .date(day)
        case .boolean:
            guard text == "true" || text == "false" else { throw EntityTypeError.invalidDefinition }
            return .boolean(text == "true")
        case .number:
            let document = RawDocument(bytes: Array(("---\nvalue: " + text + "\n---\n").utf8))
            guard !text.contains(where: \.isWhitespace), case .parsed(let fields) = document.frontmatter,
                case .scalar(let number) = fields.field(named: "value")?.value, number.kind == .number
            else { throw EntityTypeError.invalidDefinition }
            return .number(text)
        case .link:
            let target = text.trimmingCharacters(in: .whitespacesAndNewlines)
            let candidate = target.hasPrefix("[[") ? target : "[[" + target + "]]"
            let links = RawDocument(bytes: Array(candidate.utf8)).links
            guard links.count == 1, let link = links.first, !link.target.isEmpty,
                link.byteRange == 0..<candidate.utf8.count
            else { throw EntityTypeError.invalidDefinition }
            return .text(candidate)
        }
    }
}
