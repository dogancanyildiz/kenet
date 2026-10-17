import SwiftUI
import VaultFormat
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

/// The list row that opens ``EntityCreateSheet``. The Kişiler tab creates people, the Konumlar
/// tab places, and a custom type's tab an entity of that type while the vault defines it.
enum EntityCreateEntry {
    static func kind(forList kind: String, types: EntityTypeCatalog) -> VaultEntityKind? {
        switch kind {
        case "person": .person
        case "place": .place
        default: types.types.contains { $0.id == kind } ? .custom(kind) : nil
        }
    }

    /// "Yeni kişi", "Yeni konum", or "Yeni <tip adı>" with the type's singular name.
    static func title(
        _ kind: VaultEntityKind, types: EntityTypeCatalog,
        language: String = Bundle.main.preferredLocalizations.first ?? "en"
    ) -> String {
        // The phrase and the type's name come from one language: the requested one when the app
        // is localized in it, otherwise the language the app shows.
        let language = localization(language) != nil ? language : (Bundle.main.preferredLocalizations.first ?? "en")
        let bundle = localization(language) ?? .main
        switch kind {
        case .person: return String(localized: "Yeni kişi", bundle: bundle)
        case .place: return String(localized: "Yeni konum", bundle: bundle)
        case .custom(let id):
            let name = types.types.first { $0.id == id }?.name.localized(language: language) ?? id
            return String(localized: "Yeni \(inPhrase(name, language: language))", bundle: bundle)
        }
    }

    private static func localization(_ language: String) -> Bundle? {
        Bundle.main.path(forResource: language, ofType: "lproj").flatMap(Bundle.init(path:))
    }

    /// The name as the second word of a phrase: the first letter lowercased in the name's
    /// language ("Kitap" → "kitap", "İlaç" → "ilaç"), an acronym ("BMW") left as written.
    static func inPhrase(_ name: String, language: String) -> String {
        guard let first = name.first else { return name }
        if let second = name.dropFirst().first, second.isUppercase { return name }
        return String(first).lowercased(with: Locale(identifier: language)) + name.dropFirst()
    }

    static func systemImage(_ kind: VaultEntityKind, types: EntityTypeCatalog) -> String {
        switch kind {
        case .person: "person.badge.plus"
        case .place: "mappin.and.ellipse"
        case .custom(let id): types.types.first { $0.id == id }?.icon ?? "plus"
        }
    }

    static func identifier(_ kind: VaultEntityKind) -> String {
        switch kind {
        case .person: "button.entities.createPerson"
        case .place: "button.entities.createPlace"
        case .custom(let id): "button.entities.create." + id
        }
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

    var title: String { EntityCreateEntry.title(kind, types: store.entityTypes) }
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
