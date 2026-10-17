import Foundation
import Observation
import VaultFormat
import VaultStore

struct EntityTypeFieldDraft: Identifiable {
    let id = UUID()
    var key = ""
    var kind = EntityTypeField.Kind.text
}

@MainActor @Observable final class EntityTypeEditorModel {
    let store: IndexStore
    private let root: URL?
    private(set) var original: EntityTypeDefinition?
    var id: String {
        // A gallery draft's template is named after its id until the user names it.
        didSet { if templateFollowsID { template = Self.templatePath(for: id) } }
    }
    var folder: String
    var nameTR: String
    var nameEN: String
    var pluralTR: String
    var pluralEN: String
    var icon: String
    var template: String {
        didSet { templateFollowsID = isGalleryDraft && template == Self.templatePath(for: id) }
    }
    var fields: [EntityTypeFieldDraft]
    private(set) var errorText: String?
    private(set) var isSaving = false
    @ObservationIgnored private var isGalleryDraft = false
    @ObservationIgnored private var templateFollowsID = false

    /// `draft` fills a new type's fields (a gallery item) without making it an edit: `original`
    /// stays `nil`, so saving creates the type.
    init(store: IndexStore, original: EntityTypeDefinition? = nil, draft: EntityTypeDefinition? = nil) {
        self.store = store
        root = store.vaultURL
        self.original = original
        let filled = original ?? draft
        id = filled?.id ?? ""
        folder = filled?.folder ?? ""
        nameTR = filled?.name.tr ?? ""
        nameEN = filled?.name.en ?? ""
        pluralTR = filled?.plural.tr ?? ""
        pluralEN = filled?.plural.en ?? ""
        icon = filled?.icon ?? "square.stack"
        template = filled?.template ?? ""
        fields = filled?.fields.map { EntityTypeFieldDraft(key: $0.key, kind: $0.kind) } ?? []
        isGalleryDraft = original == nil && draft != nil
        templateFollowsID = isGalleryDraft && template == Self.templatePath(for: id)
    }

    private static func templatePath(for id: String) -> String {
        "templates/" + id.trimmingCharacters(in: .whitespacesAndNewlines) + ".md"
    }

    /// A new type whose template path the app does not write: only files under the root
    /// `templates/` folder are created (`VaultStore.creatingEntityType`).
    var templateIsNotWritten: Bool {
        let path = template.trimmingCharacters(in: .whitespacesAndNewlines)
        return original == nil && !path.isEmpty && !path.hasPrefix("templates/")
    }

    var definition: EntityTypeDefinition {
        func clean(_ text: String) -> String { text.trimmingCharacters(in: .whitespacesAndNewlines) }
        return EntityTypeDefinition(
            id: clean(id), folder: clean(folder), name: .init(tr: clean(nameTR), en: clean(nameEN)),
            plural: .init(tr: clean(pluralTR), en: clean(pluralEN)), icon: clean(icon),
            fields: fields.map { EntityTypeField(key: clean($0.key), kind: $0.kind) },
            template: clean(template).isEmpty ? nil : clean(template))
    }

    var canSave: Bool {
        store.canAddEvent && store.vaultURL == root && !isSaving && (try? definition.validate()) != nil
    }

    func save() async -> Bool {
        guard canSave else { return false }
        isSaving = true
        defer { isSaving = false }
        do {
            // A new type also gets its starter template when that file is still missing.
            if let original {
                try await store.saveEntityType(definition, replacing: original)
            } else {
                try await store.createEntityType(definition)
            }
            return true
        } catch is EntityTypeTemplateError {
            errorText = String(localized: "Tip kaydedildi, şablon dosyası yazılamadı.")
            original = definition
            return false
        } catch VaultStoreError.indexUpdateFailed {
            errorText = String(localized: "Tip kaydedildi, indeks güncellenemedi. Yeniden indeksle.")
            original = definition
            await store.refresh(rebuild: true)
            return store.errorText == nil
        } catch {
            errorText = String(localized: "Tip kaydedilemedi. Tanımları kontrol edip yeniden dene.")
            return false
        }
    }
}
