import SwiftUI
import VaultStore

struct EntityCreateSheet: View {
    @State private var model: EntityCreationModel
    let onCreated: (EntitySummary) -> Void
    @Environment(\.dismiss) private var dismiss

    init(store: IndexStore, kind: VaultEntityKind, onCreated: @escaping (EntitySummary) -> Void) {
        _model = State(initialValue: EntityCreationModel(store: store, kind: kind))
        self.onCreated = onCreated
    }

    var body: some View {
        @Bindable var model = model
        List {
            InkPageTitleRow(verbatim: model.title)
            TextField("Ad", text: $model.name)
                .font(.ink.content)
                .accessibilityIdentifier("field.entity.create.name")
                .inkListRow()
            if model.needsQualifier {
                TextField("Ayırt edici", text: $model.qualifier)
                    .font(.ink.content)
                    .accessibilityIdentifier("field.entity.create.qualifier")
                    .inkListRow()
            }
            if let error = model.errorText {
                InfoBand(kind: .error, verbatim: error).inkListRow()
            }
        }
        .listStyle(.plain)
        .inkPageScrollColumn()
        .disabled(model.isWriting || model.created != nil)
        .inkSheet(
            verbatim: model.title, confirm: .create, isConfirmEnabled: model.canSave,
            isBusy: model.isWriting, isCancelEnabled: !model.isWriting,
            cancelIdentifier: "button.entity.create.cancel", confirmIdentifier: "button.entity.create.confirm",
            onConfirm: {
                Task {
                    if let entity = await model.save() {
                        onCreated(entity)
                        dismiss()
                    }
                }
            }
        )
        .interactiveDismissDisabled(model.isWriting)
        .frame(minWidth: 320, minHeight: 300)
    }
}

/// The list row that opens ``EntityCreateSheet``. The Kişiler tab creates people and the
/// Konumlar tab places; a custom type has no row (`createEntity` writes the built-in kinds).
enum EntityCreateEntry {
    static func kind(forList kind: String) -> VaultEntityKind? {
        switch kind {
        case "person": .person
        case "place": .place
        default: nil
        }
    }

    static func title(_ kind: VaultEntityKind) -> LocalizedStringKey {
        kind == .person ? "Yeni kişi" : "Yeni konum"
    }

    static func systemImage(_ kind: VaultEntityKind) -> String {
        kind == .person ? "person.badge.plus" : "mappin.and.ellipse"
    }

    static func identifier(_ kind: VaultEntityKind) -> String {
        kind == .person ? "button.entities.createPerson" : "button.entities.createPlace"
    }
}

extension View {
    /// Presents ``EntityCreateSheet`` while `kind` is set. `onCreated` runs once the sheet is
    /// down, so the list can open (phone) or select (Mac column) the new entity.
    func entityCreateSheet(
        store: IndexStore, kind: Binding<VaultEntityKind?>, onCreated: @escaping (EntitySummary) -> Void
    ) -> some View {
        modifier(EntityCreateSheetPresenter(store: store, kind: kind, onCreated: onCreated))
    }
}

private struct EntityCreateSheetPresenter: ViewModifier {
    let store: IndexStore
    @Binding var kind: VaultEntityKind?
    let onCreated: (EntitySummary) -> Void
    @State private var created: EntitySummary?

    func body(content: Content) -> some View {
        content.sheet(
            isPresented: Binding(get: { kind != nil }, set: { if !$0 { kind = nil } }),
            onDismiss: {
                guard let entity = created else { return }
                created = nil
                onCreated(entity)
            },
            content: {
                if let creating = kind {
                    NavigationStack {
                        EntityCreateSheet(store: store, kind: creating) { created = $0 }
                    }
                }
            }
        )
    }
}

@MainActor @Observable
final class EntityCreationModel {
    let store: IndexStore
    let kind: VaultEntityKind
    private let root: URL?
    var name = ""
    var qualifier = ""
    private(set) var isWriting = false
    private(set) var created: EntitySummary?
    private(set) var errorText: String?
    /// The name the vault refused (a file of that name exists, an entity or not). Only that
    /// name asks for a qualifier; another name does not.
    private var collidingName: String?

    init(store: IndexStore, kind: VaultEntityKind) {
        self.store = store
        self.kind = kind
        root = store.vaultURL
    }

    var title: String { kind == .person ? String(localized: "Yeni kişi") : String(localized: "Yeni konum") }
    private var cleanName: String { name.trimmingCharacters(in: .whitespacesAndNewlines) }
    private var cleanQualifier: String { qualifier.trimmingCharacters(in: .whitespacesAndNewlines) }
    var needsQualifier: Bool {
        let matches = { (other: String) in other.compare(self.cleanName, options: [.caseInsensitive]) == .orderedSame }
        return collidingName.map(matches) == true || store.knownEntities.contains { matches($0.name) }
    }
    var canSave: Bool {
        root != nil && root == store.vaultURL && store.canAddEvent && !isWriting && created == nil
            && !cleanName.isEmpty && (!needsQualifier || !cleanQualifier.isEmpty)
    }

    func save() async -> EntitySummary? {
        guard canSave else { return nil }
        isWriting = true
        errorText = nil
        defer { isWriting = false }
        do {
            let entity = try await store.createEntity(
                kind: kind, name: cleanName, qualifier: cleanQualifier.isEmpty ? nil : cleanQualifier)
            guard root == store.vaultURL else { return nil }
            let summary =
                store.content.entities.first { $0.id == entity.file }
                ?? EntitySummary(
                    id: entity.file, kind: kind.rawValue, name: entity.name, qualifier: entity.qualifier,
                    aliases: entity.aliases, incomingLinks: 0)
            created = summary
            return summary
        } catch VaultStoreError.nameTaken {
            collidingName = cleanName
            errorText = String(localized: "Bu ad zaten kullanılıyor. Ayırt edici ekle.")
        } catch {
            errorText = DayEditError.message(for: error)
        }
        return nil
    }
}
