import EntityRecognition
import Foundation
import Observation
import VaultFormat
import VaultStore

@MainActor @Observable
final class UnresolvedEntityModel {
    let store: IndexStore
    var name: String
    var qualifier = ""
    private(set) var needsQualifier = false
    private(set) var kind: VaultEntityKind?
    private(set) var created: KnownEntity?
    private(set) var errorText: String?
    private(set) var isCreating = false

    init(store: IndexStore, target: String) {
        self.store = store
        let component = target.split(separator: "/").last.map(String.init) ?? target
        name = component.hasSuffix(".md") ? String(component.dropLast(3)) : component
    }

    func create(_ kind: VaultEntityKind) async {
        guard !isCreating, store.canAddEvent, created == nil else { return }
        self.kind = kind
        // The store's collision rule: `IŞIK` and `Işık`, `SELIN` and `Selin` are one name.
        let collision = NameCollision(name)
        if !needsQualifier && store.knownEntities.contains(where: { collision.matches($0.name) }) {
            needsQualifier = true
            return
        }
        isCreating = true
        errorText = nil
        defer { isCreating = false }
        do {
            created = try await store.createEntity(kind: kind, name: name, qualifier: needsQualifier ? qualifier : nil)
        } catch VaultStoreError.nameTaken { needsQualifier = true } catch {
            errorText = DayEditError.message(for: error)
        }
    }
}
