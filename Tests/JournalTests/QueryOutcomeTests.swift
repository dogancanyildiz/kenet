import Foundation
import Summaries
import Testing
import VaultFormat
import VaultStore

@testable import Journal

/// A screen's read ends in one of three ways: an answer it shows, a replaced or stale request that
/// leaves the screen as it was with no error, or a failure that keeps the last answer and shows
/// an error.
@MainActor
struct QueryOutcomeTests {
    private static let person = "people/Vera Lale.md"
    private static var failure: String { String(localized: "Kasa okunamadı. Kasayı kontrol edip yeniden dene.") }

    /// The cadence vault, as the people list and the entity card read it.
    private static func cadenceContext() async throws -> TaskTestContext {
        let context = try TaskTestContext()
        let vault = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
            .deletingLastPathComponent().appendingPathComponent("Fixtures/vaults/cadence")
        try FileManager.default.copyItem(at: vault, to: context.root)
        await context.start()
        return context
    }

    @Test func aFailedCadenceReadKeepsTheLastAnswerAndShowsAnError() async throws {
        let context = try await Self.cadenceContext()
        defer { context.clean() }
        let store = context.store
        var cadences = QueryState<[String: PersonCadence]>()
        cadences.apply(await QueryOutcome.of { try await store.personCadences() })
        #expect(cadences.value?[Self.person]?.days == 30)
        #expect(cadences.errorText == nil)

        store.testingQueryDidFinish = { throw CocoaError(.fileReadUnknown) }
        cadences.apply(await QueryOutcome.of { try await store.personCadences() })
        #expect(cadences.value?[Self.person]?.days == 30)
        #expect(cadences.errorText == Self.failure)

        store.testingQueryDidFinish = nil
        cadences.apply(await QueryOutcome.of { try await store.personCadences() })
        #expect(cadences.value?[Self.person]?.days == 30)
        #expect(cadences.errorText == nil)
    }

    @Test func aFirstFailedReadShowsTheErrorWithNoAnswer() async throws {
        let context = try await Self.cadenceContext()
        defer { context.clean() }
        let store = context.store
        store.testingQueryDidFinish = { throw CocoaError(.fileReadUnknown) }
        var cadences = QueryState<[String: PersonCadence]>()
        cadences.apply(await QueryOutcome.of { try await store.personCadences() })
        #expect(cadences.value == nil)
        #expect(cadences.errorText == Self.failure)
    }

    @Test func aReplacedCadenceReadKeepsTheAnswerWithNoError() async throws {
        let context = try await Self.cadenceContext()
        defer { context.clean() }
        let store = context.store
        var cadences = QueryState<[String: PersonCadence]>()
        cadences.apply(await QueryOutcome.of { try await store.personCadences() })
        let gate = FirstArrivalGate()
        store.testingQueryDidFinish = { await gate.pass() }

        let replaced = Task { await QueryOutcome.of { try await store.personCadences() } }
        await gate.waitUntilHeld()
        replaced.cancel()
        gate.release()
        let outcome = await replaced.value
        guard case .cancelled = outcome else {
            Issue.record("Expected a cancelled read, got \(outcome)")
            return
        }
        cadences.apply(outcome)
        #expect(cadences.value?[Self.person]?.days == 30)
        #expect(cadences.errorText == nil)
    }

    @Test func aReadThatOutlivesItsVaultIsStaleWithNoError() async throws {
        let context = try await Self.cadenceContext()
        defer { context.clean() }
        let store = context.store
        let other = context.directory.appendingPathComponent("Other")
        try FileManager.default.createDirectory(at: other, withIntermediateDirectories: true)
        _ = try VaultLocation(
            defaults: context.defaults.defaults, documentsURL: context.directory, bookmarks: pathBookmarks()
        ).select(other)
        var cadences = QueryState<[String: PersonCadence]>()
        cadences.apply(await QueryOutcome.of { try await store.personCadences() })
        let gate = FirstArrivalGate()
        store.testingQueryDidFinish = { await gate.pass() }

        let outlived = Task { await QueryOutcome.of { try await store.personCadences() } }
        await gate.waitUntilHeld()
        await store.retryVaultAccess()
        gate.release()
        let outcome = await outlived.value
        guard case .stale = outcome else {
            Issue.record("Expected a stale read, got \(outcome)")
            return
        }
        cadences.apply(outcome)
        #expect(cadences.value?[Self.person]?.days == 30)
        #expect(cadences.errorText == nil)
    }

    @Test func aFailedTaskListLoadKeepsTheListAndShowsAnError() async throws {
        let context = try TaskTestContext(sample: true)
        defer { context.clean() }
        await context.start()
        let store = context.store
        let today = context.today
        let model = TasksModel(store: store, today: { today })
        await model.loadList()
        let shown = model.agenda.flatMap(\.rows).map(\.id)
        #expect(!shown.isEmpty)
        #expect(model.listErrorText == nil)

        store.testingTaskQueryDidFinish = { throw CocoaError(.fileReadUnknown) }
        await model.loadList()
        #expect(model.agenda.flatMap(\.rows).map(\.id) == shown)
        #expect(model.listErrorText == Self.failure)

        store.testingTaskQueryDidFinish = nil
        await model.loadList()
        #expect(model.listErrorText == nil)
        #expect(model.isListCurrent)
    }

    @Test func aReplacedTaskListLoadKeepsTheListWithNoError() async throws {
        let context = try TaskTestContext(sample: true)
        defer { context.clean() }
        await context.start()
        let store = context.store
        let today = context.today
        let model = TasksModel(store: store, today: { today })
        await model.loadList()
        let shown = model.agenda.flatMap(\.rows).map(\.id)
        let answered = model.loadedListRequest
        model.projectFilter = "Kurgu"
        let gate = FirstArrivalGate()
        store.testingTaskQueryDidFinish = { await gate.pass() }

        let replaced = Task { await model.loadList() }
        await gate.waitUntilHeld()
        replaced.cancel()
        gate.release()
        await replaced.value
        #expect(model.agenda.flatMap(\.rows).map(\.id) == shown)
        #expect(model.loadedListRequest == answered)
        #expect(model.listErrorText == nil)
    }

    /// A shortcut the system cancelled ends as cancelled, not as "the vault is unavailable", and
    /// the next one runs.
    @Test func aCancelledIntentIsNotAnUnavailableVault() async throws {
        let context = try TaskTestContext(sample: true)
        defer { context.clean() }
        let actions = IntentActions(store: context.store, permitsStart: { true })
        let gate = FirstArrivalGate()
        context.store.testingTaskQueryDidFinish = { await gate.pass() }

        let listing = Task { try await actions.goals() }
        await gate.waitUntilHeld()
        listing.cancel()
        gate.release()
        await #expect(throws: CancellationError.self) { try await listing.value }
        #expect(try await !actions.goals().isEmpty)
    }

    @Test func aReplacedEntityPageLoadShowsNoError() async throws {
        let context = try await Self.cadenceContext()
        defer { context.clean() }
        let model = EntityDetailModel(store: context.store, path: Self.person)
        let gate = FirstArrivalGate()
        context.store.testingQueryDidFinish = { await gate.pass() }

        let replaced = Task { await model.load() }
        await gate.waitUntilHeld()
        replaced.cancel()
        gate.release()
        await replaced.value
        #expect(model.errorText == nil)
        #expect(!model.isLoaded)
        await model.load()
        #expect(model.isLoaded && model.personCadence.days == 30)
    }

    @Test func aJournalEditorLeftBeforeItsReadShowsNoError() async throws {
        let context = try await Self.cadenceContext()
        defer { context.clean() }
        let model = JournalEditorModel(store: context.store, day: try #require(CalendarDate("2026-10-01")))
        let gate = FirstArrivalGate()
        context.store.testingQueryDidFinish = { await gate.pass() }

        let left = Task { await model.load() }
        await gate.waitUntilHeld()
        left.cancel()
        gate.release()
        await left.value
        #expect(model.errorText == nil)
        #expect(!model.isLoaded)
        await model.load()
        #expect(model.isLoaded)
    }
}
