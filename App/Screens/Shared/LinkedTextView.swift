import SwiftUI

/// Native links open the entity page or offer creation for an unresolved target.
struct LinkedTextView: View {
    let text: LinkedText
    let store: IndexStore
    /// Completed task text: plain runs in secondary ink (links keep their underline style).
    var isMuted: Bool = false
    /// When false, a link tap does nothing. Task rows pass the row-interaction table.
    var opensLinks: Bool = true
    @Environment(\.entityLookup) private var entityLookup
    @State private var destination: LinkDestination?

    private var segments: [InkLinkSegment] {
        let lookup =
            entityLookup.isEmpty
            ? LinkedTextInk.lookup(entities: store.content.entities) : entityLookup
        return LinkedTextInk.segments(text, byPath: lookup)
    }

    var body: some View {
        InkLinkedText(segments: segments, isMuted: isMuted) { url in
            guard opensLinks else { return }
            guard url.scheme == "journal-entity",
                let components = URLComponents(url: url, resolvingAgainstBaseURL: false),
                let name = components.queryItems?.first(where: { $0.name == "name" })?.value
            else { return }
            let path = components.queryItems?.first(where: { $0.name == "path" })?.value
            let entities = store.content.entities
            destination = LinkDestination(
                name: name, path: path, entity: entities.first { $0.id == path })
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
                .inkSheet(verbatim: link.name, onClose: { destination = nil })
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

private struct EntityLookupKey: EnvironmentKey {
    static let defaultValue: [String: EntitySummary] = [:]
}

extension EnvironmentValues {
    /// Path → entity map built once per screen for ``LinkedTextView``.
    var entityLookup: [String: EntitySummary] {
        get { self[EntityLookupKey.self] }
        set { self[EntityLookupKey.self] = newValue }
    }
}

/// Maps parsed ``LinkedText`` spans onto ``InkLinkSegment`` kinds for drawing.
enum LinkedTextInk {
    static func lookup(entities: [EntitySummary]) -> [String: EntitySummary] {
        Dictionary(entities.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
    }

    static func segments(_ text: LinkedText, entities: [EntitySummary]) -> [InkLinkSegment] {
        segments(text, byPath: lookup(entities: entities))
    }

    static func segments(_ text: LinkedText, byPath: [String: EntitySummary]) -> [InkLinkSegment] {
        text.spans.enumerated().map { index, span in
            let id = "\(index)-\(span.text)"
            guard let target = span.target else {
                return InkLinkSegment(id: id, text: span.text, kind: .plain)
            }
            let kind: InkLinkSegment.Kind
            if let path = span.destination, let entity = byPath[path] {
                switch entity.kind {
                case "place": kind = .place
                case "person": kind = .person
                default: kind = .other
                }
            } else if span.destination == nil {
                kind = .unresolved
            } else {
                kind = .other
            }
            return InkLinkSegment(
                id: id, text: span.text, kind: kind, target: target, path: span.destination)
        }
    }
}
