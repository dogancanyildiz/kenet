import Foundation
import Observation
import VaultFormat
import VaultStore

struct EntityField: Identifiable, Hashable {
    let key: String
    let value: FrontmatterValue
    var id: [UInt8] { Array(key.utf8) }
}

@MainActor @Observable
final class EntityDetailModel {
    static let reservedKeys = ["type", "name", "qualifier", "aliases"]
    let store: IndexStore
    private(set) var path: String
    private(set) var renameResult: RenameResult?
    private(set) var renamedName: String?
    private(set) var renamedQualifier: String?
    private(set) var fields: [EntityField] = []
    private(set) var aliases: [String] = []
    private(set) var aliasesEditable = false
    private(set) var aliasesSource = ""
    private(set) var unreadableFrontmatter = false
    /// The place's valid `coordinates`, the value the map shows.
    private(set) var coordinate: PlaceCoordinate?
    /// The file has a `coordinates` field, usable or not.
    private(set) var hasCoordinatesField = false
    private(set) var body = ""
    private(set) var isLoaded = false
    private(set) var isWriting = false
    private(set) var errorText: String?
    private var root: URL?
    private var isReadOnly = false
    private var allKeys: [String] = []

    init(store: IndexStore, path: String) {
        self.store = store
        self.path = path
    }
    var canEdit: Bool {
        isLoaded && !isReadOnly && !unreadableFrontmatter && !isWriting && root == store.vaultURL && store.canAddEvent
    }

    func load() async {
        let selectedRoot = store.vaultURL
        let selectedPath = path
        do {
            let document = try await store.document(at: selectedPath)
            guard store.vaultURL == selectedRoot, path == selectedPath else { throw VaultStoreError.staleTarget }
            errorText = nil
            isReadOnly = document.isReadOnly
            unreadableFrontmatter = document.frontmatter == .unreadable
            coordinate = PlaceCoordinate(document: document)
            if case .parsed(let frontmatter) = document.frontmatter {
                hasCoordinatesField = frontmatter.field(named: "coordinates") != nil
                allKeys = frontmatter.fields.map(\.key)
                fields = frontmatter.fields.filter { !Self.reservedKeys.contains($0.key) }.map {
                    EntityField(key: $0.key, value: $0.value)
                }
                let items = frontmatter.field(named: "aliases")?.value.listItems
                aliasesEditable =
                    frontmatter.field(named: "aliases") == nil || items?.allSatisfy { $0.kind == .text } == true
                aliases = items?.filter { $0.kind == .text }.map(\.text) ?? []
                aliasesSource =
                    frontmatter.field(named: "aliases").map { field in
                        document.lines[field.lineRange].map(\.displayText).joined(separator: "\n")
                    } ?? ""
            } else {
                hasCoordinatesField = false
                allKeys = []
                fields = []
                aliases = []
                aliasesSource = ""
                aliasesEditable = !unreadableFrontmatter
            }
            body = document.lines.dropFirst(document.frontmatterLineRange?.upperBound ?? 0).map {
                String(decoding: $0.bytes, as: UTF8.self)
            }.joined()
            root = selectedRoot
            isLoaded = true
        } catch { errorText = DayEditError.message(for: error) }
    }

    func rename(to name: String, qualifier: String?) async throws -> RenameResult {
        guard canEdit else { throw VaultStoreError.staleTarget }
        isWriting = true
        defer { isWriting = false }
        let selectedRoot = store.vaultURL
        let result = try await store.renameEntity(at: path, to: name, qualifier: qualifier)
        path = result.path
        renameResult = result
        renamedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        renamedQualifier = qualifier
        if store.vaultURL == selectedRoot { await load() }
        return result
    }

    @discardableResult
    func set(_ field: String, to value: FrontmatterLiteral) async -> Bool {
        guard !Self.reservedKeys.contains(field) else { return false }
        return await write { try await self.store.setField(at: self.path, key: field, value: value) }
    }

    @discardableResult
    func setList(_ field: String, values: [FrontmatterLiteral]) async -> Bool {
        guard !Self.reservedKeys.contains(field) else { return false }
        return await write { try await self.store.setList(at: self.path, key: field, values: values) }
    }

    @discardableResult
    func setEntry(_ field: String, entry: String, value: FrontmatterLiteral) async -> Bool {
        guard !Self.reservedKeys.contains(field) else { return false }
        return await write { try await self.store.setEntry(at: self.path, key: field, entry: entry, value: value) }
    }

    @discardableResult
    func saveAliases(_ values: [String]) async -> Bool {
        guard aliasesEditable else { return false }
        return await write {
            try await self.store.setList(
                at: self.path, key: "aliases",
                values: values.filter { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }.map { .text($0) })
        }
    }

    /// Writes the pair as the `coordinates` list of vault-format.md; a text value typed
    /// there earlier is replaced.
    @discardableResult
    func saveCoordinate(_ value: PlaceCoordinate) async -> Bool {
        await setList("coordinates", values: PlaceCoordinateInput.literals(value))
    }

    @discardableResult
    func addField(key: String, text: String) async -> Bool {
        let key = key.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !key.isEmpty, !Self.reservedKeys.contains(key),
            !allKeys.contains(where: { $0.utf8.elementsEqual(key.utf8) })
        else {
            errorText = String(localized: "Bu alan adı boş, ayrılmış veya zaten kullanılıyor.")
            return false
        }
        return await set(key, to: .text(text))
    }

    @discardableResult
    func remove(_ field: String) async -> Bool {
        guard !Self.reservedKeys.contains(field) else { return false }
        return await write { try await self.store.removeField(at: self.path, key: field) }
    }

    private func write(_ operation: () async throws -> Void) async -> Bool {
        guard canEdit else { return false }
        isWriting = true
        errorText = nil
        defer { isWriting = false }
        do {
            try await operation()
            await load()
            return true
        } catch VaultStoreError.indexUpdateFailed {
            await load()
            errorText = String(localized: "Değişiklik kaydedildi, indeks güncellenemedi.")
            return true
        } catch {
            errorText = DayEditError.message(for: error)
            return false
        }
    }
}
