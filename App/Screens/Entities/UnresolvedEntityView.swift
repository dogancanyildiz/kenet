import SwiftUI

struct UnresolvedEntityView: View {
    let store: IndexStore
    @Environment(\.locale) private var locale
    @State private var model: UnresolvedEntityModel

    init(store: IndexStore, target: String) {
        self.store = store
        _model = State(initialValue: UnresolvedEntityModel(store: store, target: target))
    }

    var body: some View {
        @Bindable var model = model
        if let created = model.created {
            let entity =
                store.content.entities.first { $0.id == created.file }
                ?? EntitySummary(
                    id: created.file, kind: created.kind.rawValue, name: created.name, qualifier: created.qualifier,
                    aliases: [], incomingLinks: 0)
            EntityView(store: store, entity: entity).id(entity.id)
        } else {
            List {
                InkPageTitleRow("Bağlantı bulunamadı", byline: String(localized: "Bu ad için bir varlık oluştur."))
                InkFilterField("Ad", text: $model.name)
                    .inkListRow()
                if model.needsQualifier {
                    InkFilterField("Ayırt edici (ör. iş)", text: $model.qualifier)
                        .inkListRow()
                    Button("Oluştur") { if let kind = model.kind { Task { await model.create(kind) } } }
                        .buttonStyle(InkTextButtonStyle())
                        .disabled(model.qualifier.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                        .inkListRow()
                } else {
                    Button("Kişi olarak ekle") { Task { await model.create(.person) } }
                        .buttonStyle(InkTextButtonStyle())
                        .inkListRow()
                    Button("Konum olarak ekle") { Task { await model.create(.place) } }
                        .buttonStyle(InkTextButtonStyle())
                        .inkListRow()
                    ForEach(
                        EntityTypeChoices.choices(
                            store.entityTypes, language: locale.language.languageCode?.identifier ?? "en"
                        ).filter { $0.id != "person" && $0.id != "place" }
                    ) { type in
                        Button {
                            Task { await model.create(type.kind) }
                        } label: {
                            Text("\(type.name) olarak ekle")
                        }
                        .buttonStyle(InkTextButtonStyle())
                        .inkListRow()
                    }
                }
                if let error = model.errorText {
                    Text(verbatim: error).font(.ink.meta).foregroundStyle(.ink.danger)
                        .inkListRow()
                }
            }
            .listStyle(.plain)
            .inkPage()
            .disabled(model.isCreating || !store.canAddEvent)
            .inkPageNavigationTitle("Bağlantı bulunamadı")
        }
    }
}
