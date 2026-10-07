import SwiftUI

struct EntityAliasesEditor: View {
    struct Alias: Identifiable {
        let id = UUID()
        var text: String
    }
    let model: EntityDetailModel
    @Environment(\.entityEditorDraft) private var draft
    @State private var values: [Alias]
    @State private var saved: [String]
    @State private var saveFailed = false

    private let draftID = "aliases"

    init(model: EntityDetailModel) {
        self.model = model
        _values = State(initialValue: model.aliases.map { Alias(text: $0) })
        _saved = State(initialValue: model.aliases)
    }

    private var isDirty: Bool {
        values.map(\.text) != saved
    }

    var body: some View {
        VStack(alignment: .leading) {
            ForEach($values) { $alias in
                HStack {
                    TextField("Takma ad", text: $alias.text)
                    Button("Kaldır", systemImage: "minus.circle") { values.removeAll { $0.id == alias.id } }
                        .labelStyle(.iconOnly)
                }
            }
            HStack {
                Button("Takma ad ekle") { values.append(Alias(text: "")) }
                Button("Kaydet") {
                    let aliases = values.map(\.text)
                    Task {
                        let success = await model.saveAliases(aliases)
                        saveFailed = !success
                        if success { saved = aliases }
                        draft?.report(id: draftID, dirty: isDirty)
                    }
                }
            }
            if saveFailed {
                Text(
                    verbatim: model.errorText
                        ?? String(localized: "Değişiklik kaydedilemedi. Kasayı kontrol edip yeniden dene.")
                )
                .font(.ink.meta).foregroundStyle(.ink.danger)
            }
        }
        // Inside a List row every bordered button fires on one tap; borderless keeps them separate.
        .buttonStyle(.borderless)
        .disabled(!model.canEdit || !model.aliasesEditable)
        .onAppear { draft?.report(id: draftID, dirty: isDirty) }
        .onChange(of: values.map(\.text)) { draft?.report(id: draftID, dirty: isDirty) }
        .onChange(of: saved) { draft?.report(id: draftID, dirty: isDirty) }
    }
}
