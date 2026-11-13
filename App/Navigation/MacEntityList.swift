import SwiftUI
import VaultIndex

/// Kişiler / Konumlar column.
struct MacEntityList: View {
    let store: IndexStore
    let entities: [EntitySummary]
    var showsUnseen: Bool
    var unseenReveal: UUID? = nil
    @Binding var selection: String?
    @State private var editingEntity: EntitySummary?
    /// Every row's last encounter, 12-month days and relation count, read once for the column.
    @State private var activity: [String: EntityListActivity] = [:]

    var body: some View {
        List(selection: $selection) {
            if showsUnseen {
                UnseenPeopleSection(
                    store: store, people: entities, select: { selection = $0.id },
                    initiallyExpanded: unseenReveal != nil
                )
                .id(unseenReveal)
            }
            ForEach(entities) { entity in
                EntityRow(
                    entity: entity, store: store, activity: activity[entity.id], onEdit: { editingEntity = entity },
                    onDeleted: { if selection == $0 { selection = nil } }
                )
                .inkListRow(columnSelected: selection == entity.id)
                .tag(entity.id)
            }
        }
        .listStyle(.plain)
        .scrollContentBackground(.hidden)
        .inkColumnListFocus()
        .entityListActivity(store: store, into: $activity)
        .entityDefinitionActions(
            store: store, editing: $editingEntity,
            onRenamed: { old, new in if selection == old { selection = new } },
            onDeleted: { if selection == $0 { selection = nil } }
        )
    }
}
