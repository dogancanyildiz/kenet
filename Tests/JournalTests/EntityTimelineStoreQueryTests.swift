import Foundation
import Testing
import VaultFormat
import VaultIndex
import VaultStore

@testable import Journal

/// Entity timelines and last encounters come from Core queries on demand, not from the read model.
@MainActor struct EntityTimelineStoreQueryTests {
    @Test func sampleAndSyntheticVaultsMatchTheSnapshotConstruction() async throws {
        let sample = try TaskTestContext(sample: true)
        defer { sample.clean() }
        await sample.start()
        let timelines = try await expectSnapshotConstruction(
            sample, asOf: ["2026-09-01", "2026-09-21", "2026-10-04", "2027-01-01"])
        #expect(timelines["people/Deniz Arıkan.md"]?.count == 5)

        let synthetic = try TaskTestContext()
        defer { synthetic.clean() }
        let manifest = try SyntheticVault.generate(at: synthetic.root, configuration: .compact)
        await synthetic.start()
        let generated = try await expectSnapshotConstruction(synthetic, asOf: ["2026-09-20", "2026-10-05"])
        let linked = try #require(manifest.linkedPersonPath)
        #expect(generated[linked]?.count == SyntheticVault.Configuration.compact.days)
    }

    /// The meeting-cadence reminder reads the same last encounter as the unseen list.
    @Test func cadenceReminderPeopleUseTheLastEncounterQuery() async throws {
        let context = try TaskTestContext(sample: true)
        defer { context.clean() }
        await context.start()
        let index = try VaultIndex()
        try index.rebuild(vaultRoot: context.root)
        let timelines = EntityTimeline.build(snapshot: try index.snapshot())
        for day in ["2026-09-14", "2026-09-21", "2026-10-04"].compactMap(CalendarDate.init) {
            let expected = EntityTimeline.lastEncounters(timelines, asOf: day)
            let people = try await context.store.cadenceReminderPeople(today: day)
            #expect(people.count == context.store.content.entities.filter { $0.kind == "person" }.count)
            for person in people { #expect(person.lastDay == expected[person.id], "\(day) \(person.id)") }
            #expect(people.contains { $0.lastDay != nil })
        }
    }

    @Test func aQueryThatOutlivesItsVaultIsNotAppliedToTheNext() async throws {
        let context = try TaskTestContext(sample: true)
        defer { context.clean() }
        await context.start()
        let store = context.store
        let other = context.directory.appendingPathComponent("Other")
        try FileManager.default.createDirectory(at: other, withIntermediateDirectories: true)
        let deniz = "people/Deniz Arıkan.md"
        let today = CalendarDate("2026-10-04")!
        func switchVaultWhenTheQueryReturns() {
            store.testingEntityTimelineQueryDidFinish = {
                store.testingEntityTimelineQueryDidFinish = nil
                await store.select(other)
            }
        }

        switchVaultWhenTheQueryReturns()
        await #expect(throws: VaultStoreError.staleTarget) {
            try await store.computeEntityTimeline(for: deniz)
        }
        #expect(store.vaultURL?.lastPathComponent == "Other")

        await store.select(context.root)
        #expect(try await store.computeEntityTimeline(for: deniz).count == 5)
        switchVaultWhenTheQueryReturns()
        await #expect(throws: VaultStoreError.staleTarget) {
            try await store.computeLastEncounters(asOf: today)
        }
        #expect(store.vaultURL?.lastPathComponent == "Other")

        await store.select(context.root)
        #expect(try await store.computeLastEncounters(asOf: today)[deniz] == CalendarDate("2026-09-25"))
        switchVaultWhenTheQueryReturns()
        await #expect(throws: VaultStoreError.staleTarget) {
            try await store.cadenceReminderPeople(today: today)
        }
    }

    /// The store's answers equal the old read-model construction from a fresh rebuild of the vault,
    /// for every file of the vault and as of each day.
    private func expectSnapshotConstruction(_ context: TaskTestContext, asOf days: [String]) async throws
        -> [String: [EntityTimelineDay]]
    {
        let index = try VaultIndex()
        try index.rebuild(vaultRoot: context.root)
        let expected = EntityTimeline.build(snapshot: try index.snapshot())
        #expect(!expected.isEmpty)
        let files = Set(try index.files().map(\.path)).union(expected.keys)
        for file in files {
            let timeline = try await context.store.computeEntityTimeline(for: file)
            #expect(EntityTimeline.key(timeline) == EntityTimeline.key(expected[file] ?? []), "\(file)")
        }
        for day in days.compactMap(CalendarDate.init) {
            let encounters = try await context.store.computeLastEncounters(asOf: day)
            #expect(encounters == EntityTimeline.lastEncounters(expected, asOf: day), "\(day)")
        }
        return expected
    }
}
