import Foundation
import Testing
import VaultFormat
import VaultIndex
import VaultStore

@testable import Journal

@MainActor struct EntityRelationsModelTests {
    static let person = "people/Deniz Arıkan.md"
    static func context() async throws -> TaskTestContext {
        let context = try TaskTestContext()
        let fixture = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
            .deletingLastPathComponent().appendingPathComponent("Fixtures/vaults/graph")
        try FileManager.default.copyItem(at: fixture, to: context.root)
        await context.start()
        return context
    }

    @Test func outgoingIncomingAndUnlabelledCopy() async throws {
        let context = try await Self.context()
        defer { context.clean() }
        let model = EntityRelationsModel(store: context.store, path: Self.person)
        await model.load()
        #expect(model.rows.count == 4)
        let labelled = try #require(model.rows.first { $0.isOutgoing && $0.relation.label == "eşi" })
        #expect(labelled.text == "eşi · Selin Korkmaz")
        #expect(labelled.canRemove)
        let plain = try #require(model.rows.first { $0.isOutgoing && $0.relation.label == nil })
        #expect(plain.text == "Selin Korkmaz")
        let incoming = try #require(model.rows.first { !$0.isOutgoing && $0.relation.label == "yazar" })
        let name = incoming.relation.sourceName
        #expect(incoming.text == String(localized: "\(name)'ın sayfasında") + " · yazar")
        let incomingPlain = try #require(model.rows.first { !$0.isOutgoing && $0.relation.label == nil })
        let plainName = incomingPlain.relation.sourceName
        #expect(incomingPlain.text == String(localized: "\(plainName)'ın sayfasında"))
        #expect(model.rows.filter { !$0.isOutgoing }.allSatisfy { !$0.canRemove })
        let mert = "Mert Aksu"
        #expect(EntityRelationRow.incomingPage(mert) == String(localized: "\(mert)'nun sayfasında"))
        #expect(incoming.path == "books/Örnek Kitap.md")
    }

    @Test func schemaLinkRowOffersNoRemovalAndKeepsTheFile() async throws {
        let context = try await Self.context()
        defer { context.clean() }
        let book = "books/Örnek Kitap.md"
        let model = EntityRelationsModel(store: context.store, path: book)
        await model.load()
        let schema = try #require(model.rows.first { $0.isOutgoing && $0.relation.label == "yazar" })
        #expect(!schema.canRemove)
        let url = context.root.appendingPathComponent(book)
        let before = try Data(contentsOf: url)
        await model.remove(schema)
        #expect(model.errorText == nil)
        #expect(try Data(contentsOf: url) == before)
        #expect(model.rows.contains { $0.id == schema.id })
        let person = EntityRelationsModel(store: context.store, path: Self.person)
        await person.load()
        #expect(person.rows.filter { $0.isOutgoing }.allSatisfy { $0.canRemove })
    }

    @Test func relationKeysLeaveTheFieldListsButSchemaLinksStay() async throws {
        let context = try await Self.context()
        defer { context.clean() }
        let detail = EntityDetailModel(store: context.store, path: Self.person)
        await detail.load()
        #expect(detail.isLoaded)
        #expect(!detail.reservedKeys.contains("related"))  // The unresolved [[Yok]] must remain visible.
        #expect(detail.reservedKeys.contains("eşi"))
        let rows = EntityReadPresentation.fieldRows(fields: detail.fields, schemaKeys: [])
        #expect(!rows.other.contains { $0.key == "eşi" })
        #expect(rows.other.contains { $0.key == "related" })
        let selin = EntityDetailModel(store: context.store, path: "people/Selin Korkmaz.md")
        await selin.load()
        #expect(selin.reservedKeys.contains("related"))
        let book = EntityDetailModel(store: context.store, path: "books/Örnek Kitap.md")
        await book.load()
        #expect(!book.reservedKeys.contains("yazar"))
        let bookRows = EntityReadPresentation.fieldRows(fields: book.fields, schemaKeys: ["yazar"])
        #expect(bookRows.known.contains { $0.key == "yazar" })
    }

    @Test func suggestionsAreUniqueSortedAndEmptySafe() async throws {
        let context = try await Self.context()
        defer { context.clean() }
        let relations = try await context.store.computeRelations(of: Self.person)
        let all = relations.incoming + relations.outgoing
        #expect(EntityRelationsModel.suggestions(all + all) == ["eşi", "yazar"])
        #expect(EntityRelationsModel.suggestions([]).isEmpty)
    }

    @Test func emptyVaultHasNoSuggestions() async throws {
        let context = try TaskTestContext()
        defer { context.clean() }
        await context.start()
        #expect(EntityRelationsModel.suggestions(try await context.store.computeExplicitRelations()).isEmpty)
    }

    @Test func keyInUseHasSpecificCopyAndKeepsBytes() async throws {
        let context = try await Self.context()
        defer { context.clean() }
        try await context.store.setField(at: Self.person, key: "tanışma", value: .text("Üniversite"))
        let path = context.root.appendingPathComponent(Self.person)
        let bytes = try Data(contentsOf: path)
        let model = EntityRelationsModel(store: context.store, path: Self.person)
        let target = try #require(context.store.content.entities.first { $0.id == "people/Selin Korkmaz.md" })
        #expect(!(await model.save(target: target, label: "tanışma")))
        #expect(model.errorText == String(localized: "Bu etiket adında bir alan zaten var."))
        #expect(try Data(contentsOf: path) == bytes)
        #expect(
            EntityRelationsModel.errorMessage(RelationError.reservedLabel) == String(localized: "Bu ad ayrılmıştır."))
    }

    @Test func savingWritesOnlySourceAndReloadsRows() async throws {
        let context = try await Self.context()
        defer { context.clean() }
        let model = EntityRelationsModel(store: context.store, path: Self.person)
        let target = try #require(context.store.content.entities.first { $0.id == "places/Liman Ofis.md" })
        let targetURL = context.root.appendingPathComponent(target.id)
        let before = try Data(contentsOf: targetURL)
        #expect(await model.save(target: target, label: "iş arkadaşı"))
        #expect(model.rows.contains { $0.isOutgoing && $0.path == target.id && $0.relation.label == "iş arkadaşı" })
        #expect(try Data(contentsOf: targetURL) == before)
        #expect(model.labels == model.labels.sorted())
        #expect(Set(model.labels).count == model.labels.count)
    }

    @Test func incomingRemovalDoesNotWriteAndOutgoingRemovalRefreshes() async throws {
        let context = try await Self.context()
        defer { context.clean() }
        let model = EntityRelationsModel(store: context.store, path: Self.person)
        await model.load()
        // Every incoming row, including the plain `related` one Core could remove from its source.
        let incoming = model.rows.filter { !$0.isOutgoing }
        #expect(incoming.contains { $0.relation.label == nil })
        for row in incoming {
            let source = context.root.appendingPathComponent(row.relation.source)
            let before = try Data(contentsOf: source)
            await model.remove(row)
            #expect(try Data(contentsOf: source) == before)
            #expect(model.rows.contains { $0.id == row.id })
        }
        let outgoing = try #require(model.rows.first { $0.isOutgoing && $0.relation.label == nil })
        await model.remove(outgoing)
        #expect(model.errorText == nil)
        #expect(!model.rows.contains { $0.id == outgoing.id })
    }
}
