import EntityRecognition
import VaultFormat

/// Headless entries resolve certain names and leave questions as plain text.
enum IntentText {
    static func linking(_ text: String, entities: [KnownEntity]) throws -> String {
        let certain = EntityRecognizer.recognize(text, entities: entities).filter(\.isCertain)
        let linked = try EntityRecognizer.linking(text, mentions: certain)
        let positions =
            EntityRecognizer.recognize(linked, entities: entities).filter(\.isExplicit).map(\.position)
            + EntityRecognizer.unknownMentions(linked, entities: entities).map(\.position)
        let document = RawDocument(bytes: linked.utf8)
        let offsets = Set(
            positions.map { position in
                document.lines.prefix(position.line).reduce(document.hasByteOrderMark ? 3 : 0) { $0 + $1.bytes.count }
                    + position.byteRange.lowerBound - 1
            })
        var bytes = Array(linked.utf8)
        for offset in offsets.sorted(by: >) where bytes.indices.contains(offset) && bytes[offset] == 64 {
            bytes.remove(at: offset)
        }
        return String(decoding: bytes, as: UTF8.self)
    }

    static func display(_ text: String) -> String {
        let document = RawDocument(bytes: text.utf8)
        var bytes = Array(text.utf8)
        for link in document.links.reversed() {
            let offset = document.lines.prefix(link.line).reduce(document.hasByteOrderMark ? 3 : 0) {
                $0 + $1.bytes.count
            }
            bytes.replaceSubrange(
                (offset + link.byteRange.lowerBound)..<(offset + link.byteRange.upperBound),
                with: (link.displayText ?? link.target).utf8)
        }
        return String(String(decoding: bytes, as: UTF8.self).prefix(120))
    }
}
