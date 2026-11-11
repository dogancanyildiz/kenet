import EntityRecognition
import Foundation
import Testing
import VaultFormat
import VaultIndex
import VaultStore

@testable import Journal

/// Entity usage counted from the read model (`EntityUsageCalculator`) against the index query it
/// replaced, and the publish rules around it: a failed recognition reload during a refresh, and the
/// waits that no longer poll. Every vault here is fictional.
@MainActor
struct EntityUsagePublishTests {
    private static let sample = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
        .deletingLastPathComponent().appendingPathComponent("Fixtures/vaults/sample")

    /// Usage from a full read model of `root`, and from the index query, over one fresh index.
    private static func bothCounts(of root: URL) throws -> (model: [EntityUsage]?, index: [EntityUsage]) {
        let index = try VaultIndex()
        try index.rebuild(vaultRoot: root)
        return (VaultReadModel(snapshot: try index.snapshot()).entityUsage(), try index.entityUsage())
    }

    @Test func theSampleCountsAsTheIndexDoes() throws {
        let counts = try Self.bothCounts(of: Self.sample)
        #expect(!counts.index.isEmpty)
        #expect(counts.index.contains { !$0.cooccurrences.isEmpty })
        #expect(counts.model == counts.index)
    }

    /// Goals, unresolved links, links to notes, links between entities, two day files with one date
    /// and links from files that have no date.
    @Test func everyKindOfLinkCountsAsTheIndexDoes() throws {
        let directory = try testDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let root = directory.appendingPathComponent("Vault")
        var files: [String: String] = [
            "goals/Su.md": "---\ntype: goal\nname: Su\nkey: su\nperiod: day\nkind: number\ntarget: 8\n---\n",
            "notes/Fikir.md": "[[Ada Lin]] ve [[Mavi Han]] için bir fikir.\n",
            "people/Ada Lin.md":
                "---\ntype: person\nname: Ada Lin\naliases: [Ada]\n---\n\n[[Bora Taş]] ile tanıştırdı.\n",
            "people/Bora Taş.md": "---\ntype: person\nname: Bora Taş\naliases: []\n---\n",
            "people/Cem Ulu.md": "---\ntype: person\nname: Cem Ulu\naliases: []\n---\n",
            "places/Mavi Han.md": "---\ntype: place\nname: Mavi Han\naliases: []\n---\n",
        ]
        let people = ["Ada Lin", "Bora Taş", "Cem Ulu", "Mavi Han", "Su", "Fikir", "Yok Biri"]
        for day in 1...40 {
            let date = String(format: "2026-03-%02d", (day - 1) % 28 + 1)
            let path = day <= 28 ? "journal/\(date).md" : "journal/\(date) kopya.md"
            let first = people[day % people.count]
            let second = people[(day * 3) % people.count]
            files[path] =
                "---\ntype: journal\ndate: \(date)\n---\n\n## Events\n- 09:00 [[\(first)]] ve [[\(second)]] ^e\(day)\n"
                + (day % 4 == 0 ? "\n## Journal\n[[Ada Lin|Ada]] uğradı.\n" : "")
        }
        for (path, text) in files {
            let url = root.appendingPathComponent(path)
            try FileManager.default.createDirectory(
                at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            try Data(text.utf8).write(to: url)
        }
        let counts = try Self.bothCounts(of: root)
        #expect(counts.index.count == 4)
        #expect(counts.index.contains { $0.cooccurrences.count > 1 })
        #expect(counts.model == counts.index)
    }

    @Test func anUnbuiltOrDriftedModelAsksTheIndex() throws {
        #expect(VaultReadModel.empty.entityUsage() == nil)
        let index = try VaultIndex()
        try index.rebuild(vaultRoot: Self.sample)
        var model = VaultReadModel(snapshot: try index.snapshot())
        #expect(model.entityUsage() != nil)
        model.markNeedsFullReconcile()
        #expect(model.entityUsage() == nil)
        #expect(model.usageRecount(since: nil).isNeedsIndex)
    }

    /// Writes keep the store's usage equal to the index's: a line without a link keeps the rows,
    /// a linked line counts again.
    @Test func writesKeepUsageEqualToTheIndex() async throws {
        let context = try TaskTestContext(sample: true)
        defer { context.clean() }
        await context.start()
        let store = context.store
        func indexUsage() throws -> [EntityUsage] {
            let index = try VaultIndex()
            try index.rebuild(vaultRoot: context.root)
            return try index.entityUsage()
        }
        #expect(store.entityUsage == (try indexUsage()))
        let before = store.content

        // The day's first line opens a new day file: still no link, so the rows stay.
        #expect(await store.addEvent(on: context.today, text: "Kısa yürüyüş", time: nil))
        #expect(store.content.hasSameUsageInputs(as: before))
        let opened = store.content
        #expect(await store.addEvent(on: context.today, text: "Uzun yürüyüş", time: nil))
        #expect(store.content.hasSameUsageInputs(as: opened))
        #expect(store.entityUsage == (try indexUsage()))

        let unlinked = store.content
        #expect(await store.addEvent(on: context.today, text: "[[Deniz Arıkan]] ile kahve", time: nil))
        #expect(!store.content.hasSameUsageInputs(as: unlinked))
        let usage = try indexUsage()
        #expect(store.entityUsage == usage)
        #expect(store.entityUsageByFile["people/Deniz Arıkan.md"]?.lastDate == context.today)
        #expect(store.entityUsageByFile.count == usage.count)
    }

    /// A refresh whose recognition reload fails has already replaced the content: `lastUpdated`
    /// moves with it and the next publish rebuilds the model, as after a failed write.
    @Test func aFailedRecognitionReloadInARefreshStillMovesLastUpdated() async throws {
        let context = try TaskTestContext(sample: true)
        defer { context.clean() }
        await context.start()
        let store = context.store
        let before = try #require(store.lastUpdated)
        let day = context.root.appendingPathComponent("journal/2026-09-20.md")
        try (try String(contentsOf: day, encoding: .utf8) + "\nDışarıdan eklenen satır.\n")
            .write(to: day, atomically: true, encoding: .utf8)
        store.testingRecognitionReloadDidLoad = {
            store.testingRecognitionReloadDidLoad = nil
            throw CocoaError(.fileReadUnknown)
        }
        await store.refresh(directories: ["journal"])
        let after = try #require(store.lastUpdated)
        #expect(after > before)
        #expect(store.errorText != nil)
        #expect(store.content.needsFullReconcile)

        await store.refresh()
        #expect(store.errorText == nil)
        #expect(!store.content.needsFullReconcile)
        #expect(try #require(store.lastUpdated) > after)
    }

    @Test func waitingForARefreshResumesWhenItEnds() async throws {
        let context = try TaskTestContext(sample: true)
        defer { context.clean() }
        await context.start()
        let store = context.store
        let day = context.root.appendingPathComponent("journal/2026-09-21.md")
        try (try String(contentsOf: day, encoding: .utf8) + "\nBir satır daha.\n")
            .write(to: day, atomically: true, encoding: .utf8)
        let gate = FirstArrivalGate()
        store.testingRecognitionReloadDidLoad = { await gate.pass() }
        let refresh = Task { await store.refresh(directories: ["journal"]) }
        await gate.waitUntilHeld()

        var waited = false
        let waiter = Task {
            await store.waitWhileRefreshInFlight()
            waited = true
        }
        let cancelled = Task { await store.waitWhileRefreshInFlight() }
        cancelled.cancel()
        await cancelled.value
        for _ in 0..<20 { await Task.yield() }
        #expect(!waited)

        gate.release()
        await refresh.value
        await waiter.value
        #expect(waited)
        store.testingRecognitionReloadDidLoad = nil
    }

    /// A background caller waits for a queued write without polling and writes after it.
    @Test func backgroundPreparationWaitsForTheWriteInFlight() async throws {
        let context = try TaskTestContext(sample: true)
        defer { context.clean() }
        await context.start()
        let store = context.store
        store.testingOccupyWriteSlot()
        var prepared = false
        let prepare = Task {
            try await store.prepareForBackground()
            prepared = true
        }
        for _ in 0..<20 { await Task.yield() }
        #expect(!prepared)
        store.testingReleaseWriteSlot()
        try await prepare.value
        #expect(prepared)
    }

    @Test func backgroundReadFailuresShowUntilTheNextSuccess() async throws {
        let context = try TaskTestContext(sample: true)
        defer { context.clean() }
        await context.start()
        let store = context.store
        store.noteBackgroundRead(.widget, failure: VaultStoreError.staleTarget)
        store.noteBackgroundRead(.geofence, failure: CancellationError())
        #expect(store.backgroundReadFailures.isEmpty)

        store.noteBackgroundRead(.widget, failure: CocoaError(.fileReadUnknown))
        #expect(store.backgroundReadFailures[.widget] != nil)
        #expect(store.backgroundReadFailures[.geofence] == nil)
        store.noteBackgroundRead(.widget, failure: nil)
        #expect(store.backgroundReadFailures.isEmpty)
    }
}

extension UsageRecount {
    fileprivate var isNeedsIndex: Bool { if case .needsIndex = self { true } else { false } }
}
