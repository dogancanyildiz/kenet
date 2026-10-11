import Foundation
import Testing
import VaultFormat
import VaultIndex
import VaultStore

@testable import Journal

/// The graph screen reads its input from a Core query on demand, not from the read model.
@MainActor struct GraphQueryTests {
    let today = CalendarDate("2026-10-04")!

    @Test func sampleAndSyntheticVaultsMatchTheSnapshotConstruction() async throws {
        let sample = try TaskTestContext(sample: true)
        defer { sample.clean() }
        await sample.start()
        let input = try await expectSnapshotConstruction(sample)
        #expect(input.entities.count == 10 && input.days.count == 14)

        let synthetic = try TaskTestContext()
        defer { synthetic.clean() }
        let manifest = try SyntheticVault.generate(at: synthetic.root, configuration: .compact)
        await synthetic.start()
        let generated = try await expectSnapshotConstruction(synthetic)
        #expect(generated.entities.count == manifest.people.count + manifest.places.count)
        #expect(generated.days.count == SyntheticVault.Configuration.compact.days)
    }

    @Test func aQueryThatOutlivesItsVaultIsNotAppliedToTheNext() async throws {
        let context = try TaskTestContext(sample: true)
        defer { context.clean() }
        await context.start()
        let store = context.store
        let other = context.directory.appendingPathComponent("Other")
        try FileManager.default.createDirectory(at: other, withIntermediateDirectories: true)

        // Another vault is selected while the sample vault's query is out.
        store.testingGraphQueryDidFinish = {
            store.testingGraphQueryDidFinish = nil
            await store.select(other)
        }
        await #expect(throws: VaultStoreError.staleTarget) {
            try await store.computeGraphInput()
        }
        #expect(store.vaultURL?.lastPathComponent == "Other")

        // The same race under the screen: nothing from the sample vault reaches it.
        await store.select(context.root)
        #expect(try await store.computeGraphInput().entities.count == 10)
        let screen = GraphScreenModel(store: store)
        store.testingGraphQueryDidFinish = {
            store.testingGraphQueryDidFinish = nil
            await store.select(other)
        }
        await screen.load(today: today, live: false)
        #expect(screen.graph.nodes.isEmpty && screen.positions.isEmpty && !screen.isLoading)
    }

    /// The query's answer equals the old read-model construction from a fresh rebuild of the vault.
    private func expectSnapshotConstruction(_ context: TaskTestContext) async throws -> GraphInput {
        let index = try VaultIndex()
        try index.rebuild(vaultRoot: context.root)
        let input = try await context.store.computeGraphInput()
        #expect(input == GraphInput(snapshot: try index.snapshot(), entities: context.store.content.entities))
        #expect(!input.totals.isEmpty)
        return input
    }
}
