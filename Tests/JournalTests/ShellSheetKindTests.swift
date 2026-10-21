import Foundation
import SwiftUI
import Testing
import VaultFormat

@testable import Journal

/// The decisions behind each shell sheet's kind (read-only / editing-save / editing-create /
/// cancel-only) and its draft. What the mounted sheets really show and do on the Mac:
/// `ShellSheetKindHostedTests`.
@MainActor struct ShellSheetKindTests {
    // MARK: - Editing: "Vazgeç" / "Kaydet" or "Oluştur"

    @Test func entityTypeEditorCreatesANewTypeAndSavesAnExistingOne() {
        #expect(EntityTypeEditorView.confirmation(isNew: true) == .create)
        #expect(EntityTypeEditorView.confirmation(isNew: false) == .save)
    }

    // MARK: - Cancel-only: vault preparation

    @Test func vaultPreparationBarAndButtonsFollowTheWrite() {
        // "Vazgeç" until the result is in; then the bar is empty and "Kasayı aç" is the way out.
        #expect(VaultImportChrome.showsCancel(hasResult: false, openFailed: false))
        #expect(!VaultImportChrome.showsCancel(hasResult: true, openFailed: false))
        // Opening the prepared vault failed: "Vazgeç" returns and the sheet can be swiped away.
        #expect(VaultImportChrome.openFailed(hasResult: true, hasError: true))
        #expect(!VaultImportChrome.openFailed(hasResult: false, hasError: true))
        #expect(VaultImportChrome.showsCancel(hasResult: true, openFailed: true))
        #expect(!VaultImportChrome.blocksInteractiveDismiss(hasResult: true, isWriting: false, openFailed: true))
        #expect(VaultImportChrome.blocksInteractiveDismiss(hasResult: true, isWriting: false, openFailed: false))
        #expect(VaultImportChrome.blocksInteractiveDismiss(hasResult: true, isWriting: true, openFailed: true))
        #expect(InkSheetChrome.cancelOnlyButtons(showsCancel: true) == [.cancel])
        #expect(InkSheetChrome.cancelOnlyButtons(showsCancel: false).isEmpty)

        #expect(!VaultImportChrome.isWriting(isApplying: false, isProcessing: false))
        #expect(VaultImportChrome.isWriting(isApplying: true, isProcessing: false))
        #expect(VaultImportChrome.isWriting(isApplying: false, isProcessing: true))

        #expect(VaultImportChrome.canApply(canPrepare: true, isWriting: false))
        #expect(!VaultImportChrome.canApply(canPrepare: false, isWriting: false))
        #expect(!VaultImportChrome.canApply(canPrepare: true, isWriting: true))

        #expect(!VaultImportChrome.blocksInteractiveDismiss(hasResult: false, isWriting: false, openFailed: false))
        #expect(VaultImportChrome.blocksInteractiveDismiss(hasResult: true, isWriting: false, openFailed: false))
        #expect(VaultImportChrome.blocksInteractiveDismiss(hasResult: false, isWriting: true, openFailed: false))
    }

    // MARK: - Component additions

    @Test func disabledCancelIsDrawnDisabled() {
        #expect(InkSheetChrome.token(for: .cancel) == .secondaryText)
        #expect(InkSheetChrome.token(for: .cancel, isEnabled: false) == .control)
        #expect(InkSheetChrome.token(for: .confirm, isEnabled: false) == .secondaryText)
    }

    // MARK: - Dirty draft

    @Test func entityTypeDraftIsDirtyOnlyAfterAChange() throws {
        let context = try TaskTestContext()
        defer { context.clean() }
        let model = EntityTypeEditorModel(store: context.store)
        let opened = EntityTypeDraftSnapshot(model)
        #expect(!EntityTypeDraftSnapshot(model).isDirty(since: opened), "a fresh sheet closes without asking")

        model.nameTR = "Albüm"
        #expect(EntityTypeDraftSnapshot(model).isDirty(since: opened))
        model.nameTR = ""
        #expect(!EntityTypeDraftSnapshot(model).isDirty(since: opened), "typed and undone")

        model.fields.append(EntityTypeFieldDraft())
        #expect(EntityTypeDraftSnapshot(model).isDirty(since: opened), "an added empty field")
        model.fields.removeAll()
        #expect(!EntityTypeDraftSnapshot(model).isDirty(since: opened))

        for change: (EntityTypeEditorModel) -> Void in [
            { $0.id = "a" }, { $0.folder = "a" }, { $0.nameEN = "a" }, { $0.pluralTR = "a" },
            { $0.pluralEN = "a" }, { $0.icon = "book" }, { $0.template = "a" },
        ] {
            let fresh = EntityTypeEditorModel(store: context.store)
            let before = EntityTypeDraftSnapshot(fresh)
            change(fresh)
            #expect(EntityTypeDraftSnapshot(fresh).isDirty(since: before))
        }
    }

    @Test func entityTypeDraftSeesFieldNameAndKindChanges() throws {
        let context = try TaskTestContext()
        defer { context.clean() }
        let definition = EntityTypeDefinition(
            id: "book", folder: "books", name: .init(tr: "Kitap", en: "Book"),
            plural: .init(tr: "Kitaplar", en: "Books"), icon: "book",
            fields: [EntityTypeField(key: "yazar", kind: .text)], template: nil)
        let model = EntityTypeEditorModel(store: context.store, original: definition)
        let opened = EntityTypeDraftSnapshot(model)
        #expect(!EntityTypeDraftSnapshot(model).isDirty(since: opened), "an existing type opens clean")
        model.fields[0].kind = .date
        #expect(EntityTypeDraftSnapshot(model).isDirty(since: opened))
        model.fields[0].kind = .text
        model.fields[0].key = "yazarlar"
        #expect(EntityTypeDraftSnapshot(model).isDirty(since: opened))
        // A removed and re-added field with the same content is the same draft.
        model.fields = [EntityTypeFieldDraft(key: "yazar", kind: .text)]
        #expect(!EntityTypeDraftSnapshot(model).isDirty(since: opened))
    }

    /// The discard dialog's words reach the built app in both languages.
    @Test func entityTypeEditorDiscardWordsAreTranslated() {
        for key in ["Değişiklikleri at", "Düzenlemeye devam et", "Tip kimliği", "Klasör", "ör. %@"] {
            for language in ["tr", "en"] {
                #expect(CatalogLookup.hasTranslation(key, language: language), "\(key) has no \(language) entry")
            }
        }
    }
}
