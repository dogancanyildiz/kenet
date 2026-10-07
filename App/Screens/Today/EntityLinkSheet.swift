import SwiftUI
import VaultFormat

/// Shared destination for wiki-link taps on Today event and task rows.
struct EntityLinkDestination: Identifiable {
    let name: String
    let path: String?
    let entity: EntitySummary?
    var id: String { path ?? name }

    static func from(url: URL, entities: [EntitySummary]) -> EntityLinkDestination? {
        guard url.scheme == "journal-entity",
            let components = URLComponents(url: url, resolvingAgainstBaseURL: false),
            let name = components.queryItems?.first(where: { $0.name == "name" })?.value
        else { return nil }
        let path = components.queryItems?.first(where: { $0.name == "path" })?.value
        return EntityLinkDestination(
            name: name, path: path, entity: entities.first { $0.id == path })
    }
}

extension View {
    /// Presents person / place / unresolved entity pages for a Today link tap.
    func entityLinkSheet(
        _ destination: Binding<EntityLinkDestination?>, store: IndexStore
    ) -> some View {
        sheet(item: destination) { link in
            NavigationStack {
                Group {
                    if let entity = link.entity {
                        EntityView(store: store, entity: entity)
                    } else if link.path == nil {
                        UnresolvedEntityView(store: store, target: link.name)
                    } else {
                        VStack(alignment: .leading, spacing: 0) {
                            InkPageTitle(verbatim: link.name)
                            EmptyState("Bu bağlantı kişi veya konum değil")
                                .padding(.horizontal, InkSpacing.margin)
                            Spacer(minLength: 0)
                        }
                    }
                }
                .inkSheet(verbatim: link.name, onClose: { destination.wrappedValue = nil })
            }
            .frame(minWidth: 300, minHeight: 300)
        }
    }
}
