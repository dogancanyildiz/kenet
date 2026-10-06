import SwiftUI

/// Native links open the entity page or offer creation for an unresolved target.
struct LinkedTextView: View {
    let text: LinkedText
    let store: IndexStore
    private var entities: [EntitySummary] { store.content.entities }
    @State private var destination: LinkDestination?
    /// Built once per identity so duplicate entity paths cannot crash `Dictionary` on every draw.
    @State private var segments: [InkLinkSegment] = []

    private var segmentIdentity: String {
        text.plainText + "\u{1e}" + entities.map(\.id).joined(separator: "\u{1f}")
            + "\u{1e}" + String(describing: store.lastUpdated?.timeIntervalSince1970 ?? 0)
    }

    var body: some View {
        InkLinkedText(segments: segments) { url in
            guard url.scheme == "journal-entity",
                let components = URLComponents(url: url, resolvingAgainstBaseURL: false),
                let name = components.queryItems?.first(where: { $0.name == "name" })?.value
            else { return }
            let path = components.queryItems?.first(where: { $0.name == "path" })?.value
            destination = LinkDestination(name: name, path: path, entity: entities.first { $0.id == path })
        }
        .task(id: segmentIdentity) {
            segments = LinkedTextInk.segments(text, entities: entities)
        }
        .sheet(item: $destination) { link in
            NavigationStack {
                Group {
                    if let entity = link.entity {
                        EntityView(store: store, entity: entity)
                    } else if link.path == nil {
                        UnresolvedEntityView(store: store, target: link.name)
                    } else {
                        ContentUnavailableView(
                            "Bu bağlantı kişi veya konum değil", systemImage: "doc.text",
                            description: Text(verbatim: link.name))
                    }
                }
                .toolbar { Button("Kapat") { destination = nil } }
            }
            .frame(minWidth: 300, minHeight: 300)
        }
    }

    private struct LinkDestination: Identifiable {
        let name: String
        let path: String?
        let entity: EntitySummary?
        var id: String { path ?? name }
    }
}

/// Maps parsed ``LinkedText`` spans onto ``InkLinkSegment`` kinds for drawing.
enum LinkedTextInk {
    static func segments(_ text: LinkedText, entities: [EntitySummary]) -> [InkLinkSegment] {
        let byPath = Dictionary(entities.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        return text.spans.enumerated().map { index, span in
            let id = "\(index)-\(span.text)"
            guard let target = span.target else {
                return InkLinkSegment(id: id, text: span.text, kind: .plain)
            }
            let kind: InkLinkSegment.Kind
            if let path = span.destination, let entity = byPath[path] {
                switch entity.kind {
                case "place": kind = .place
                case "person": kind = .person
                default: kind = .entity
                }
            } else if span.destination == nil {
                kind = .unresolved
            } else {
                kind = .entity
            }
            return InkLinkSegment(
                id: id, text: span.text, kind: kind, target: target, path: span.destination)
        }
    }
}
