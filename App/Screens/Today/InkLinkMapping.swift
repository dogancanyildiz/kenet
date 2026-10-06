import Foundation
import VaultFormat

/// Maps vault ``LinkedText`` spans to ``InkLinkSegment`` for MarginRow reading views.
enum InkLinkMapping {
    static func segments(from text: LinkedText, entities: [EntitySummary]) -> [InkLinkSegment] {
        let byPath = Dictionary(uniqueKeysWithValues: entities.map { ($0.id, $0) })
        return text.spans.enumerated().map { index, span in
            let kind: InkLinkSegment.Kind
            if span.target == nil {
                kind = .plain
            } else if let path = span.destination, let entity = byPath[path] {
                switch entity.kind {
                case "person": kind = .person
                case "place": kind = .place
                default: kind = .unresolved
                }
            } else if span.destination != nil {
                kind = .unresolved
            } else {
                kind = .unresolved
            }
            return InkLinkSegment(
                id: "\(index)-\(span.text)",
                text: span.text,
                kind: kind,
                target: span.target,
                path: span.destination
            )
        }
    }
}
