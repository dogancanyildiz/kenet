import Foundation
import GoalTracking
import VaultFormat

extension VaultStore {
    /// Creates a definition without a template, reserving its key inside the vault write queue.
    @discardableResult
    public func creatingGoal(
        name: String, period: GoalPeriod, kind: GoalKind, target: Double, unit: String? = nil
    ) async throws -> String {
        guard kind != .milestone || period == .year else { throw EditError.invalidValue }
        guard target.isFinite, target > 0 else { throw EditError.invalidValue }
        return try await perform {
            let name = try self.displayName(name)
            let stem = try self.filenameComponent(name)
            guard (stem + ".md").utf8.count <= 255 else { throw VaultStoreError.invalidName }
            guard try !self.filenameIsTaken(stem), try self.index.entities(named: name).isEmpty else {
                throw VaultStoreError.nameTaken
            }
            var keys = Set(try self.index.snapshot().entities.compactMap(\.goalKey))
            keys.formUnion(try self.index.goalLogs().map(\.key))
            // External edits can precede the watcher. Reserve current disk keys and display names too.
            for path in try self.markdownPaths() {
                let document = RawDocument(bytes: try Data(contentsOf: self.checkedURL(path)))
                guard case .parsed(let fields) = document.frontmatter else { continue }
                if case .mapping(let entries) = fields.field(named: "goals")?.value {
                    keys.formUnion(entries.map(\.key))
                }
                guard case .scalar(let type) = fields.field(named: "type")?.value, type.text == "goal" else { continue }
                if case .scalar(let key) = fields.field(named: "key")?.value { keys.insert(key.text) }
                if case .scalar(let other) = fields.field(named: "name")?.value,
                    storeComparisonKey(other.text) == storeComparisonKey(name)
                {
                    throw VaultStoreError.nameTaken
                }
            }
            let key = Self.goalKey(for: name, reserving: keys)
            var document = try RawDocument(bytes: []).settingFrontmatterValue(.text("goal"), forKey: "type")
            for (field, value) in [("name", name), ("key", key), ("period", period.rawValue), ("kind", kind.rawValue)] {
                document = try document.settingFrontmatterValue(.text(value), forKey: field)
            }
            if kind != .milestone {
                document = try document.settingFrontmatterValue(.number(goalNumberSpelling(target)), forKey: "target")
            }
            if let unit, !unit.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                document = try document.settingFrontmatterValue(.text(self.displayName(unit)), forKey: "unit")
            }
            let path = "goals/" + stem + ".md"
            try self.persist(document, path: path, exclusive: true)
            return path
        }
    }

    /// The UI preview uses the same spelling as creation; creation rechecks disk reservations.
    public nonisolated static func goalKey(for name: String, reserving keys: Set<String> = []) -> String {
        let folded = name.lowercased().replacingOccurrences(of: "ı", with: "i")
            .folding(options: .diacriticInsensitive, locale: Locale(identifier: "en_US_POSIX"))
        let pieces = folded.components(
            separatedBy: CharacterSet(charactersIn: "abcdefghijklmnopqrstuvwxyz0123456789").inverted)
        let slug = pieces.filter { !$0.isEmpty }.joined(separator: "-")
        let base = slug.isEmpty ? "goal" : slug
        let taken = Set(keys.map(storeComparisonKey))
        var candidate = base
        var suffix = 2
        while taken.contains(candidate) {
            candidate = base + "-" + String(suffix)
            suffix += 1
        }
        return candidate
    }
}
