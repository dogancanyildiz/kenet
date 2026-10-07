import Foundation
import VaultFormat

/// Maps vault ``LinkedText`` spans to ``InkLinkSegment`` for MarginRow reading views.
enum InkLinkMapping {
    /// Deduplicates by entity path so a copied vault file cannot crash Today.
    static func entityIndex(_ entities: [EntitySummary]) -> [String: EntitySummary] {
        Dictionary(entities.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
    }

    static func segments(from text: LinkedText, entities: [EntitySummary]) -> [InkLinkSegment] {
        segments(from: text, entitiesByID: entityIndex(entities))
    }

    static func segments(
        from text: LinkedText, entitiesByID: [String: EntitySummary]
    ) -> [InkLinkSegment] {
        text.spans.enumerated().map { index, span in
            let kind: InkLinkSegment.Kind
            if span.target == nil {
                kind = .plain
            } else if let path = span.destination, let entity = entitiesByID[path] {
                switch entity.kind {
                case "person": kind = .person
                case "place": kind = .place
                default: kind = .other
                }
            } else if span.destination != nil {
                // Resolved path without a matching entity row — still a resolved link.
                kind = .other
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
