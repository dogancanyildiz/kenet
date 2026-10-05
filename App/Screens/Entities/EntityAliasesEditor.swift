import SwiftUI

struct EntityAliasesEditor: View {
    struct Alias: Identifiable {
        let id = UUID()
        var text: String
    }
    let model: EntityDetailModel
    @State private var values: [Alias]

    init(model: EntityDetailModel) {
        self.model = model
        _values = State(initialValue: model.aliases.map { Alias(text: $0) })
    }

    var body: some View {
        VStack(alignment: .leading) {
            ForEach($values) { $alias in
                HStack {
                    TextField("Takma ad", text: $alias.text)
                    Button("Kaldır", systemImage: "minus.circle") { values.removeAll { $0.id == alias.id } }.labelStyle(
                        .iconOnly)
                }
            }
            HStack {
                Button("Takma ad ekle") { values.append(Alias(text: "")) }
                Button("Kaydet") {
                    let aliases = values.map(\.text)
                    Task { await model.saveAliases(aliases) }
                }
            }
        }
        // Inside a List row every bordered button fires on one tap; borderless keeps them separate.
        .buttonStyle(.borderless)
        .disabled(!model.canEdit || !model.aliasesEditable)
    }
}
