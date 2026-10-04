import Foundation
import GoalTracking
import Observation
import VaultFormat
import VaultStore

/// Each save targets one frontmatter field; unsupported fields and the immutable key stay intact.
@MainActor @Observable
final class GoalDefinitionModel {
    let store: IndexStore
    let goal: GoalDefinition
    private let root: URL?
    private(set) var isWriting = false
    private(set) var errorText: String?
    var canEdit: Bool { root != nil && root == store.vaultURL && !isWriting && store.canAddEvent }

    init(store: IndexStore, goal: GoalDefinition) {
        self.store = store
        self.goal = goal
        root = store.vaultURL
    }

    func set(_ field: String, text: String) async -> Bool {
        guard canEdit else { return false }
        errorText = nil
        func invalid() -> Bool {
            errorText = String(localized: "Hedef tanımını kontrol et: ad boş olmamalı, miktar sıfırdan büyük olmalı.")
            return false
        }
        let clean = text.trimmingCharacters(in: .whitespacesAndNewlines)
        let literal: FrontmatterLiteral
        switch field {
        case "name", "unit":
            guard field == "unit" || !clean.isEmpty,
                !clean.unicodeScalars.contains(where: CharacterSet.controlCharacters.contains)
            else { return invalid() }
            if field == "name",
                store.content.goals.contains(where: {
                    $0.id != goal.id
                        && $0.name.precomposedStringWithCanonicalMapping.lowercased()
                            == clean.precomposedStringWithCanonicalMapping.lowercased()
                })
            {
                errorText = String(localized: "Bu ad zaten kullanılıyor. Başka bir ad seç.")
                return false
            }
            literal = .text(clean)
        case "period":
            guard goal.kind != .milestone || clean == "year" else { return invalid() }
            guard GoalPeriod(rawValue: clean) != nil else { return invalid() }
            literal = .text(clean)
        case "kind":
            guard clean != "milestone", goal.kind != .milestone else { return invalid() }
            guard GoalKind(rawValue: clean) != nil else { return invalid() }
            literal = .text(clean)
        case "target":
            guard goal.kind != .milestone else { return invalid() }
            guard let number = GoalValueModel.number(clean), number > 0 else { return invalid() }
            // Keep numeric spelling in the supported YAML decimal subset.
            guard !clean.lowercased().contains("e") else { return invalid() }
            literal = .number(clean.replacingOccurrences(of: ",", with: "."))
        default: return invalid()
        }
        isWriting = true
        defer { isWriting = false }
        errorText = nil
        do {
            let document = try await store.document(at: goal.id)
            guard root == store.vaultURL, !document.isReadOnly, case .parsed(let fields) = document.frontmatter,
                case .scalar(let type) = fields.field(named: "type")?.value, type.text == "goal",
                case .scalar(let key) = fields.field(named: "key")?.value, key.text == goal.key
            else { throw VaultStoreError.staleTarget }
            if field == "unit", clean.isEmpty {
                try await store.removeField(at: goal.id, key: field)
            } else {
                try await store.setField(at: goal.id, key: field, value: literal)
            }
            return true
        } catch {
            errorText = DayEditError.message(for: error)
            if case VaultStoreError.indexUpdateFailed = error { return true }
            return false
        }
    }
}
