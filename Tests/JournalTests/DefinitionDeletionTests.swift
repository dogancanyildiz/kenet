import Foundation
import Testing

@testable import Journal

@MainActor
struct DefinitionDeletionTests {
    @Test(arguments: [false, true])
    func cancelKeepsFileAndConfirmPublishesRemovalOnce(_ goal: Bool) async throws {
        let context = try EntityPageTestContext()
        defer { context.clean() }
        await context.start()
        let path = goal ? "goals/Spor.md" : context.path
        let file = context.root.appendingPathComponent(path)
        let before = try Data(contentsOf: file)
        let model = DefinitionDeletionModel()
        model.request(path: path)
        #expect(model.confirmation.pending == path)
        #expect(!model.isDeleted)
        #expect(try Data(contentsOf: file) == before)
        model.confirmation.cancel()
        #expect(model.confirmation.confirm() == nil)
        #expect(try Data(contentsOf: file) == before)
        model.request(path: path)
        let confirmedPath = model.confirmation.confirm()
        let confirmed = try #require(confirmedPath)
        #expect(await model.delete(store: context.store, path: confirmed, goal: goal))
        // The views dismiss only on this successful result; a repeat cannot trigger another pop.
        #expect(model.isDeleted)
        #expect(!FileManager.default.fileExists(atPath: file.path))
        #expect(context.store.content.entities.allSatisfy { $0.id != path })
        #expect((try await context.store.goalDefinitions()).allSatisfy { $0.id != path })
        #expect(context.store.knownEntities.allSatisfy { $0.file != path })
        #expect(await !model.delete(store: context.store, path: path, goal: goal))
    }

    @Test func failureKeepsDetailOpenAndAllowsRetry() async throws {
        let context = try EntityPageTestContext()
        defer { context.clean() }
        await context.start()
        let model = DefinitionDeletionModel()
        #expect(await !model.delete(store: context.store, path: "journal/2026-09-27.md", goal: false))
        #expect(!model.isDeleted && !model.isDeleting)
        #expect(model.errorText != nil)
        model.request(path: context.path)
        #expect(model.confirmation.pending == context.path)
    }
}
