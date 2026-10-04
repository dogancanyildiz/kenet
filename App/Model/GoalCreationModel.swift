import Foundation
import GoalTracking
import Observation
import VaultStore

@MainActor @Observable
final class GoalCreationModel {
    let store: IndexStore
    private let root: URL?
    var name = ""
    var period = GoalPeriod.day
    var kind = GoalKind.boolean
    var target = "1"
    var unit = ""
    private(set) var isWriting = false
    private(set) var isSaved = false
    private(set) var errorText: String?

    init(store: IndexStore) {
        self.store = store
        root = store.vaultURL
    }
    var key: String { VaultStore.goalKey(for: name, reserving: store.content.reservedGoalKeys) }
    var canSave: Bool {
        root != nil && root == store.vaultURL && !isWriting && !isSaved && store.canAddEvent
            && !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && (kind == .milestone || (GoalValueModel.number(target) ?? 0) > 0)
    }
    func save() async -> Bool {
        guard canSave, let target = kind == .milestone ? 1 : GoalValueModel.number(target) else { return false }
        isWriting = true
        defer { isWriting = false }
        errorText = nil
        do {
            try await store.createGoal(
                name: name, period: kind == .milestone ? .year : period, kind: kind, target: target,
                unit: kind == .number ? unit : nil)
            isSaved = true
        } catch VaultStoreError.nameTaken {
            errorText = String(localized: "Bu ad zaten kullanılıyor. Başka bir ad seç.")
        } catch {
            errorText = DayEditError.message(for: error)
            if case VaultStoreError.indexUpdateFailed = error { isSaved = true }
        }
        return isSaved
    }
}
