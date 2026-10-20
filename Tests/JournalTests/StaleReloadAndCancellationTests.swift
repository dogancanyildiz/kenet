import Foundation
import Testing
import VaultFormat
import VaultIndex
import VaultStore

@testable import Journal

/// A recognition reload that outlives its vault is never shown on the next one, and an on-demand
/// query whose caller was replaced answers with `CancellationError` instead of its older result.
@MainActor
struct StaleReloadAndCancellationTests {
    /// Every on-demand query that a screen or model reloads when its request changes.
    enum Query: String, CaseIterable, Sendable {
        case summary, onThisDay, importantDates, dayBacklinks, unlinkedMentions
        case graph, entityTimeline, lastEncounters, goalStatuses
        case goalDefinitions, reservedGoalKeys, goalLogs, notificationGoals

        @MainActor func hold(_ gate: FirstArrivalGate, on store: IndexStore) {
            let pass: @MainActor () async -> Void = { await gate.pass() }
            switch self {
            case .summary, .onThisDay, .importantDates, .dayBacklinks, .unlinkedMentions:
                store.testingQueryDidFinish = pass
            case .graph: store.testingGraphQueryDidFinish = pass
            case .entityTimeline, .lastEncounters: store.testingEntityTimelineQueryDidFinish = pass
            case .goalStatuses: store.testingGoalStatusQueryDidFinish = pass
            case .goalDefinitions, .reservedGoalKeys, .goalLogs, .notificationGoals:
                store.testingTaskQueryDidFinish = pass
            }
        }

        @MainActor func run(on store: IndexStore, today: CalendarDate) async throws {
            let person = try #require(store.knownEntities.first { $0.kind == .person })
            switch self {
            case .summary: _ = try await store.periodSummary(.week, containing: today, today: today)
            case .onThisDay: _ = try await store.computeOnThisDay(today)
            case .importantDates: _ = try await store.computeImportantDates(today)
            case .dayBacklinks: _ = try await store.computeDayBacklinks(today)
            case .unlinkedMentions: _ = try await store.computeUnlinkedMentions(of: person)
            case .graph: _ = try await store.computeGraphInput()
            case .entityTimeline: _ = try await store.computeEntityTimeline(for: person.file)
            case .lastEncounters: _ = try await store.computeLastEncounters(asOf: today)
            case .goalStatuses: _ = try await store.computeGoalStatuses(today: today)
            case .goalDefinitions: _ = try await store.computeGoalDefinitions()
            case .reservedGoalKeys: _ = try await store.computeReservedGoalKeys()
            case .goalLogs: _ = try await store.computeGoalLogs(from: today.addingDays(-7)!, through: today)
            case .notificationGoals:
                _ = try await store.computeNotificationGoals(from: today, through: today.addingDays(6)!)
            }
        }
    }

    @Test(arguments: Query.allCases)
    func aCancelledQueryGetsNoAnswer(_ query: Query) async throws {
        let context = try TaskTestContext(sample: true)
        defer { context.clean() }
        await context.start()
        let store = context.store
        let today = context.today
        let gate = FirstArrivalGate()
        query.hold(gate, on: store)

        let replaced = Task { try await query.run(on: store, today: today) }
        await gate.waitUntilHeld()
        replaced.cancel()
        gate.release()
        await #expect(throws: CancellationError.self) { try await replaced.value }
        // The same query, not cancelled, answers.
        try await query.run(on: store, today: today)
    }

    @Test func aReloadThatOutlivesItsVaultLeavesTheNextOneAlone() async throws {
        let context = try TaskTestContext(sample: true)
        defer { context.clean() }
        await context.start()
        let store = context.store
        #expect(!store.mapPlaces.isEmpty && !store.nearbyPlaces.isEmpty && !store.knownEntities.isEmpty)
        let other = try Self.emptyVault(in: context)
        let gate = FirstArrivalGate()
        store.testingRecognitionReloadDidLoad = { await gate.pass() }

        let write = Task { await store.addEvent(on: context.today, text: "Kısa yürüyüş", time: nil) }
        await gate.waitUntilHeld()
        await store.retryVaultAccess()
        #expect(store.vaultURL?.lastPathComponent == other.lastPathComponent)
        let opened = store.lastUpdated
        #expect(opened != nil)
        gate.release()
        #expect(await write.value)

        #expect(store.knownEntities.isEmpty)
        #expect(store.mapPlaces.isEmpty)
        #expect(store.nearbyPlaces.isEmpty)
        #expect(store.entityUsage.isEmpty)
        #expect(store.lastUpdated == opened)
    }

    @Test func anEntitySavedInTheLastVaultIsNotListedInTheNext() async throws {
        let context = try TaskTestContext(sample: true)
        defer { context.clean() }
        await context.start()
        let store = context.store
        _ = try Self.emptyVault(in: context)
        let gate = FirstArrivalGate()
        store.testingRecognitionReloadDidLoad = { await gate.pass() }

        let create = Task { try await store.createEntity(kind: .person, name: "Nil Taslak", qualifier: nil) }
        await gate.waitUntilHeld()
        await store.retryVaultAccess()
        gate.release()
        #expect(try await create.value.name == "Nil Taslak")
        #expect(store.knownEntities.isEmpty)
    }

    @Test func aFailedRecognitionReloadStillMovesLastUpdated() async throws {
        let context = try TaskTestContext(sample: true)
        defer { context.clean() }
        await context.start()
        let store = context.store
        let before = try #require(store.lastUpdated)
        store.testingRecognitionReloadDidLoad = {
            store.testingRecognitionReloadDidLoad = nil
            throw CocoaError(.fileReadUnknown)
        }
        #expect(await store.addEvent(on: context.today, text: "Kısa yürüyüş", time: nil))
        #expect(store.entryErrorText == EntryWriteError.savedWithoutIndex)
        let after = try #require(store.lastUpdated)
        #expect(after > before)
    }

    @Test func aCancelledBacklinkLoadKeepsTheList() async throws {
        let context = try TaskTestContext()
        defer { context.clean() }
        let day = try #require(CalendarDate("2026-10-02"))
        try Self.write(
            ["journal/2026-10-02.md": "## Events\n", "notes/Fikir.md": "Toplantı [[2026-10-02]] günü.\n"],
            in: context.root)
        await context.start()
        let model = DayBacklinksModel(store: context.store)
        await model.load(day: day)
        #expect(model.items.count == 1)

        let gate = FirstArrivalGate()
        context.store.testingQueryDidFinish = { await gate.pass() }
        let replaced = Task { await model.load(day: day) }
        await gate.waitUntilHeld()
        replaced.cancel()
        gate.release()
        await replaced.value
        #expect(model.items.count == 1)
        #expect(model.hasLoaded)
    }

    @Test func aCancelledWeeklyReviewLoadShowsNoError() async throws {
        let context = try TaskTestContext()
        defer { context.clean() }
        try Self.write(["people/Ada Kurgu.md": "---\ntype: person\nname: Ada Kurgu\n---\n"], in: context.root)
        await context.start()
        let model = WeeklyReviewModel(
            store: context.store, today: context.today, calendar: Calendar(identifier: .gregorian),
            defaults: context.defaults.defaults)

        let gate = FirstArrivalGate()
        context.store.testingEntityTimelineQueryDidFinish = { await gate.pass() }
        let replaced = Task { await model.load() }
        await gate.waitUntilHeld()
        replaced.cancel()
        gate.release()
        await replaced.value
        #expect(model.loadErrorText == nil)
    }

    /// A reminder plan already under way is not a screen request: cancelling its caller does
    /// not drop the people reminders.
    @Test func aCancelledPlanStillPlansPeople() async throws {
        let context = try TaskTestContext()
        defer { context.clean() }
        try Self.write(
            [
                "people/Lale Mor.md": "---\ntype: person\nname: Lale Mor\ncadence_days: 7\n---\n",
                "journal/2026-09-20.md": "---\ntype: journal\ndate: 2026-09-20\n---\n\n## Events\n- [[Lale Mor]]\n",
            ], in: context.root)
        await context.start()
        let defaults = try TestDefaults()
        defer { defaults.clean() }
        let service = NotificationService(
            center: FakeNotificationCenter(), defaults: defaults.defaults,
            now: { notificationDate("2026-10-11", hour: 8) }, timeZone: { notificationUTC })
        service.attach(to: context.store)
        service.preferences.tasksEnabled = false
        service.preferences.goalsEnabled = false
        service.preferences.journalEnabled = false
        service.preferences.peopleEnabled = true
        service.update(isOpen: context.store.lastUpdated != nil, vaultID: context.store.vaultURL?.path)

        let gate = FirstArrivalGate()
        context.store.testingEntityTimelineQueryDidFinish = { await gate.pass() }
        let plan = Task { await service.replanNow() }
        await gate.waitUntilHeld()
        plan.cancel()
        gate.release()
        await plan.value
        #expect(service.pending.contains { $0.id == "people-2026-10-11" })
    }

    /// Toggling the preference while a cancelled plan waits on its people: the plan stays the one
    /// writer (a second caller returns at once) and its last pass follows the last preference.
    @Test(arguments: [false, true])
    func aCancelledPlanFollowsTheLastPreference(_ peopleLast: Bool) async throws {
        let context = try TaskTestContext()
        defer { context.clean() }
        try Self.write(
            [
                "people/Lale Mor.md": "---\ntype: person\nname: Lale Mor\ncadence_days: 7\n---\n",
                "journal/2026-09-20.md": "---\ntype: journal\ndate: 2026-09-20\n---\n\n## Events\n- [[Lale Mor]]\n",
            ], in: context.root)
        await context.start()
        let defaults = try TestDefaults()
        defer { defaults.clean() }
        let center = FakeNotificationCenter()
        let service = NotificationService(
            center: center, defaults: defaults.defaults,
            now: { notificationDate("2026-10-11", hour: 8) }, timeZone: { notificationUTC })
        service.attach(to: context.store)
        service.preferences.tasksEnabled = false
        service.preferences.goalsEnabled = false
        service.preferences.journalEnabled = false
        service.preferences.peopleEnabled = true
        service.update(isOpen: context.store.lastUpdated != nil, vaultID: context.store.vaultURL?.path)

        let gate = FirstArrivalGate()
        context.store.testingEntityTimelineQueryDidFinish = { await gate.pass() }
        let plan = Task { await service.replanNow() }
        await gate.waitUntilHeld()
        plan.cancel()
        for _ in 0..<(peopleLast ? 6 : 5) { service.preferences.peopleEnabled.toggle() }
        #expect(service.preferences.peopleEnabled == peopleLast)
        await service.replanNow()
        #expect(service.isPlanning)
        gate.release()
        await plan.value
        #expect(!service.isPlanning)
        #expect(center.maxConcurrentAdds <= 1)
        #expect(service.pending.contains { $0.id == "people-2026-10-11" } == peopleLast)
    }

    /// A refresh of the previous vault failing after the next one opened: the next vault is idle
    /// and shows no error, though no refresh of it is left to clear a busy flag.
    @Test func aRefreshThatFailsAfterItsVaultLeavesTheNextOneIdle() async throws {
        let temp = try testDirectory()
        defer { try? FileManager.default.removeItem(at: temp) }
        let suite = try TestDefaults()
        defer { suite.clean() }
        let gate = FailOnceGate()
        let location = VaultLocation(defaults: suite.defaults, documentsURL: temp, bookmarks: pathBookmarks())
        let store = IndexStore(
            location: location, supportURL: temp.appendingPathComponent("indexes"),
            update: { index, root, rebuild, previous, skip, skipped, previousContent in
                try await gate.pass()
                return try await IndexUpdate.read(
                    index: index, root: root, rebuild: rebuild, previousTypes: previous,
                    skipUnchanged: skip, previousSkipped: skipped, previousContent: previousContent)
            })
        await store.start()
        #expect(store.lastUpdated != nil && !store.isProcessing)
        let next = temp.appendingPathComponent("Next")
        try FileManager.default.createDirectory(at: next, withIntermediateDirectories: true)
        _ = try location.select(next)

        gate.arm()
        let stale = Task { await store.refresh() }
        await gate.waitUntilHeld()
        await store.retryVaultAccess()
        #expect(store.vaultURL?.lastPathComponent == "Next")
        #expect(!store.isProcessing)
        gate.release()
        await stale.value

        #expect(!store.isProcessing)
        #expect(store.errorText == nil)
    }

    /// A refresh of the previous vault still loading recognition when the next one opened leaves
    /// the next vault's `lastUpdated` as its own refresh set it.
    @Test func aRefreshThatOutlivesItsVaultLeavesLastUpdatedAlone() async throws {
        let context = try TaskTestContext(sample: true)
        defer { context.clean() }
        await context.start()
        let store = context.store
        _ = try Self.emptyVault(in: context)
        try Self.write(["people/Nil Taslak.md": "---\ntype: person\nname: Nil Taslak\n---\n"], in: context.root)
        let gate = FirstArrivalGate()
        store.testingRecognitionReloadDidLoad = { await gate.pass() }

        let stale = Task { await store.refresh() }
        await gate.waitUntilHeld()
        await store.retryVaultAccess()
        let opened = try #require(store.lastUpdated)
        gate.release()
        await stale.value

        #expect(store.lastUpdated == opened)
        #expect(store.knownEntities.isEmpty)
        #expect(store.errorText == nil)
    }

    /// A write that outlived its vault is in that vault's files and index: going back shows it.
    @Test func aWriteThatOutlivesItsVaultIsThereOnReturn() async throws {
        let context = try TaskTestContext(sample: true)
        defer { context.clean() }
        await context.start()
        let store = context.store
        _ = try Self.emptyVault(in: context)
        let gate = FirstArrivalGate()
        store.testingRecognitionReloadDidLoad = { await gate.pass() }

        let write = Task { await store.addEvent(on: context.today, text: "Kısa yürüyüş", time: nil) }
        await gate.waitUntilHeld()
        await store.retryVaultAccess()
        gate.release()
        #expect(await write.value)
        #expect(store.entryErrorText == nil)
        #expect(try await store.computeDay(on: context.today).events.isEmpty)

        try Self.select(context.root, in: context)
        await store.retryVaultAccess()
        #expect(store.vaultURL?.lastPathComponent == context.root.lastPathComponent)
        let day = try await store.computeDay(on: context.today)
        #expect(day.events.contains { $0.text.plainText.contains("Kısa yürüyüş") })
        #expect(!store.knownEntities.isEmpty && !store.mapPlaces.isEmpty)
    }

    /// An empty vault next to the test vault, saved as the selected one: `retryVaultAccess`
    /// opens it at once, while a write or refresh is still running.
    private static func emptyVault(in context: TaskTestContext) throws -> URL {
        let other = context.directory.appendingPathComponent("Other")
        try FileManager.default.createDirectory(at: other, withIntermediateDirectories: true)
        try select(other, in: context)
        return other
    }

    /// Saves `root` as the selected vault; `retryVaultAccess` opens it.
    private static func select(_ root: URL, in context: TaskTestContext) throws {
        let location = VaultLocation(
            defaults: context.defaults.defaults, documentsURL: context.directory, bookmarks: pathBookmarks())
        _ = try location.select(root)
    }

    private static func write(_ files: [String: String], in root: URL) throws {
        for (path, text) in files {
            let file = root.appendingPathComponent(path)
            try FileManager.default.createDirectory(
                at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
            try Data(text.utf8).write(to: file)
        }
    }
}

/// Holds the first caller that passes until `release`; every later caller passes straight on.
@MainActor final class FirstArrivalGate {
    private var isOpen = false
    private var held: CheckedContinuation<Void, Never>?

    func pass() async {
        guard !isOpen, held == nil else { return }
        await withCheckedContinuation { held = $0 }
    }

    /// Bounded: a caller that never reaches the gate fails the test instead of hanging it.
    func waitUntilHeld() async {
        if !(await waitUntil { held != nil }) { Issue.record("Expected a caller to reach the gate") }
    }

    func release() {
        isOpen = true
        held?.resume()
        held = nil
    }
}

/// Once armed, holds the next caller until `release`, then fails it; every other caller passes.
@MainActor final class FailOnceGate {
    private var armed = false
    private let gate = FirstArrivalGate()

    func arm() { armed = true }

    func pass() async throws {
        guard armed else { return }
        armed = false
        await gate.pass()
        throw CocoaError(.fileReadUnknown)
    }

    func waitUntilHeld() async { await gate.waitUntilHeld() }
    func release() { gate.release() }
}
