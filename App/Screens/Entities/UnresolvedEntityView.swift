import SwiftUI
import VaultStore

struct UnresolvedEntityView: View {
    let store: IndexStore
    @Environment(\.locale) private var locale
    @State private var model: UnresolvedEntityModel
    @State private var noteBody = ""
    @State private var isCreatingNote = false

    init(store: IndexStore, target: String) {
        self.store = store
        _model = State(initialValue: UnresolvedEntityModel(store: store, target: target))
    }

    private var masthead: InkPageTitleRow<EmptyView> {
        InkPageTitleRow("Bağlantı bulunamadı", byline: String(localized: "Bu ad için bir varlık oluştur."))
    }

    var body: some View {
        @Bindable var model = model
        if let path = model.createdNotePath {
            SearchNoteView(store: store, file: path)
        } else if let created = model.created {
            let entity =
                store.content.entities.first { $0.id == created.file }
                ?? EntitySummary(
                    id: created.file, kind: created.kind.rawValue, name: created.name, qualifier: created.qualifier,
                    aliases: [], incomingLinks: 0)
            EntityView(store: store, entity: entity).id(entity.id)
        } else {
            List {
                InkScrolledMasthead(masthead)
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
                    option("Kişi olarak ekle", kind: .person)
                    option("Konum olarak ekle", kind: .place)
                    ForEach(
                        EntityTypeChoices.choices(
                            store.entityTypes, language: locale.language.languageCode?.identifier ?? "en"
                        ).filter { $0.id != "person" && $0.id != "place" }
                    ) { type in
                        option("\(type.name) olarak ekle", kind: type.kind)
                    }
                    if isCreatingNote {
                        InkCard {
                            TextEditor(text: $noteBody)
                                .font(.ink.content)
                                .scrollContentBackground(.hidden)
                                .frame(minHeight: 140)
                                .padding(8)
                        }
                            .inkListRow()
                        Button("Notu oluştur") { Task { await model.createNote(body: noteBody) } }
                            .buttonStyle(InkPrimaryButtonStyle())
                            .disabled(model.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                            .inkListRow()
                    } else {
                        Button { isCreatingNote = true } label: {
                            HStack(spacing: 12) {
                                Rectangle().fill(Color.ink.secondaryText).frame(width: 18, height: 18)
                                    .frame(width: 32, height: 40)
                                Text("Not olarak oluştur").foregroundStyle(.ink.text)
                                Spacer()
                                Image(systemName: "chevron.right").font(.caption).foregroundStyle(.ink.secondaryText)
                            }
                        }
                        .buttonStyle(.plain).inkListRow()
                    }
                }
                if let error = model.errorText {
                    Text(verbatim: error).font(.ink.meta).foregroundStyle(.ink.danger)
                        .inkListRow()
                }
            }
            .listStyle(.plain)
            // The list has no reading column of its own: the manşet spans it as the rows do.
            .inkPinnedMasthead(masthead, columnWidth: .infinity)
            .inkPage()
            .disabled(model.isCreating || !store.canAddEvent)
            .inkPageNavigationTitle("Bağlantı bulunamadı")
        }
    }

    private func option(_ title: LocalizedStringKey, kind: VaultEntityKind) -> some View {
        Button { Task { await model.create(kind) } } label: {
            HStack(spacing: 12) {
                GraphNodeShape(kind: graphKind(for: kind))
                    .fill(GraphNodeStyle.fill(graphKind(for: kind)))
                    .frame(width: 18, height: 18)
                    .frame(width: 32, height: 40)
                Text(title).foregroundStyle(.ink.text)
                Spacer()
                Image(systemName: "chevron.right").font(.caption).foregroundStyle(.ink.secondaryText)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .inkListRow()
    }

    private func graphKind(for kind: VaultEntityKind) -> GraphNode.Kind {
        switch kind {
        case .person: .person
        case .place: .place
        case .custom(let id): .custom(id)
        }
    }
}
