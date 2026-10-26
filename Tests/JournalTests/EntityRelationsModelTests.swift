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
        #expect(labelled.name == "Selin Korkmaz")
        #expect(labelled.relation.label == "eşi")
        #expect(labelled.canRemove)
        let plain = try #require(model.rows.first { $0.isOutgoing && $0.relation.label == nil })
        #expect(plain.name == "Selin Korkmaz")
        #expect(plain.relation.label == nil)
        let incoming = try #require(model.rows.first { !$0.isOutgoing && $0.relation.label == "yazar" })
        #expect(incoming.name == "Örnek Kitap")
        #expect(incoming.relation.label == "yazar")
        let incomingPlain = try #require(model.rows.first { !$0.isOutgoing && $0.relation.label == nil })
        #expect(incomingPlain.name == "Selin Korkmaz")
        #expect(incomingPlain.relation.label == nil)
        #expect(model.rows.filter { !$0.isOutgoing }.allSatisfy { !$0.canRemove })
        #expect(incoming.path == "books/Örnek Kitap.md")
    }

    @Test func removalActionsFollowDirectionSchemaAndWriteAccess() async throws {
        let context = try await Self.context()
        defer { context.clean() }
        for path in [Self.person, "books/Örnek Kitap.md"] {
            let model = EntityRelationsModel(store: context.store, path: path)
            await model.load()
            #expect(!model.rows.isEmpty)
            for row in model.rows {
                let expected: [EntityRelationsSection.RemoveAction] =
                    row.isOutgoing && !row.isSchemaField ? [.remove] : []
                #expect(EntityRelationsSection.removeActions(for: row, canWrite: true) == expected)
                #expect(EntityRelationsSection.removeActions(for: row, canWrite: false).isEmpty)
            }
        }
    }

    @Test func incomingPageCopyUsesExplicitLanguageBundles() throws {
        let examples = [
            ("Ada", "Ada'nın"), ("Ece", "Ece'nin"), ("Aksu", "Aksu'nun"), ("Öykü", "Öykü'nün"),
            ("Deniz", "Deniz'in"), ("Bulut", "Bulut'un"), ("Özgür", "Özgür'ün"), ("Arıkan", "Arıkan'ın"),
        ]
        for language in ["tr", "en"] {
            let path = try #require(Bundle.main.path(forResource: language, ofType: "lproj"))
            for (name, possessive) in examples {
                let resource = EntityRelationCopy.incomingPage(
                    name, locale: Locale(identifier: language), bundle: .atURL(URL(fileURLWithPath: path)))
                let expected = language == "tr" ? "\(possessive) sayfasında" : "On \(name)'s page"
                #expect(String(localized: resource) == expected)
            }
        }
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
        let model = EntityRelationsModel(store: context.store, path: Self.person)
        await model.load()
        #expect(model.errorText == nil)
        // Both labels survive even though the Graph query collapses the Deniz–Selin pair.
        #expect(model.labels == ["eşi", "yazar"])
        #expect(try await context.store.relationLabels() == ["eşi", "yazar"])
    }

    @Test func emptyVaultHasNoSuggestions() async throws {
        let context = try TaskTestContext()
        defer { context.clean() }
        await context.start()
        #expect(try await context.store.relationLabels().isEmpty)
    }

    @Test func loadingFailureUsesLoadingCopy() async throws {
        let context = try await Self.context()
        defer { context.clean() }
        context.store.testingQueryDidFinish = { throw CocoaError(.fileReadUnknown) }
        let model = EntityRelationsModel(store: context.store, path: Self.person)
        await model.load()
        #expect(model.errorText == String(localized: "Bağlar yüklenemedi. Kasayı kontrol edip yeniden dene."))
        #expect(model.rows.isEmpty)
        context.store.testingQueryDidFinish = nil
        await model.load()
        #expect(model.errorText == nil)
        #expect(model.labels == ["eşi", "yazar"])
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
        #expect(model.sheetErrorText == String(localized: "Bu etiket adında bir alan zaten var."))
        #expect(try Data(contentsOf: path) == bytes)
        // The save failure belongs to the sheet: the section shows nothing, and closing the sheet clears it.
        #expect(model.errorText == nil)
        model.clearSheetError()
        #expect(model.sheetErrorText == nil)
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

    @Test func writeGateFailuresReadAsWhatHappenedToTheFile() {
        let generic = String(localized: "Bağ kaydedilemedi. Kasayı kontrol edip yeniden dene.")
        let gate: [any Error] = [
            VaultStoreError.indexUpdateFailed(path: Self.person, underlying: CocoaError(.fileReadUnknown)),
            VaultStoreError.staleTarget, VaultStoreError.readOnlyVault,
        ]
        for error in gate {
            #expect(EntityRelationsModel.errorMessage(error) == DayEditError.message(for: error))
            #expect(EntityRelationsModel.errorMessage(error) != generic)
        }
        // The file was written: the copy must not say it was not saved.
        #expect(
            EntityRelationsModel.errorMessage(gate[0])
                == String(localized: "Değişiklik kaydedildi, indeks güncellenemedi."))
        #expect(
            EntityRelationsModel.errorMessage(RelationError.invalidLabel)
                == String(localized: "Etiket geçersiz karakter içeriyor."))
        #expect(
            EntityRelationsModel.errorMessage(RelationError.unsafeRemoval)
                == String(localized: "Bu bağ alanın metni içinde; Alanlar'da düzenle."))
        #expect(EntityRelationsModel.errorMessage(RelationError.invalidTarget) == generic)
    }

    @Test func invalidLabelHasSpecificCopyAndKeepsBytes() async throws {
        let context = try await Self.context()
        defer { context.clean() }
        let path = context.root.appendingPathComponent(Self.person)
        let bytes = try Data(contentsOf: path)
        let model = EntityRelationsModel(store: context.store, path: Self.person)
        let target = try #require(context.store.content.entities.first { $0.id == "places/Liman Ofis.md" })
        #expect(!(await model.save(target: target, label: "<<")))
        #expect(model.sheetErrorText == String(localized: "Etiket geçersiz karakter içeriyor."))
        #expect(model.errorText == nil)
        #expect(try Data(contentsOf: path) == bytes)
    }

    @Test func unsafeRemovalHasSpecificCopyAndKeepsBytes() async throws {
        let context = try await Self.context()
        defer { context.clean() }
        try await context.store.setField(
            at: Self.person, key: "ortak", value: .text("[[Selin Korkmaz]] ve [[Liman Ofis]]"))
        let path = context.root.appendingPathComponent(Self.person)
        let bytes = try Data(contentsOf: path)
        let model = EntityRelationsModel(store: context.store, path: Self.person)
        await model.load()
        let row = try #require(
            model.rows.first { $0.isOutgoing && $0.relation.label == "ortak" && $0.path == "places/Liman Ofis.md" })
        await model.remove(row)
        #expect(model.errorText == String(localized: "Bu bağ alanın metni içinde; Alanlar'da düzenle."))
        #expect(model.sheetErrorText == nil)
        #expect(try Data(contentsOf: path) == bytes)
    }

    @Test func anchoredMixedAndSelfLinkFieldsStayInTheFieldList() async throws {
        let context = try await Self.context()
        defer { context.clean() }
        try await context.store.setField(at: Self.person, key: "ilk", value: .text("[[Selin Korkmaz#Not]]"))
        try await context.store.setField(
            at: Self.person, key: "ortak", value: .text("[[Selin Korkmaz]] ve [[Liman Ofis]]"))
        try await context.store.setList(
            at: Self.person, key: "kendi", values: [.text("[[Selin Korkmaz]]"), .text("[[Deniz Arıkan]]")])
        // Each key is an outgoing relation, so only the spelling decides whether it hides.
        let relations = EntityRelationsModel(store: context.store, path: Self.person)
        await relations.load()
        for key in ["ilk", "ortak", "kendi"] {
            #expect(relations.rows.contains { $0.isOutgoing && $0.relation.label == key })
        }
        let detail = EntityDetailModel(store: context.store, path: Self.person)
        await detail.load()
        #expect(detail.isLoaded)
        #expect(detail.reservedKeys.contains("eşi"))
        for key in ["ilk", "ortak", "kendi"] {
            #expect(!detail.reservedKeys.contains(key))
            #expect(detail.fields.contains { $0.key == key })
        }
    }

    @Test func relationWritesGoThroughTheEditGate() async throws {
        let context = try await Self.context()
        defer { context.clean() }
        var turns = 0
        context.store.testingEditTurnDidArrive = { turns += 1 }
        let model = EntityRelationsModel(store: context.store, path: Self.person)
        let target = try #require(context.store.content.entities.first { $0.id == "places/Liman Ofis.md" })
        let before = context.store.lastUpdated
        #expect(await model.save(target: target, label: "iş"))
        #expect(turns == 1)
        #expect(context.store.lastUpdated != before)
        let row = try #require(model.rows.first { $0.isOutgoing && $0.relation.label == "iş" })
        await model.remove(row)
        #expect(turns == 2)
        #expect(!model.rows.contains { $0.id == row.id })
    }

    @Test func readOnlyVaultOffersNoWrite() async throws {
        let context = try TaskTestContext()
        defer { context.clean() }
        let fixture = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
            .deletingLastPathComponent().appendingPathComponent("Fixtures/vaults/graph")
        try FileManager.default.copyItem(at: fixture, to: context.root)
        // A format newer than this build: the vault opens read-only.
        let app = context.root.appendingPathComponent(".app")
        try FileManager.default.createDirectory(at: app, withIntermediateDirectories: true)
        try Data("{ \"formatVersion\": 2 }\n".utf8).write(to: app.appendingPathComponent("vault.json"))
        await context.start()
        #expect(context.store.isVaultReadOnly)
        let model = EntityRelationsModel(store: context.store, path: Self.person)
        await model.load()
        #expect(!model.rows.isEmpty)
        #expect(!model.canWrite)
        let path = context.root.appendingPathComponent(Self.person)
        let bytes = try Data(contentsOf: path)
        let target = try #require(context.store.content.entities.first { $0.id == "places/Liman Ofis.md" })
        #expect(!(await model.save(target: target, label: "iş")))
        #expect(try Data(contentsOf: path) == bytes)
    }

    @Test func suggestionsLeaveOutTheSourcesSchemaKeys() async throws {
        let context = try await Self.context()
        defer { context.clean() }
        // "yazar" is the book type's own field: Core refuses it as a label on a book.
        let book = EntityRelationsModel(store: context.store, path: "books/Örnek Kitap.md")
        await book.load()
        #expect(book.labels == ["eşi"])
    }
}
