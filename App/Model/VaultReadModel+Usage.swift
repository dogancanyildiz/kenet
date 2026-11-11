import EntityRecognition
import VaultIndex

/// What a publish does with entity usage (`VaultReadModel.usageRecount(since:)`).
enum UsageRecount: Sendable {
    /// Link targets match the model the current rows were counted from: keep them.
    case unchanged
    case counted([EntityUsage])
    /// The model may not match the index: read usage from the index.
    case needsIndex
}

extension VaultReadModel {
    /// Usage for this model; `counted` is the model the current rows came from, if any.
    func usageRecount(since counted: VaultReadModel?) -> UsageRecount {
        if let counted, hasSameUsageInputs(as: counted) { return .unchanged }
        return entityUsage().map(UsageRecount.counted) ?? .needsIndex
    }

    /// Entity usage counted from the fragments (`EntityUsageCalculator`); `nil` when the model may
    /// not match the index (never built, or marked for a full reconcile): the caller asks the index.
    func entityUsage() -> [EntityUsage]? {
        guard isBuilt, !needsFullReconcile else { return nil }
        return EntityUsageCalculator.usage(of: fragments.values.lazy.map { ($0.file, $0.entity, $0.links) })
    }

    /// True when `other` gives the same entity usage: file by file the same kind, date, usage
    /// entity and link targets. A file only one side has counts only if it has links or an entity;
    /// a new day's first unlinked line changes nothing. Fragments an incremental publish did not
    /// touch share storage with `other`'s, so their links compare cheaply.
    func hasSameUsageInputs(as other: VaultReadModel) -> Bool {
        guard isBuilt, other.isBuilt, !needsFullReconcile, !other.needsFullReconcile else { return false }
        var matched = 0
        for (path, fragment) in fragments {
            guard let previous = other.fragments[path] else {
                if fragment.countsForUsage { return false }
                continue
            }
            matched += 1
            if previous.file.kind != fragment.file.kind || previous.file.date != fragment.file.date { return false }
            if previous.usageEntity != fragment.usageEntity { return false }
            if previous.links == fragment.links { continue }
            if !previous.links.lazy.map(\.resolvedFile).elementsEqual(fragment.links.lazy.map(\.resolvedFile)) {
                return false
            }
        }
        if matched < other.fragments.count {
            for (path, previous) in other.fragments where fragments[path] == nil && previous.countsForUsage {
                return false
            }
        }
        return true
    }
}

extension VaultFileFragment {
    /// The entity path usage counts for; goals have no usage row.
    fileprivate var usageEntity: String? { entity.flatMap { $0.kind == "goal" ? nil : $0.file } }
    /// A file with no links and no usage entity adds nothing to any usage row.
    fileprivate var countsForUsage: Bool { !links.isEmpty || usageEntity != nil }
}
