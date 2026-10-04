import SwiftUI

struct EntityTypePicker: View {
    let store: IndexStore
    @Binding var selection: String
    @Environment(\.locale) private var locale

    var body: some View {
        Picker("Varlık türü", selection: $selection) {
            ForEach(
                EntityTypeChoices.choices(store.entityTypes, language: locale.language.languageCode?.identifier ?? "en")
            ) { type in
                Text(verbatim: type.plural).tag(type.id)
            }
        }
        .pickerStyle(.menu)
        .onChange(of: store.entityTypes.allTypes, initial: true) { _, _ in
            selection = EntityTypeChoices.selection(selection, in: store.entityTypes)
        }
    }
}
