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
    var templateID: GoalTemplate.ID?
    private(set) var isWriting = false
    private(set) var isSaved = false
    private(set) var errorText: String?

    /// Every key a definition holds (``IndexStore/computeReservedGoalKeys()``), empty until
    /// ``load()``. The preview only: creation reserves the keys on disk again.
    private(set) var reservedKeys: Set<String> = []

    init(store: IndexStore) {
        self.store = store
        root = store.vaultURL
    }

    /// Reads the reserved keys again; a read that fails, is cancelled or outlives its vault keeps them.
    func load() async {
        guard root == store.vaultURL, let keys = try? await store.computeReservedGoalKeys(), root == store.vaultURL
        else { return }
        reservedKeys = keys
    }

    var key: String { VaultStore.goalKey(for: name, reserving: reservedKeys) }
    var canSave: Bool {
        root != nil && root == store.vaultURL && !isWriting && !isSaved && store.canAddEvent
            && !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && (kind == .milestone || (GoalValueModel.number(target) ?? 0) > 0)
    }
    func apply(_ template: GoalTemplate, locale: Locale = .current) {
        name = template.localizedName(locale: locale)
        kind = template.kind
        period = template.period
        target = String(template.target)
        unit = template.localizedUnit(locale: locale) ?? ""
        templateID = template.id
    }

    static func matches(_ template: GoalTemplate, query: String, locale: Locale = .current) -> Bool {
        func folded(_ text: String) -> String {
            // Also accept an undotted uppercase I typed for a Turkish dotted i ("KITAP").
            text.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: locale)
                .replacingOccurrences(of: "ı", with: "i")
        }
        return query.isEmpty
            || folded(template.localizedName(locale: locale)).localizedStandardContains(folded(query))
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
