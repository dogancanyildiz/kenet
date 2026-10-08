import SwiftUI
import VaultFormat
import VaultStore

struct EntityTypesSettingsView: View {
    let store: IndexStore
    @Environment(\.locale) private var locale
    @State private var deleting: EntityTypeDefinition?
    @State private var editing: EditorTarget?
    @State private var errorText: String?

    var body: some View {
        List {
            #if os(iOS)
                InkPageTitleRow("Varlık tipleri")
            #endif
            Section {
                SectionHeader("Yerleşik tipler")
                    .inkListRow()
                ForEach(EntityTypeChoices.choices(store.entityTypes).filter { $0.id == "person" || $0.id == "place" }) {
                    type in
                    Label(type.plural, systemImage: type.definition.icon)
                        .inkListRow()
                }
            }
            Section {
                SectionHeader("Özel varlık tipleri")
                    .inkListRow()
                if store.entityTypes.types.isEmpty {
                    Text("Henüz özel tip yok.")
                        .inkListRow()
                }
                ForEach(store.entityTypes.types, id: \.id) { type in
                    HStack {
                        Button {
                            editing = EditorTarget(original: type)
                        } label: {
                            Label(
                                type.name.localized(language: locale.language.languageCode?.identifier ?? "en"),
                                systemImage: type.icon
                            )
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .tapTarget()
                            .contentShape(Rectangle())
                        }
                        .accessibilityHint(Text("Varlık tipini düzenle"))
                        Button("Tipi sil", role: .destructive) { deleting = type }
                            .buttonStyle(InkDestructiveButtonStyle())
                    }
                    .buttonStyle(.borderless)
                    .inkListRow()
                }
                Button("Yeni varlık tipi") { editing = EditorTarget(original: nil) }
                    .buttonStyle(.borderless)
                    .disabled(!store.canAddEvent || store.entityTypes.issue != nil)
                    .inkListRow()
            }
            if store.entityTypes.issue != nil {
                Text(
                    "Varlık tipleri okunamıyor. Yalnız yerleşik tipler kullanılıyor. Kasadaki .app/types.json dosyasını kontrol et."
                )
                .font(.ink.meta)
                .foregroundStyle(Color.ink.warning)
                .inkListRow()
            }
            if let errorText {
                Text(verbatim: errorText)
                    .font(.ink.meta)
                    .foregroundStyle(Color.ink.danger)
                    .inkListRow()
            }
            Text("Tipi silmek varlık dosyalarını silmez. Tanımı olmayan dosyalar düz not olarak kalır.")
                .font(.ink.meta)
                .foregroundStyle(Color.ink.secondaryText)
                .inkListRow()
        }
        .onChange(of: store.vaultURL) { _, _ in
            deleting = nil
            editing = nil
            errorText = nil
        }
        .sheet(item: $editing) { target in
            NavigationStack {
                EntityTypeEditorView(model: EntityTypeEditorModel(store: store, original: target.original))
            }
            #if os(macOS)
                .frame(minWidth: InkSpacing.macSettingsMinWidth, minHeight: InkSpacing.macSettingsMinHeight)
            #endif
        }
        .listStyle(.plain)
        .inkPageNavigationTitle("Varlık tipleri")
        .inkPageScrollColumn()
        .inkPage()
        .confirmationDialog(
            "Tip tanımını sil?", isPresented: Binding(get: { deleting != nil }, set: { if !$0 { deleting = nil } })
        ) {
            Button("Tipi sil", role: .destructive) {
                guard let type = deleting else { return }
                deleting = nil
                let root = store.vaultURL
                Task {
                    guard store.vaultURL == root else { return }
                    do { try await store.deleteEntityType(type) } catch VaultStoreError.indexUpdateFailed {
                        errorText = String(localized: "Tip silindi, indeks güncellenemedi. Yeniden indeksle.")
                        await store.refresh(rebuild: true)
                    } catch { errorText = String(localized: "Tip silinemedi. Tanımları kontrol edip yeniden dene.") }
                }
            }
        } message: {
            Text("Varlık dosyaları korunur.")
        }
    }
}

/// One presentation of the type editor; a fresh identity per tap gives the sheet a fresh model.
private struct EditorTarget: Identifiable {
    let id = UUID()
    let original: EntityTypeDefinition?
}
