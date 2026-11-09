import SwiftUI
import VaultFormat
import VaultStore

struct EntityTypesSettingsView: View {
    let store: IndexStore
    @Environment(\.locale) private var locale
    @State private var deleting: EntityTypeDefinition?
    @State private var editing: EditorTarget?
    /// "Yeni varlık tipi" opens the gallery of ready-made types; editing opens the editor directly.
    @State private var showsGallery = false
    @State private var errorText: String?

    var body: some View {
        List {
            #if os(iOS)
                InkPageTitleRow("Varlık tipleri")
            #endif
            Section {
                SectionHeader("Yerleşik tipler")
                    .inkListRow()
                let builtIn = EntityTypeChoices.choices(store.entityTypes).filter {
                    $0.id == "person" || $0.id == "place"
                }
                InkCard(padded: false) {
                    VStack(alignment: .leading, spacing: 0) {
                        ForEach(Array(builtIn.enumerated()), id: \.element.id) { index, type in
                            if index > 0 { InkCardDivider() }
                            Label(type.plural, systemImage: type.definition.icon)
                                .frame(maxWidth: .infinity, minHeight: InkButtonChrome.minimumHeight, alignment: .leading)
                                .padding(.horizontal, InkSpacing.cardPadding)
                        }
                    }
                }
                .inkListRow()
            }
            Section {
                SectionHeader("Özel varlık tipleri")
                    .inkListRow()
                InkCard(padded: false) {
                    VStack(alignment: .leading, spacing: 0) {
                        if store.entityTypes.types.isEmpty {
                            Text("Henüz özel tip yok.")
                                .font(.ink.meta)
                                .foregroundStyle(Color.ink.secondaryText)
                                .frame(maxWidth: .infinity, minHeight: InkButtonChrome.minimumHeight, alignment: .leading)
                                .padding(.horizontal, InkSpacing.cardPadding)
                        }
                        ForEach(Array(store.entityTypes.types.enumerated()), id: \.element.id) {
                            index, type in
                            if index > 0 { InkCardDivider() }
                            HStack {
                                Button {
                                    editing = EditorTarget(original: type)
                                } label: {
                                    Label(
                                        type.name.localized(
                                            language: locale.language.languageCode?.identifier ?? "en"),
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
                            .frame(minHeight: InkButtonChrome.minimumHeight)
                            .padding(.horizontal, InkSpacing.cardPadding)
                        }
                        InkCardDivider()
                        Button("Yeni varlık tipi") { showsGallery = true }
                            .buttonStyle(.borderless)
                            .disabled(!store.canAddEvent || store.entityTypes.issue != nil)
                            .frame(maxWidth: .infinity, minHeight: InkButtonChrome.minimumHeight, alignment: .leading)
                            .padding(.horizontal, InkSpacing.cardPadding)
                    }
                }
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
            showsGallery = false
            errorText = nil
        }
        .entityTypeGallerySheet(isPresented: $showsGallery, store: store) { _ in }
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
