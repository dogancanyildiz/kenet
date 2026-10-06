import Foundation
import VaultFormat
import VaultIndex

/// Display spans preserve surrounding text and use index resolution for destinations.
struct LinkedText: Sendable {
    struct Span: Sendable {
        let text: String
        let destination: String?
        var target: String? = nil
    }

    let spans: [Span]
    var plainText: String { spans.map(\.text).joined() }

    /// Test and presentation helpers that already hold display spans.
    init(spans: [Span]) { self.spans = spans }

    init(row: IndexedBlock, links: [IndexedLink]) {
        let document = RawDocument(bytes: Array(("text\n" + row.text).utf8))
        let linksByLine = Dictionary(grouping: document.links, by: \.line)
        var available = links.filter { $0.block == row.ordinal }.sorted { $0.ordinal < $1.ordinal }
        var spans: [Span] = []
        for (lineNumber, line) in document.lines.dropFirst().enumerated() {
            if lineNumber > 0 { spans.append(Span(text: "\n", destination: nil)) }
            let bytes = Array((line.text ?? "").utf8)
            var cursor = 0
            for link in linksByLine[lineNumber + 1] ?? [] {
                guard
                    let source = available.firstIndex(where: {
                        $0.target == link.target && $0.displayText == link.displayText
                    })
                else { continue }
                let indexed = available.remove(at: source)
                let start = link.byteRange.lowerBound
                let end = link.byteRange.upperBound
                guard start >= cursor, end <= bytes.count else { continue }
                spans.append(Span(text: String(decoding: bytes[cursor..<start], as: UTF8.self), destination: nil))
                spans.append(
                    Span(text: link.displayText ?? link.target, destination: indexed.resolvedFile, target: link.target))
                cursor = end
            }
            spans.append(Span(text: String(decoding: bytes[cursor...], as: UTF8.self), destination: nil))
        }
        self.spans = spans
    }
}
