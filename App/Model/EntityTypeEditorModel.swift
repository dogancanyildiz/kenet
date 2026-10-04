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
    var id: String
    var folder: String
    var nameTR: String
    var nameEN: String
    var pluralTR: String
    var pluralEN: String
    var icon: String
    var template: String
    var fields: [EntityTypeFieldDraft]
    private(set) var errorText: String?
    private(set) var isSaving = false

    init(store: IndexStore, original: EntityTypeDefinition? = nil) {
        self.store = store
        root = store.vaultURL
        self.original = original
        id = original?.id ?? ""
        folder = original?.folder ?? ""
        nameTR = original?.name.tr ?? ""
        nameEN = original?.name.en ?? ""
        pluralTR = original?.plural.tr ?? ""
        pluralEN = original?.plural.en ?? ""
        icon = original?.icon ?? "square.stack"
        template = original?.template ?? ""
        fields = original?.fields.map { EntityTypeFieldDraft(key: $0.key, kind: $0.kind) } ?? []
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
            try await store.saveEntityType(definition, replacing: original)
            return true
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
