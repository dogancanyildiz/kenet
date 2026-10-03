import SwiftUI

/// Native links open the entity page or offer creation for an unresolved target.
struct LinkedTextView: View {
    let text: LinkedText
    let store: IndexStore
    private var entities: [EntitySummary] { store.content.entities }
    @State private var destination: LinkDestination?

    var body: some View {
        Text(attributedText)
            .environment(
                \.openURL,
                OpenURLAction { url in
                    guard url.scheme == "journal-entity",
                        let components = URLComponents(url: url, resolvingAgainstBaseURL: false),
                        let name = components.queryItems?.first(where: { $0.name == "name" })?.value
                    else { return .systemAction }
                    let path = components.queryItems?.first(where: { $0.name == "path" })?.value
                    destination = LinkDestination(name: name, path: path, entity: entities.first { $0.id == path })
                    return .handled
                }
            )
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

    private var attributedText: AttributedString {
        var result = AttributedString()
        for span in text.spans {
            var value = AttributedString(span.text)
            if let target = span.target {
                var url = URLComponents()
                url.scheme = "journal-entity"
                url.host = "open"
                url.queryItems = [URLQueryItem(name: "name", value: target)]
                if let path = span.destination { url.queryItems?.append(URLQueryItem(name: "path", value: path)) }
                value.link = url.url
            }
            result.append(value)
        }
        return result
    }

    private struct LinkDestination: Identifiable {
        let name: String
        let path: String?
        let entity: EntitySummary?
        var id: String { path ?? name }
    }
}
