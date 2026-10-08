import SwiftUI

/// Sort order as a manşet-row icon; accent while the order differs from the default (by name).
struct EntitySortMenu: View {
    @Binding var order: EntityOrdering

    var body: some View {
        InkHeaderMenu(
            "Sıralama", systemImage: "arrow.up.arrow.down", isActive: order != .name,
            identifier: "button.entities.sort"
        ) {
            Picker("Sıralama", selection: $order) {
                Text("Ada göre").tag(EntityOrdering.name)
                Text("Son geçişe göre").tag(EntityOrdering.recent)
            }
            .pickerStyle(.inline)
        }
    }
}

/// In-page filter of the entity list: the Search page's field as a component.
struct EntityFilterField: View {
    @Binding var search: String

    var body: some View {
        InkFilterField("Kişi veya konum ara", text: $search, identifier: "field.entities.filter")
            .autocorrectionDisabled()
    }
}
