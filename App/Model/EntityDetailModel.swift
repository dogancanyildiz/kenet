import Foundation
import Observation
import Summaries
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
    /// Keys the free field list hides and its editors refuse. The cadence keys belong to the
    /// rhythm editor on a person only; on any other file they are ordinary fields.
    private(set) var reservedKeys = EntityDetailModel.reservedKeys
    let store: IndexStore
    private(set) var path: String
    private(set) var renameResult: RenameResult?
    private(set) var renamedName: String?
    private(set) var renamedQualifier: String?
    private(set) var fields: [EntityField] = []
    private(set) var personCadence = PersonCadence.none
    private(set) var aliases: [String] = []
    private(set) var aliasesEditable = false
    private(set) var aliasesSource = ""
    private(set) var unreadableFrontmatter = false
    /// The place's valid `coordinates`, the value the map shows.
    private(set) var coordinate: PlaceCoordinate?
    /// The file has a `coordinates` field, usable or not.
    private(set) var hasCoordinatesField = false
    /// The two numbers of a valid `coordinates` exactly as the file spells them.
    private(set) var coordinateSpellings: [String]?
    /// The `coordinates` lines as they stand in the file, for showing what a save replaces.
    private(set) var coordinatesSource = ""
    /// False for a value the writer refuses to touch (kept raw by the parser).
    private(set) var coordinatesWritable = true
    private(set) var body = ""
    private(set) var isLoaded = false
    private(set) var isWriting = false
    private(set) var errorText: String?
    private var root: URL?
    private var isReadOnly = false
    private var allKeys: [String] = []
    private var isPersonFile = false

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
                let coordinates = frontmatter.field(named: "coordinates")
                hasCoordinatesField = coordinates != nil
                coordinateSpellings = coordinate == nil ? nil : coordinates?.value.listItems?.map(\.raw)
                coordinatesSource =
                    coordinates.map { field in
                        document.lines[field.lineRange].map(\.displayText).joined(separator: "\n")
                    } ?? ""
                if case .raw = coordinates?.value { coordinatesWritable = false } else { coordinatesWritable = true }
                allKeys = frontmatter.fields.map(\.key)
                if case .scalar(let type) = frontmatter.field(named: "type")?.value {
                    isPersonFile = type.text == "person"
                } else {
                    isPersonFile = false
                }
                reservedKeys = Self.reservedKeys + (isPersonFile ? PersonCadence.keys : [])
                personCadence =
                    isPersonFile ? PersonCadence.parse(frontmatter.fields.compactMap(Self.cadenceField)) : .none
                fields = frontmatter.fields.filter { !reservedKeys.contains($0.key) }.map {
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
                coordinateSpellings = nil
                coordinatesSource = ""
                coordinatesWritable = true
                allKeys = []
                isPersonFile = false
                reservedKeys = Self.reservedKeys
                personCadence = .none
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
        } catch is CancellationError {
            // A newer load (`.task(id:)`) replaced this one; its answer is the one to show.
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
        guard !reservedKeys.contains(field) else { return false }
        return await write { try await self.store.setField(at: self.path, key: field, value: value) }
    }

    @discardableResult
    func setList(_ field: String, values: [FrontmatterLiteral]) async -> Bool {
        guard !reservedKeys.contains(field) else { return false }
        return await write { try await self.store.setList(at: self.path, key: field, values: values) }
    }

    @discardableResult
    func setEntry(_ field: String, entry: String, value: FrontmatterLiteral) async -> Bool {
        guard !reservedKeys.contains(field) else { return false }
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

    /// Writes the two number spellings as given, so digits the user did not touch stay.
    @discardableResult
    func saveCoordinate(latitude: String, longitude: String) async -> Bool {
        await setList("coordinates", values: [.number(latitude), .number(longitude)])
    }

    @discardableResult
    func addField(key: String, text: String) async -> Bool {
        let key = key.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !key.isEmpty, !reservedKeys.contains(key),
            !allKeys.contains(where: { $0.utf8.elementsEqual(key.utf8) })
        else {
            errorText = String(localized: "Bu alan adı boş, ayrılmış veya zaten kullanılıyor.")
            return false
        }
        return await set(key, to: .text(text))
    }

    @discardableResult
    func setCadenceDays(_ days: Int) async -> Bool {
        guard isPersonFile, days >= 1 else { return false }
        return await write {
            try await self.store.setField(at: self.path, key: PersonCadence.dayKey, value: .integer(days))
        }
    }

    @discardableResult
    func clearCadenceDays() async -> Bool {
        guard isPersonFile else { return false }
        return await write { try await self.store.removeField(at: self.path, key: PersonCadence.dayKey) }
    }

    @discardableResult
    func resumeCadence() async -> Bool {
        guard isPersonFile else { return false }
        return await write { try await self.store.removeField(at: self.path, key: PersonCadence.pauseKey) }
    }

    @discardableResult
    func remove(_ field: String) async -> Bool {
        guard !reservedKeys.contains(field) else { return false }
        return await write { try await self.store.removeField(at: self.path, key: field) }
    }

    private static func cadenceField(_ field: FrontmatterField) -> PersonCadenceField? {
        guard PersonCadence.keys.contains(field.key) else { return nil }
        guard case .scalar(let scalar) = field.value else {
            return PersonCadenceField(key: field.key, kind: "raw", value: "")
        }
        let kind: String
        switch scalar.kind {
        case .date: kind = "date"
        case .number: kind = "number"
        case .boolean: kind = "boolean"
        default: kind = "other"
        }
        return PersonCadenceField(key: field.key, kind: kind, value: scalar.raw)
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
