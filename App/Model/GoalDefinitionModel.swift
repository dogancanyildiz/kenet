import Foundation
import GoalTracking
import Observation
import VaultFormat
import VaultIndex
import VaultStore

/// A frontmatter field the definition form edits. The key is never one of them.
enum GoalEditableField: String, Identifiable, CaseIterable {
    case name, period, kind, target, unit
    var id: Self { self }
    var title: String {
        switch self {
        case .name: String(localized: "Ad")
        case .period: String(localized: "Dönem")
        case .kind: String(localized: "Tür")
        case .target: String(localized: "Hedef miktar")
        case .unit: String(localized: "Birim")
        }
    }
}

/// What the definition form holds before "Kaydet". Nothing here writes.
struct GoalDefinitionDraft: Equatable {
    var name: String
    var period: GoalPeriod
    var kind: GoalKind
    var target: String
    var unit: String

    init(goal: GoalDefinition) {
        name = goal.name
        period = goal.period
        kind = goal.kind
        target = Self.spelling(goal.target)
        unit = goal.unit ?? ""
    }

    /// A whole amount without the fraction ("8", not "8.0"); other amounts as Swift spells them.
    static func spelling(_ value: Double) -> String {
        value.rounded() == value && abs(value) < 1e15 ? String(Int64(value)) : String(value)
    }
}

/// One field "Kaydet" writes, with the text ``GoalDefinitionModel/set(_:text:)`` takes.
struct GoalDefinitionChange: Equatable {
    let field: GoalEditableField
    let text: String
}

/// Each save targets one frontmatter field; unsupported fields and the immutable key stay intact.
@MainActor @Observable
final class GoalDefinitionModel {
    let store: IndexStore
    let goal: GoalDefinition
    private let root: URL?
    private(set) var isWriting = false
    private(set) var errorText: String?
    /// The other goals' names, compared as the name check compares them, as the index last listed
    /// them (``load()``); nil until then, and nothing is written while they are unknown.
    private var takenNames: Set<String>?
    /// The last read of the names failed; its message is the one in `errorText`.
    private var loadFailed = false
    var canEdit: Bool { root != nil && root == store.vaultURL && !isWriting && store.canAddEvent }
    /// A field can be written: editing is possible and the name check has the other names.
    private var canWrite: Bool { canEdit && takenNames != nil }

    /// A milestone stays a yearly milestone: its period and kind are shown, not edited.
    var isScheduleLocked: Bool { goal.kind == .milestone }

    init(store: IndexStore, goal: GoalDefinition) {
        self.store = store
        self.goal = goal
        root = store.vaultURL
    }

    /// Reads the other goals' names from the index (``IndexStore/computeGoalDefinitions()``). A
    /// read that is cancelled or outlives its vault keeps the names as they were; a failed read
    /// keeps them too and says why "Kaydet" may stay off.
    func load() async {
        guard root == store.vaultURL else { return }
        let rows: [GoalDefinitionRow]
        do { rows = try await store.computeGoalDefinitions() } catch is CancellationError { return } catch {
            if root == store.vaultURL {
                errorText = DayEditError.message(for: error)
                loadFailed = true
            }
            return
        }
        guard root == store.vaultURL else { return }
        if loadFailed {
            errorText = nil
            loadFailed = false
        }
        takenNames = Set(rows.map(\.definition).filter { $0.id != goal.id }.map { Self.comparisonName($0.name) })
    }

    private static func comparisonName(_ name: String) -> String {
        name.precomposedStringWithCanonicalMapping.lowercased()
    }

    private enum Check {
        case valid(FrontmatterLiteral, clean: String)
        case invalid
        case nameTaken
    }

    private func check(_ field: String, text: String) -> Check {
        let clean = text.trimmingCharacters(in: .whitespacesAndNewlines)
        switch field {
        case "name", "unit":
            guard field == "unit" || !clean.isEmpty,
                !clean.unicodeScalars.contains(where: CharacterSet.controlCharacters.contains)
            else { return .invalid }
            if field == "name", takenNames?.contains(Self.comparisonName(clean)) == true {
                return .nameTaken
            }
            return .valid(.text(clean), clean: clean)
        case "period":
            guard goal.kind != .milestone || clean == "year" else { return .invalid }
            guard GoalPeriod(rawValue: clean) != nil else { return .invalid }
            return .valid(.text(clean), clean: clean)
        case "kind":
            guard clean != "milestone", goal.kind != .milestone else { return .invalid }
            guard GoalKind(rawValue: clean) != nil else { return .invalid }
            return .valid(.text(clean), clean: clean)
        case "target":
            guard goal.kind != .milestone else { return .invalid }
            guard let number = GoalValueModel.number(clean), number > 0 else { return .invalid }
            // Keep numeric spelling in the supported YAML decimal subset.
            guard !clean.lowercased().contains("e") else { return .invalid }
            return .valid(.number(clean.replacingOccurrences(of: ",", with: ".")), clean: clean)
        default: return .invalid
        }
    }

    /// Reads the names again first: the check sees every goal published until now.
    func set(_ field: String, text: String) async -> Bool {
        await load()
        guard canWrite else { return false }
        errorText = nil
        switch check(field, text: text) {
        case .invalid:
            errorText = String(localized: "Hedef tanımını kontrol et: ad boş olmamalı, miktar sıfırdan büyük olmalı.")
            return false
        case .nameTaken:
            errorText = String(localized: "Bu ad zaten kullanılıyor. Başka bir ad seç.")
            return false
        case .valid(let literal, let clean):
            isWriting = true
            defer { isWriting = false }
            return await write([FieldWrite(field: field, literal: literal, clean: clean)])
        }
    }

    // MARK: - Definition form

    /// The fields whose draft differs from the definition, in write order. An amount is compared
    /// as a number, text after trimming; the period and kind of a milestone never count.
    func changes(in draft: GoalDefinitionDraft) -> [GoalDefinitionChange] {
        var changes: [GoalDefinitionChange] = []
        let name = draft.name.trimmingCharacters(in: .whitespacesAndNewlines)
        if name != goal.name { changes.append(GoalDefinitionChange(field: .name, text: name)) }
        if !isScheduleLocked {
            if draft.period != goal.period {
                changes.append(GoalDefinitionChange(field: .period, text: draft.period.rawValue))
            }
            if draft.kind != goal.kind {
                changes.append(GoalDefinitionChange(field: .kind, text: draft.kind.rawValue))
            }
            if GoalValueModel.number(draft.target) != goal.target {
                changes.append(GoalDefinitionChange(field: .target, text: draft.target))
            }
        }
        let unit = draft.unit.trimmingCharacters(in: .whitespacesAndNewlines)
        if showsUnit(draft), unit != (goal.unit ?? "") {
            changes.append(GoalDefinitionChange(field: .unit, text: unit))
        }
        return changes
    }

    /// The unit field is on the form for a number goal or when the file has a unit. A hidden
    /// field is never written: switching to "evet / hayır" leaves a typed unit out of the file.
    func showsUnit(_ draft: GoalDefinitionDraft) -> Bool { draft.kind == .number || goal.unit != nil }

    /// The message under a changed field that "Kaydet" would refuse; nil for a valid or unchanged one.
    func error(for field: GoalEditableField, in draft: GoalDefinitionDraft) -> String? {
        guard let change = changes(in: draft).first(where: { $0.field == field }) else { return nil }
        switch check(field.rawValue, text: change.text) {
        case .valid: return nil
        case .nameTaken: return String(localized: "Bu ad zaten kullanılıyor. Başka bir ad seç.")
        case .invalid:
            switch field {
            case .name: return String(localized: "Ad boş olmamalı ve tek satır olmalı.")
            case .target: return String(localized: "Hedef miktar sıfırdan büyük bir sayı olmalı.")
            case .unit: return String(localized: "Birim tek satır olmalı.")
            case .period, .kind:
                return String(
                    localized: "Hedef tanımını kontrol et: ad boş olmamalı, miktar sıfırdan büyük olmalı.")
            }
        }
    }

    /// "Kaydet" is possible: something changed and every changed field is valid.
    func canSave(_ draft: GoalDefinitionDraft) -> Bool {
        guard canWrite, let writes = writes(for: draft) else { return false }
        return !writes.isEmpty
    }

    /// Writes only the changed fields, in one write turn and one index update; the file name
    /// stays. Nothing is written when one of them is invalid. A failed write stops the rest and
    /// keeps the reason; the fields written before it are in the file and in the index.
    func apply(_ draft: GoalDefinitionDraft) async -> Bool {
        await load()
        guard canWrite, let writes = writes(for: draft), !writes.isEmpty else { return false }
        errorText = nil
        isWriting = true
        defer { isWriting = false }
        return await write(writes)
    }

    private struct FieldWrite {
        let field: String
        let literal: FrontmatterLiteral
        let clean: String
    }

    /// The writes for every changed field, or nil when one of them is invalid.
    private func writes(for draft: GoalDefinitionDraft) -> [FieldWrite]? {
        var writes: [FieldWrite] = []
        for change in changes(in: draft) {
            guard case .valid(let literal, let clean) = check(change.field.rawValue, text: change.text) else {
                return nil
            }
            writes.append(FieldWrite(field: change.field.rawValue, literal: literal, clean: clean))
        }
        return writes
    }

    /// One `performEdit`: one write turn, one check that the file is still this goal, one index
    /// update. A failure after the first field still publishes the fields already written.
    private func write(_ writes: [FieldWrite]) async -> Bool {
        let path = goal.id
        let key = goal.key
        var partialFailure: (any Error)?
        do {
            guard root == store.vaultURL else { throw VaultStoreError.staleTarget }
            try await store.performEdit(path: path) { writer in
                let document = try await writer.document(at: path)
                guard !document.isReadOnly, case .parsed(let fields) = document.frontmatter,
                    case .scalar(let type) = fields.field(named: "type")?.value, type.text == "goal",
                    case .scalar(let current) = fields.field(named: "key")?.value, current.text == key
                else { throw VaultStoreError.staleTarget }
                for (position, item) in writes.enumerated() {
                    do {
                        if item.field == "unit", item.clean.isEmpty {
                            try await writer.removingFrontmatterField(at: path, key: item.field)
                        } else {
                            try await writer.settingFrontmatterValue(at: path, key: item.field, value: item.literal)
                        }
                    } catch {
                        guard position > 0 else { throw error }
                        partialFailure = error
                        return
                    }
                }
            }
        } catch {
            errorText = DayEditError.message(for: error)
            if case VaultStoreError.indexUpdateFailed = error { return partialFailure == nil }
            return false
        }
        if let partialFailure {
            errorText = DayEditError.message(for: partialFailure)
            return false
        }
        return true
    }
}
