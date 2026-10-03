import SwiftUI

/// The entity header is ready for a later timeline below it.
struct EntityView: View {
    let store: IndexStore
    let entity: EntitySummary

    private var current: EntitySummary { store.content.entities.first { $0.id == entity.id } ?? entity }

    var body: some View {
        Form {
            Section("Varlık") {
                LabeledContent("Ad") { Text(verbatim: current.name) }
                if let qualifier = current.qualifier {
                    LabeledContent("Ayırt edici") { Text(verbatim: qualifier) }
                }
                LabeledContent("Takma adlar") {
                    if current.aliases.isEmpty {
                        Text("Takma ad yok")
                    } else {
                        Text(verbatim: current.aliases.joined(separator: ", "))
                    }
                }
                LabeledContent("Gelen bağlantılar") { Text(current.incomingLinks, format: .number) }
            }
            Section { Text("Zaman akışı sonraki sürümde").foregroundStyle(.secondary) }
        }
        .formStyle(.grouped)
        .navigationTitle(current.name)
        .toolbar { SearchButton() }
    }
}
