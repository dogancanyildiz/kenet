import SwiftUI
import VaultFormat

/// One gallery row: a ready-made type, or why it cannot be added again.
struct EntityTypeGalleryRow: Identifiable, Hashable {
    let definition: EntityTypeDefinition
    let language: String
    /// A type with this id or folder is already in the vault.
    let isTaken: Bool
    var id: String { definition.id }
    var name: String { definition.name.localized(language: language) }
    /// The field keys as they are written into the files ("yazar, sayfa, puan, bitirme").
    var fieldSummary: String { definition.fields.map(\.key).joined(separator: ", ") }
}

enum EntityTypeGalleryRows {
    static func rows(_ catalog: EntityTypeCatalog, language: String) -> [EntityTypeGalleryRow] {
        EntityTypeGallery.items.map {
            EntityTypeGalleryRow(
                definition: $0.definition, language: language, isTaken: $0.isTaken(by: catalog.allTypes))
        }
    }
}

/// The "Yeni tip…" entry under the Kişiler ve Konumlar create row (phone list, split-shell and
/// Mac column): opens the gallery.
enum EntityTypeGalleryEntry {
    static let identifier = "button.entities.newType"
    static let systemImage = "plus.square.on.square"

    @MainActor static func isEnabled(_ store: IndexStore) -> Bool {
        store.canAddEvent && store.entityTypes.issue == nil
    }
}

/// "Varlık tipi ekle": the ten ready-made types, then "Boş tip…". A row pushes the type editor
/// filled with that type (id, folder and names stay editable); saving there writes the
/// definition and its template, and closes the gallery. "Vazgeç" in the editor returns here.
struct EntityTypeGalleryView: View {
    let store: IndexStore
    let onSaved: (EntityTypeDefinition) -> Void
    @Environment(\.dismiss) private var dismiss
    @Environment(\.locale) private var locale
    @State private var draft: GalleryDraft?

    /// `opening` pushes the editor for that type at once (previews and snapshots).
    init(
        store: IndexStore, opening definition: EntityTypeDefinition? = nil,
        onSaved: @escaping (EntityTypeDefinition) -> Void
    ) {
        self.store = store
        self.onSaved = onSaved
        _draft = State(initialValue: definition.map { GalleryDraft(definition: $0) })
    }

    var body: some View {
        List {
            InkPageTitleRow("Varlık tipi ekle")
            Section {
                SectionHeader("Hazır tipler")
                    .inkListRow()
                ForEach(
                    EntityTypeGalleryRows.rows(
                        store.entityTypes, language: locale.language.languageCode?.identifier ?? "en")
                ) { row in
                    itemButton(row)
                }
            }
            Section {
                Button {
                    draft = GalleryDraft(definition: nil)
                } label: {
                    Label("Boş tip…", systemImage: "square.dashed")
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .tapTarget()
                        .contentShape(Rectangle())
                }
                .buttonStyle(.borderless)
                .accessibilityIdentifier("button.entityTypeGallery.blank")
                .inkListRow()
            }
            Text("Hazır tip, alanları boş bir şablonla gelir. Kaydetmeden önce her değeri değiştirebilirsin.")
                .font(.ink.meta)
                .foregroundStyle(Color.ink.secondaryText)
                .inkListRow()
        }
        .disabled(!EntityTypeGalleryEntry.isEnabled(store))
        .listStyle(.plain)
        .inkPageScrollColumn()
        .inkSheet("Varlık tipi ekle", cancelIdentifier: "button.entityTypeGallery.cancel")
        .navigationDestination(item: $draft) { draft in
            EntityTypeEditorView(model: EntityTypeEditorModel(store: store, draft: draft.definition)) { saved in
                onSaved(saved)
                dismiss()
            }
            // The editor's "Vazgeç" leads back here (asking first when the draft changed).
            .navigationBarBackButtonHidden(true)
        }
    }

    private func itemButton(_ row: EntityTypeGalleryRow) -> some View {
        Button {
            draft = GalleryDraft(definition: row.definition)
        } label: {
            MarginRow(kind: .external) {
                Image(systemName: row.definition.icon)
                    .foregroundStyle(row.isTaken ? Color.ink.secondaryText : Color.ink.accent)
                    .accessibilityHidden(true)
            } primary: {
                Text(verbatim: row.name)
                    .foregroundStyle(row.isTaken ? Color.ink.secondaryText : Color.ink.text)
            } secondary: {
                VStack(alignment: .leading, spacing: 2) {
                    Text(verbatim: row.fieldSummary)
                    if row.isTaken {
                        Text("Zaten var")
                    }
                }
                .font(.ink.meta)
                .foregroundStyle(Color.ink.secondaryText)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(row.isTaken)
        .accessibilityIdentifier("button.entityTypeGallery." + row.id)
        .inkListRow()
    }
}

/// One push of the editor; a fresh identity per tap gives it a fresh model. `nil`: a blank type.
private struct GalleryDraft: Identifiable, Hashable {
    let id = UUID()
    let definition: EntityTypeDefinition?
}

extension View {
    /// Presents ``EntityTypeGalleryView`` while `isPresented`; `onSaved` gets the new type.
    func entityTypeGallerySheet(
        isPresented: Binding<Bool>, store: IndexStore, onSaved: @escaping (EntityTypeDefinition) -> Void
    ) -> some View {
        sheet(isPresented: isPresented) {
            NavigationStack {
                EntityTypeGalleryView(store: store, onSaved: onSaved)
            }
            #if os(macOS)
                .frame(minWidth: InkSpacing.macSettingsMinWidth, minHeight: InkSpacing.macSettingsMinHeight)
            #endif
        }
    }
}
