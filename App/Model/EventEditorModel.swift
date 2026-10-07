import Foundation
import Observation
import VaultFormat
import VaultStore

@MainActor @Observable
final class EventEditorModel: Identifiable {
    let id = UUID()
    let store: IndexStore
    let day: CalendarDate
    let row: EventRow
    let composer: MentionComposer
    private(set) var target: LineBlock?
    private(set) var errorText: String?
    private(set) var isSaving = false
    private(set) var isSaved = false
    private var root: URL?

    var text: String {
        get { composer.text }
        set { composer.text = newValue }
    }

    init(store: IndexStore, day: CalendarDate, row: EventRow) {
        self.store = store
        self.day = day
        self.row = row
        self.composer = MentionComposer(store: store)
    }

    var canSave: Bool {
        target != nil && !isSaving && !composer.isCreating && store.canAddEvent && root == store.vaultURL
            && !text.allSatisfy(\.isWhitespace) && !text.contains(where: { $0.isNewline })
    }

    func load() async {
        guard target == nil && !isSaved else { return }
        let selectedRoot = store.vaultURL
        do {
            let block = try await store.eventTarget(on: day, row: row)
            guard store.vaultURL == selectedRoot else { throw VaultStoreError.staleTarget }
            target = block
            text = block.text
            root = selectedRoot
        } catch { errorText = DayEditError.message(for: error) }
    }

    @discardableResult
    func save() async -> Bool {
        guard canSave, let target else { return false }
        if isSaved {
            errorText = nil
            return true
        }
        guard composer.beginResolution() else { return false }
        let linked: String
        do {
            linked = try composer.linkedText()
        } catch {
            errorText = String(localized: "Anmalar bağlanamadı. Metni kontrol edip yeniden dene.")
            return false
        }
        if linked.utf8.elementsEqual(target.text.utf8) {
            composer.awaitingResolution = false
            return true
        }
        let saved = await write { try await self.store.changeEvent(on: self.day, target: target, to: linked) }
        if saved { text = linked }
        return saved
    }

    @discardableResult
    func delete() async -> Bool {
        guard let target, !isSaving, store.canAddEvent, root == store.vaultURL else { return false }
        if isSaved { return true }
        return await write { try await self.store.deleteEvent(on: self.day, target: target) }
    }

    private func write(_ operation: () async throws -> Void) async -> Bool {
        isSaving = true
        errorText = nil
        defer { isSaving = false }
        do {
            try await operation()
            isSaved = true
            composer.awaitingResolution = false
            return true
        } catch VaultStoreError.indexUpdateFailed {
            isSaved = true
            composer.awaitingResolution = false
            errorText = String(localized: "Değişiklik kaydedildi, indeks güncellenemedi.")
            return true
        } catch {
            if case VaultStoreError.staleTarget = error { target = nil }
            errorText = DayEditError.message(for: error)
            return false
        }
    }
}
