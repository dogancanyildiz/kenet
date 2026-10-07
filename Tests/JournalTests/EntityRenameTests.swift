import EntityRecognition
import Foundation
import Testing
import VaultFormat

@testable import Journal

@MainActor
struct EntityRenameTests {
    @Test func collisionRequestsQualifierAndPageMovesToSavedPath() async throws {
        let context = try EntityPageTestContext()
        defer { context.clean() }
        await context.start()
        let detail = EntityDetailModel(store: context.store, path: context.path)
        await detail.load()
        let model = EntityRenameModel(detail: detail, name: "Mert Aksu", qualifier: nil)
        let before = try Data(contentsOf: context.file)
        await model.save()
        #expect(model.needsQualifier)
        #expect(model.result == nil)
        #expect(detail.path == context.path)
        #expect(try Data(contentsOf: context.file) == before)
        for _ in 0..<150 where !detail.canEdit { try await Task.sleep(for: .milliseconds(20)) }
        model.qualifier = "ofis"
        await model.save()
        let result = try #require(model.result)
        #expect(result.path == "people/Mert Aksu (ofis).md")
        #expect(detail.path == result.path)
        #expect(detail.renameResult == result)
        for _ in 0..<150 where !detail.canEdit { try await Task.sleep(for: .milliseconds(20)) }
        #expect(detail.isLoaded && detail.canEdit)
        #expect(result.updatedFiles.count == 7)
        #expect(result.failures.isEmpty)
        #expect(!FileManager.default.fileExists(atPath: context.file.path))
        #expect(context.store.content.entities.contains { $0.id == result.path && $0.qualifier == "ofis" })
        #expect(context.store.content.entityTimeline[result.path]?.count == 5)
        let mentions = EntityRecognizer.recognize("Mert Aksu", entities: context.store.knownEntities)
        #expect(mentions.first?.candidates.contains { $0.file == result.path } == true)
        await model.save()
        #expect(model.result == result)
    }

    @Test func summaryIncludesRawFailuresAndNewPageRemainsEditable() async throws {
        let context = try EntityPageTestContext()
        defer { context.clean() }
        await context.start()
        let raw = context.root.appendingPathComponent("notes/Su.md")
        try Data("---\nraw: |\n  [[Deniz Arıkan]]\n---\n[[Deniz Arıkan|Deniz]]\n".utf8).write(to: raw)
        await context.store.refresh()
        let detail = EntityDetailModel(store: context.store, path: context.path)
        await detail.load()
        let model = EntityRenameModel(detail: detail, name: "Deniz Arıkan Yılmaz", qualifier: nil)
        await model.save()
        let result = try #require(model.result)
        #expect(result.failures.count == 1)
        #expect(result.failures.first?.path == "notes/Su.md")
        #expect(detail.path == result.path)
        #expect(
            try String(contentsOf: raw, encoding: .utf8)
                == "---\nraw: |\n  [[Deniz Arıkan]]\n---\n[[Deniz Arıkan Yılmaz|Deniz]]\n")
        for _ in 0..<150 where !detail.canEdit { try await Task.sleep(for: .milliseconds(20)) }
        #expect(await detail.addField(key: "Su", text: "Kitap"))
        let file = context.root.appendingPathComponent(result.path)
        #expect(try String(contentsOf: file, encoding: .utf8).contains("Su: Kitap"))
    }
}
