import SwiftUI

/// "Pick one" for the entity type, directly under the manşet: tabs while there are two or
/// three types (the built-in people and places, plus at most one custom type), a labeled
/// "Tür" menu once the vault's custom types bring the count to four.
///
/// Draws no horizontal page margin of its own (`.inkListRow()` in a `List`).
struct EntityTypePicker: View {
    let store: IndexStore
    @Binding var selection: String
    @Environment(\.locale) private var locale

    private var choices: [EntityTypeChoice] {
        EntityTypeChoices.choices(store.entityTypes, language: locale.language.languageCode?.identifier ?? "en")
    }

    var body: some View {
        let choices = choices
        Group {
            if InkTabsChrome.fits(count: choices.count) {
                InkTabs(
                    selection: $selection,
                    items: choices.map {
                        InkTabItem(verbatim: $0.plural, value: $0.id, identifier: "tab.entities." + $0.id)
                    },
                    identifier: "tabs.entities.kind",
                    accessibilityLabelPrefix: String(localized: "Tür")
                )
            } else {
                InkLabeledMenu(
                    "Tür", selection: $selection,
                    options: choices.map { InkMenuOption(verbatim: $0.plural, value: $0.id) },
                    identifier: "menu.entities.kind")
            }
        }
        .onChange(of: store.entityTypes.allTypes, initial: true) { _, _ in
            selection = EntityTypeChoices.selection(selection, in: store.entityTypes)
        }
    }
}
