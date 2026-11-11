import SwiftUI
import VaultStore

struct UnresolvedEntityView: View {
    let store: IndexStore
    @Environment(\.locale) private var locale
    @State private var model: UnresolvedEntityModel

    init(store: IndexStore, target: String) {
        self.store = store
        _model = State(initialValue: UnresolvedEntityModel(store: store, target: target))
    }

    private var masthead: InkPageTitleRow<EmptyView> {
        InkPageTitleRow("Bağlantı bulunamadı", byline: String(localized: "Bu ad için bir sayfa oluştur."))
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
                InkFilterField("Ad", text: $model.name, showsClearButton: false)
                    .inkListRow()
                if model.needsQualifier {
                    InkFilterField("Ayırt edici (ör. iş)", text: $model.qualifier, showsClearButton: false)
                        .inkListRow()
                    Button("Oluştur") { if let kind = model.kind { Task { await model.create(kind) } } }
                        .buttonStyle(InkTextButtonStyle())
                        .disabled(model.qualifier.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                        .inkListRow()
                } else {
                    // One card of choices; each row leads with its Graph node shape (docs/screens.md).
                    InkCard(padded: false) {
                        VStack(spacing: 0) {
                            option("Kişi olarak ekle", kind: .person)
                            InkCardDivider()
                            option("Konum olarak ekle", kind: .place)
                            ForEach(customTypes) { type in
                                InkCardDivider()
                                option("\(type.name) olarak ekle", kind: type.kind)
                            }
                            InkCardDivider()
                            optionRow("Not olarak oluştur") {
                                Image(systemName: "doc.text")
                                    .font(.body)
                                    .foregroundStyle(.ink.secondaryText)
                            } action: {
                                Task { await model.createNote() }
                            }
                            .disabled(model.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                        }
                    }
                    .inkListRow()
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

    private var customTypes: [EntityTypeChoice] {
        EntityTypeChoices.choices(store.entityTypes, language: locale.language.languageCode?.identifier ?? "en")
            .filter { $0.id != "person" && $0.id != "place" }
    }

    private func option(_ title: LocalizedStringKey, kind: VaultEntityKind) -> some View {
        optionRow(title) {
            GraphNodeShape(kind: graphKind(for: kind))
                .fill(GraphNodeStyle.fill(graphKind(for: kind)))
                .frame(width: 18, height: 18)
                .accessibilityHidden(true)
        } action: {
            Task { await model.create(kind) }
        }
    }

    private func optionRow<Mark: View>(
        _ title: LocalizedStringKey, @ViewBuilder mark: () -> Mark, action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            HStack(spacing: 12) {
                mark().frame(width: 32).accessibilityHidden(true)
                Text(title).font(.ink.content).foregroundStyle(.ink.text)
                Spacer(minLength: 8)
                Image(systemName: "chevron.right").font(.ink.meta).foregroundStyle(.ink.secondaryText)
                    .accessibilityHidden(true)
            }
            .padding(.horizontal, InkSpacing.cardPadding)
            .frame(minHeight: TapTarget.minimumLength)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private func graphKind(for kind: VaultEntityKind) -> GraphNode.Kind {
        switch kind {
        case .person: .person
        case .place: .place
        case .custom(let id): .custom(id)
        }
    }
}
