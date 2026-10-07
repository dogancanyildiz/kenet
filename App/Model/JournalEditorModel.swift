import Foundation
import Observation
import VaultFormat
import VaultStore

@MainActor @Observable
final class JournalEditorModel {
    let store: IndexStore
    let day: CalendarDate
    var text = ""
    private(set) var originalText = ""
    private(set) var isLoaded = false
    private(set) var isSaving = false
    private(set) var errorText: String?
    private var root: URL?

    init(store: IndexStore, day: CalendarDate) {
        self.store = store
        self.day = day
    }

    var isDirty: Bool { !text.utf8.elementsEqual(originalText.utf8) }
    var canSave: Bool { isLoaded && !isSaving && store.canAddEvent && store.vaultURL == root }

    func load() async {
        guard !isLoaded else { return }
        let selectedRoot = store.vaultURL
        do {
            let document = try await store.dayDocument(for: day)
            guard store.vaultURL == selectedRoot else { throw VaultStoreError.staleTarget }
            text = try JournalRecognition.body(of: document)
            originalText = text
            root = selectedRoot
            isLoaded = true
            errorText = nil
        } catch { errorText = DayEditError.message(for: error) }
    }

    /// Returns true for no-op saves and persisted edits, even when indexing fails.
    @discardableResult
    func save() async -> Bool {
        guard canSave else { return false }
        guard isDirty else {
            errorText = nil
            return true
        }
        let draft = text
        isSaving = true
        errorText = nil
        defer { isSaving = false }
        var linked = draft
        do {
            let document = try await store.dayDocument(for: day)
            guard store.vaultURL == root,
                try JournalRecognition.body(of: document).utf8.elementsEqual(originalText.utf8)
            else {
                await store.refresh()
                throw VaultStoreError.staleTarget
            }
            linked = try JournalRecognition.linkingChanges(in: draft, from: originalText, entities: store.knownEntities)
            try await store.changeJournal(on: day, to: linked)
            await acceptSaved(draft: draft, linked: linked)
            return true
        } catch VaultStoreError.indexUpdateFailed {
            await acceptSaved(draft: draft, linked: linked)
            errorText = DayEditError.message(
                for: VaultStoreError.indexUpdateFailed(
                    path: "journal/\(day).md", underlying: CocoaError(.fileReadUnknown)))
            return true
        } catch {
            errorText = DayEditError.message(for: error)
            return false
        }
    }

    private func acceptSaved(draft: String, linked: String) async {
        var saved = linked
        if store.vaultURL == root, let document = try? await store.dayDocument(for: day),
            let body = try? JournalRecognition.body(of: document)
        {
            saved = body
        }
        originalText = saved
        if text.utf8.elementsEqual(draft.utf8) { text = saved }
    }
}
