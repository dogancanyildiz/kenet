import Foundation
import Observation
import VaultStore

/// Execution model for the contact import flow.
@MainActor @Observable
final class ContactImportModel {
    /// Names, not counts alone: the user must be able to see which contacts were left out.
    struct ContactImportResult: Equatable, Sendable {
        let created: [String]
        let skipped: [String]
        let failed: [String]
    }

    typealias Creator = @MainActor (ContactImportPlan.Item) async throws -> Void

    private(set) var plan: ContactImportPlan?
    private(set) var result: ContactImportResult?
    private(set) var isImporting = false

    private let existingProvider: @MainActor () -> [ExistingEntityInfo]
    private let creator: Creator

    init(store: IndexStore) {
        self.existingProvider = { [weak store] in
            (store?.knownEntities ?? []).map {
                ExistingEntityInfo(name: $0.name, aliases: $0.aliases, fileStem: $0.fileStem)
            }
        }
        self.creator = { [weak store] item in
            guard let store else { throw VaultStoreError.staleTarget }
            // One exclusive write per person: the alias goes in with the file, so a failure can
            // never leave a person without the alias the summary promised.
            _ = try await store.createEntity(
                kind: .person, name: item.name, qualifier: nil, aliases: item.aliases.isEmpty ? nil : item.aliases)
        }
    }

    init(existing: [ExistingEntityInfo] = [], creator: @escaping Creator) {
        self.existingProvider = { existing }
        self.creator = creator
    }

    func prepare(candidates: [ContactName]) {
        guard !isImporting else { return }
        plan = ContactImportPlan.build(selected: candidates, existingEntities: existingProvider())
        result = nil
    }

    /// Writes the planned people one after another. A failure does not stop the rest; a name that
    /// appeared in the vault after the plan was made is reported as skipped, never overwritten.
    func importContacts() async {
        guard let plan, result == nil, !isImporting else { return }
        isImporting = true
        defer { isImporting = false }

        var created: [String] = []
        var skipped = plan.alreadyExists.map(\.name)
        var failed: [String] = []
        for item in plan.toCreate {
            do {
                try await creator(item)
                created.append(item.name)
            } catch VaultStoreError.nameTaken {
                skipped.append(item.name)
            } catch {
                failed.append(item.name)
            }
        }
        result = ContactImportResult(created: created, skipped: skipped, failed: failed)
    }

    func cancel() {
        guard !isImporting else { return }
        plan = nil
        result = nil
    }
}
