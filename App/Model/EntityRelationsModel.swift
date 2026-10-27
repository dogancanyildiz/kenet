import Foundation
import Observation
import VaultFormat
import VaultIndex
import VaultStore

struct EntityRelationRow: Identifiable {
    let relation: Relation
    let isOutgoing: Bool
    /// The label is a field of the source's custom-type schema; its editor lives in Fields.
    var isSchemaField = false
    var id: [String] { [relation.source, relation.target, relation.label ?? "", isOutgoing ? "out" : "in"] }
    var path: String { isOutgoing ? relation.target : relation.source }
    var canRemove: Bool { isOutgoing && !isSchemaField }
    var name: String { isOutgoing ? relation.targetName : relation.sourceName }
}

@MainActor @Observable
final class EntityRelationsModel {
    let store: IndexStore
    let path: String
    private(set) var rows: [EntityRelationRow] = []
    private(set) var labels: [String] = []
    /// Loading and removal failures: an information band in the section.
    private(set) var errorText: String?
    /// A failed save: shown only in the sheet and cleared when the sheet opens or closes.
    private(set) var sheetErrorText: String?
    private(set) var isWriting = false
    private let root: URL?

    init(store: IndexStore, path: String) {
        self.store = store
        self.path = path
        root = store.vaultURL
    }

    var canWrite: Bool { root == store.vaultURL && store.canAddEvent && !isWriting }

    static func errorMessage(_ error: any Error) -> String {
        switch error {
        case RelationError.keyInUse: String(localized: "Bu etiket adında bir alan zaten var.")
        case RelationError.reservedLabel: String(localized: "Bu ad ayrılmıştır.")
        case RelationError.invalidLabel: String(localized: "Etiket geçersiz karakter içeriyor.")
        case RelationError.unsafeRemoval: String(localized: "Bu bağ alanın metni içinde; Alanlar'da düzenle.")
        case is RelationError: String(localized: "Bağ kaydedilemedi. Kasayı kontrol edip yeniden dene.")
        // Write-gate failures (written but not indexed, stale, read-only) say what happened to the file.
        default: DayEditError.message(for: error)
        }
    }

    func clearSheetError() { sheetErrorText = nil }

    func load() async {
        do {
            let relations = try await store.computeRelations(of: path)
            let labels = try await store.relationLabels()
            guard root == store.vaultURL, !Task.isCancelled else { return }
            let kind = store.content.entities.first { $0.id == path }?.kind
            let schemaKeys = Set(store.entityTypes.allTypes.first { $0.id == kind }?.fields.map(\.key) ?? [])
            rows =
                relations.outgoing.map {
                    EntityRelationRow(
                        relation: $0, isOutgoing: true, isSchemaField: $0.label.map(schemaKeys.contains) ?? false)
                }
                + relations.incoming.map { EntityRelationRow(relation: $0, isOutgoing: false) }
            // The source's own schema keys are refused as labels, so they are not offered.
            self.labels = labels.filter { !schemaKeys.contains($0) }
            errorText = nil
        } catch {
            guard root == store.vaultURL, !Task.isCancelled else { return }
            errorText = String(localized: "Bağlar yüklenemedi. Kasayı kontrol edip yeniden dene.")
        }
    }

    func save(target: EntitySummary, label: String) async -> Bool {
        guard canWrite else { return false }
        isWriting = true
        sheetErrorText = nil
        defer { isWriting = false }
        do {
            try await store.addRelation(from: path, to: "/" + String(target.id.dropLast(3)), label: label)
            await load()
            return root == store.vaultURL
        } catch {
            sheetErrorText = Self.errorMessage(error)
            return false
        }
    }

    func remove(_ row: EntityRelationRow) async {
        guard row.canRemove, canWrite else { return }
        isWriting = true
        errorText = nil
        defer { isWriting = false }
        do {
            try await store.removeRelation(row.relation)
            await load()
        } catch { errorText = Self.errorMessage(error) }
    }

    /// Hide only pure link values that Core resolved to this field's relations. Mixed text, aliased or
    /// anchored links, unresolved links, links to the page itself, links Core resolved to another file
    /// of the same name (a note, a goal) and schema fields stay editable. `links` are the source
    /// file's indexed links: the index resolves each link once, as the relation query reads it.
    static func hiddenKeys(
        fields: [EntityField], schemaKeys: Set<String>, outgoing: [Relation], links: [IndexedLink]
    ) -> [String] {
        fields.compactMap { field in
            let key = field.key.utf8
            let targets = Set(outgoing.filter { ($0.label ?? "related").utf8.elementsEqual(key) }.map(\.target))
            guard !schemaKeys.contains(field.key), !targets.isEmpty,
                let items = field.value.listItems, !items.isEmpty,
                items.allSatisfy({ item in
                    guard item.kind == .text else { return false }
                    let text = item.text.trimmingCharacters(in: .whitespacesAndNewlines)
                    let links = RawDocument(bytes: text.utf8).links
                    // Display text and anchors are the user's own spelling; the field keeps them editable.
                    return links.count == 1 && links[0].byteRange == 0..<text.utf8.count
                        && links[0].displayText == nil && links[0].anchor == nil
                })
            else { return nil }
            // One indexed link per item; each must resolve to a target of this field's relations. A link
            // to the page itself is no relation (Core leaves it out), so it is no target and the field shows it.
            let indexed = links.filter {
                $0.block == nil && $0.entry == nil && $0.key.map { $0.utf8.elementsEqual(key) } == true
            }
            guard indexed.count == items.count,
                indexed.allSatisfy({ $0.resolvedFile.map(targets.contains) == true })
            else { return nil }
            return field.key
        }
    }
}
