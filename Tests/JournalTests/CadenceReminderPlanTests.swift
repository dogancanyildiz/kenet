import Foundation
import Summaries
import Testing
import VaultFormat

@testable import Journal

struct CadenceReminderPlanTests {
    private let today = CalendarDate("2026-10-11")!

    @Test func oneDayListsEveryoneAndShowsThreeNames() {
        let people = [
            cadencePerson("people/d.md", name: "Cem", last: "2026-10-03", days: 7),
            cadencePerson("people/a.md", name: "Deniz", last: "2026-08-01", days: 7),
            cadencePerson("people/b.md", name: "Ada", last: "2026-09-01", days: 7),
            cadencePerson("people/c.md", name: "Bora", last: "2026-09-20", days: 7),
        ]
        let planned = CadenceReminderPlan.plan(people: people, days: [today])
        let due = planned[today] ?? []
        #expect(due.map(\.name) == ["Deniz", "Ada", "Bora", "Cem"])
        let message = CadenceReminderPlan.message(people: due, hideContent: false)
        #expect(message.title == String(localized: "Görüşme zamanı"))
        #expect(message.body == String(localized: "\("Deniz"), \("Ada"), \("Bora") ve \(1) kişi daha"))
        #expect(!message.body.contains("Cem"))
        #expect(!message.title.contains("Deniz"))
    }

    @Test func equalOverdueBreaksTiesByIdentifier() {
        let people = [
            cadencePerson("people/b.md", name: "Ada", last: "2026-10-01", days: 7),
            cadencePerson("people/a.md", name: "Ada", last: "2026-10-01", days: 7),
        ]
        let due = CadenceReminderPlan.plan(people: people, days: [today])[today] ?? []
        #expect(due.map(\.id) == ["people/a.md", "people/b.md"])
        let message = CadenceReminderPlan.message(people: due, hideContent: false)
        #expect(message.body == String(localized: "\("Ada") ve \("Ada")"))
    }

    @Test func pausedSnoozedRhythmlessAndNeverMetStayOut() {
        let people = [
            cadencePerson("people/paused.md", name: "Pera", last: "2026-08-01", days: 7, paused: true),
            cadencePerson("people/plain.md", name: "Sade", last: "2026-01-01", days: nil),
            cadencePerson("people/never.md", name: "Nila", last: nil, days: 7),
            cadencePerson("people/later.md", name: "Gelecek", last: "2026-10-12", days: 7),
        ]
        #expect(CadenceReminderPlan.plan(people: people, days: cadenceWindow(from: today)).isEmpty)
    }

    @Test func snoozeHidesThroughThatDayAndReturnsTheNext() {
        let person = cadencePerson(
            "people/Fela.md", name: "Fela", last: "2026-09-01", days: 7, snoozed: "2026-10-12")
        let planned = CadenceReminderPlan.plan(people: [person], days: cadenceWindow(from: today))
        #expect(planned[today] == nil)
        #expect(planned[CalendarDate("2026-10-12")!] == nil)
        #expect(planned[CalendarDate("2026-10-13")!]?.map(\.id) == ["people/Fela.md"])
    }

    @Test func quietPeriodUsesAQuarterOfTheRhythmAndAtLeastThreeDays() {
        let person = cadencePerson("people/Lale.md", name: "Lale", last: "2026-09-01", days: 12)
        #expect(CadenceReminderPlan.quietDays(cadence: 12) == 3)
        #expect(CadenceReminderPlan.quietDays(cadence: 11) == 3)
        #expect(CadenceReminderPlan.quietDays(cadence: 16) == 4)
        #expect(CadenceReminderPlan.quietDays(cadence: 30) == 7)
        let blocked = CadenceReminderPlan.plan(
            people: [person], days: [today], lastNotified: ["people/Lale.md": CalendarDate("2026-10-09")!])
        #expect(blocked.isEmpty)
        let open = CadenceReminderPlan.plan(
            people: [person], days: [today], lastNotified: ["people/Lale.md": CalendarDate("2026-10-08")!])
        #expect(open[today]?.map(\.id) == ["people/Lale.md"])
        let longer = cadencePerson("people/Lale.md", name: "Lale", last: "2026-09-01", days: 16)
        let stillQuiet = CadenceReminderPlan.plan(
            people: [longer], days: [today], lastNotified: ["people/Lale.md": CalendarDate("2026-10-08")!])
        #expect(stillQuiet.isEmpty)
        let released = CadenceReminderPlan.plan(
            people: [longer], days: [today], lastNotified: ["people/Lale.md": CalendarDate("2026-10-07")!])
        #expect(released[today]?.map(\.id) == ["people/Lale.md"])
    }

    @Test func theSamePersonIsNotRepeatedInsideTheQuietGap() {
        let person = cadencePerson("people/Lale.md", name: "Lale", last: "2026-09-01", days: 7)
        let planned = CadenceReminderPlan.plan(people: [person], days: cadenceWindow(from: today))
        #expect(planned.keys.sorted() == [today, CalendarDate("2026-10-14")!, CalendarDate("2026-10-17")!])
    }

    @Test func aThirtyDayRhythmFillsOnlyTheFirstDayOfTheWindow() {
        let person = cadencePerson("people/Lale.md", name: "Lale", last: "2026-09-01", days: 30)
        let planned = CadenceReminderPlan.plan(people: [person], days: cadenceWindow(from: today))
        #expect(planned.keys.sorted() == [today])
        #expect(planned[today.addingDays(6)!] == nil)
    }

    @Test func aMeetingAfterTheReminderStartsANewCycle() {
        let met = cadencePerson("people/Lale.md", name: "Lale", last: "2026-10-10", days: 1)
        let planned = CadenceReminderPlan.plan(
            people: [met], days: [today], lastNotified: ["people/Lale.md": CalendarDate("2026-10-09")!])
        #expect(planned[today]?.map(\.id) == ["people/Lale.md"])
        let seenToday = cadencePerson("people/Lale.md", name: "Lale", last: "2026-10-11", days: 30)
        #expect(CadenceReminderPlan.plan(people: [seenToday], days: cadenceWindow(from: today)).isEmpty)
    }

    @Test func hiddenContentUsesTheCountAndNoNames() {
        let people = [
            cadencePerson("people/a.md", name: "Deniz", last: "2026-08-01", days: 7),
            cadencePerson("people/b.md", name: "Ada", last: "2026-09-01", days: 7),
        ]
        let due = CadenceReminderPlan.plan(people: people, days: [today])[today] ?? []
        let hidden = CadenceReminderPlan.message(people: due, hideContent: true)
        #expect(hidden.body == String(localized: "Görüşme zamanı gelen \(2) kişi var"))
        #expect(!hidden.body.contains("Deniz"))
        #expect(!hidden.body.contains("Ada"))
        #expect(!hidden.title.contains("Deniz"))
    }

    @Test func fiveDuePeopleShareOneBodyWithThreeNamesAndTheRest() {
        let people = (1...5).map {
            cadencePerson("people/\($0).md", name: "Ad\($0)", last: "2026-09-0\($0)", days: 7)
        }
        let planned = CadenceReminderPlan.plan(people: people.reversed(), days: [today])
        let due = planned[today] ?? []
        #expect(planned.count == 1 && due.count == 5)
        let body = CadenceReminderPlan.message(people: due, hideContent: false).body
        #expect(body == String(localized: "\("Ad1"), \("Ad2"), \("Ad3") ve \(2) kişi daha"))
        #expect(!body.contains("Ad4") && !body.contains("Ad5"))
    }

    @Test func onlyAPendingRequestWhoseInstantHasPassedCountsAsFired() {
        let id = "people/Lale.md"
        let memory = CadenceReminderMemory(
            fired: [id: CalendarDate("2026-10-05")!, "people/Ada.md": CalendarDate("2026-10-09")!],
            pending: [
                CadenceReminderAssignment(
                    day: CalendarDate("2026-10-08")!, date: notificationDate("2026-10-08", hour: 10),
                    personIDs: [id, "people/Ada.md"]),
                CadenceReminderAssignment(day: today, date: notificationDate("2026-10-11", hour: 10), personIDs: [id]),
                CadenceReminderAssignment(
                    day: CalendarDate("2026-10-14")!, date: notificationDate("2026-10-14", hour: 10),
                    personIDs: [id]),
            ])
        let before = memory.settled(at: notificationDate("2026-10-11", hour: 9, minute: 59))
        #expect(before.fired == [id: CalendarDate("2026-10-08")!, "people/Ada.md": CalendarDate("2026-10-09")!])
        #expect(before.pending.isEmpty)
        let after = memory.settled(at: notificationDate("2026-10-11", hour: 10))
        #expect(after.fired[id] == today)
    }

    @Test func historyRoundTripsPerVaultAndDropsPeopleWhoLeft() throws {
        let defaults = try TestDefaults()
        defer { defaults.clean() }
        let request = CadenceReminderAssignment(
            day: today, date: notificationDate("2026-10-11", hour: 10), personIDs: ["people/a.md", "people/old.md"])
        var history = CadenceReminderHistory()
        history.record([request], known: nil, vaultID: "vault-a")
        history.record([request], known: nil, vaultID: nil)
        history.persist(in: defaults.defaults)
        #expect(CadenceReminderHistory.read(from: defaults.defaults, vaultID: "vault-a").pending == [request])
        #expect(CadenceReminderHistory.read(from: defaults.defaults, vaultID: "vault-b") == CadenceReminderMemory())
        #expect(CadenceReminderHistory.read(from: defaults.defaults, vaultID: nil) == CadenceReminderMemory())

        var later = CadenceReminderHistory(from: defaults.defaults)
        later.settle(at: notificationDate("2026-10-11", hour: 11))
        #expect(later.memory(vaultID: "vault-a").fired == ["people/a.md": today, "people/old.md": today])
        later.record([], known: ["people/a.md"], vaultID: "vault-a")
        later.persist(in: defaults.defaults)
        #expect(
            CadenceReminderHistory.read(from: defaults.defaults, vaultID: "vault-a")
                == CadenceReminderMemory(fired: ["people/a.md": today]))
        later.record([], known: [], vaultID: "vault-a")
        later.persist(in: defaults.defaults)
        #expect(defaults.defaults.data(forKey: CadenceReminderHistory.storageKey) == nil)
    }

    @Test func duplicateIdentifierIsListedOnce() {
        let person = cadencePerson("people/Lale.md", name: "Lale", last: "2026-09-01", days: 7)
        let due = CadenceReminderPlan.plan(people: [person, person], days: [today])[today] ?? []
        #expect(due.map(\.id) == ["people/Lale.md"])
    }
}

@MainActor
private final class ReminderClock {
    var now: Date
    init(_ day: String, hour: Int) { now = notificationDate(day, hour: hour) }
    func set(_ day: String, hour: Int) { now = notificationDate(day, hour: hour) }
}

@MainActor
struct CadenceReminderServiceTests {
    private let lale = "people/Lale.md"

    private func peopleIDs(_ center: FakeNotificationCenter) -> [String] {
        center.values.keys.filter { $0.hasPrefix("people-") }.sorted()
    }

    /// Only the people reminder is on, so every pending request is a `people-` one.
    private func service(
        _ center: FakeNotificationCenter, defaults: TestDefaults, clock: ReminderClock, vault: String = "vault-a",
        people: [CadenceReminderPerson]?
    ) -> NotificationService {
        let service = NotificationService(
            center: center, defaults: defaults.defaults, now: { clock.now }, timeZone: { notificationUTC })
        service.update(snapshot: .empty, vaultID: vault)
        service.preferences.tasksEnabled = false
        service.preferences.goalsEnabled = false
        service.preferences.journalEnabled = false
        service.preferences.peopleEnabled = true
        service.useCadencePeople(people)
        return service
    }

    @Test func turningThePreferenceOffCancelsPeopleNotifications() async throws {
        let defaults = try TestDefaults()
        defer { defaults.clean() }
        let center = FakeNotificationCenter()
        let service = service(
            center, defaults: defaults, clock: ReminderClock("2026-10-11", hour: 8),
            people: [cadencePerson(lale, name: "Lale", last: "2026-09-01", days: 7)])
        await service.replanNow()
        #expect(
            service.pending.map(\.id) == ["people-2026-10-11", "people-2026-10-14", "people-2026-10-17"])
        let scheduled = CadenceReminderHistory.read(from: defaults.defaults, vaultID: "vault-a")
        #expect(scheduled.pending.map(\.day.description) == ["2026-10-11", "2026-10-14", "2026-10-17"])
        #expect(scheduled.pending.first?.date == notificationDate("2026-10-11", hour: 10))
        #expect(scheduled.pending.allSatisfy { $0.personIDs == [lale] })
        #expect(scheduled.fired.isEmpty)
        service.preferences.peopleEnabled = false
        await service.replanNow()
        #expect(service.pending.isEmpty && center.values.isEmpty)
        #expect(center.removals.last?.contains("people-2026-10-11") == true)
        #expect(CadenceReminderHistory.read(from: defaults.defaults, vaultID: "vault-a") == CadenceReminderMemory())
    }

    @Test func aFiredReminderIsRememberedAndBlocksTheNextDays() async throws {
        let defaults = try TestDefaults()
        defer { defaults.clean() }
        let clock = ReminderClock("2026-10-11", hour: 8)
        let center = FakeNotificationCenter()
        let service = service(
            center, defaults: defaults, clock: clock,
            people: [cadencePerson(lale, name: "Lale", last: "2026-09-01", days: 30)])
        await service.replanNow()
        #expect(peopleIDs(center) == ["people-2026-10-11"])
        clock.set("2026-10-11", hour: 11)
        await service.replanNow()
        #expect(peopleIDs(center).isEmpty)
        #expect(CadenceReminderHistory.read(from: defaults.defaults, vaultID: "vault-a").fired[lale] == today)
        // Quarter of thirty is seven: the first day the person may return is the 18th.
        clock.set("2026-10-17", hour: 8)
        await service.replanNow()
        #expect(peopleIDs(center) == ["people-2026-10-18"])
    }

    private var today: CalendarDate { CalendarDate("2026-10-11")! }

    /// The app was closed while the plan ran: the latest fired day counts, not the first planned one.
    @Test func everyFiredDayOfAnOldPlanCountsWhenTheAppReturns() async throws {
        let defaults = try TestDefaults()
        defer { defaults.clean() }
        let clock = ReminderClock("2026-10-11", hour: 8)
        let center = FakeNotificationCenter()
        let service = service(
            center, defaults: defaults, clock: clock,
            people: [cadencePerson(lale, name: "Lale", last: "2026-09-01", days: 7)])
        await service.replanNow()
        #expect(peopleIDs(center) == ["people-2026-10-11", "people-2026-10-14", "people-2026-10-17"])
        clock.set("2026-10-15", hour: 8)
        await service.replanNow()
        #expect(
            CadenceReminderHistory.read(from: defaults.defaults, vaultID: "vault-a").fired[lale]
                == CalendarDate("2026-10-14"))
        #expect(peopleIDs(center) == ["people-2026-10-17", "people-2026-10-20"])
    }

    @Test func movingTheTimeLaterDoesNotRepeatTodaysFiredReminder() async throws {
        let defaults = try TestDefaults()
        defer { defaults.clean() }
        let clock = ReminderClock("2026-10-11", hour: 8)
        let center = FakeNotificationCenter()
        let service = service(
            center, defaults: defaults, clock: clock,
            people: [cadencePerson(lale, name: "Lale", last: "2026-09-01", days: 7)])
        await service.replanNow()
        clock.set("2026-10-11", hour: 12)
        service.preferences.peopleTime = NotificationTime(hour: 18)
        await service.replanNow()
        #expect(peopleIDs(center) == ["people-2026-10-14", "people-2026-10-17"])
        #expect(CadenceReminderHistory.read(from: defaults.defaults, vaultID: "vault-a").fired[lale] == today)
    }

    @Test func movingTheTimeEarlierDoesNotCountAWithdrawnReminderAsFired() async throws {
        let defaults = try TestDefaults()
        defer { defaults.clean() }
        let clock = ReminderClock("2026-10-11", hour: 8)
        let center = FakeNotificationCenter()
        let service = service(
            center, defaults: defaults, clock: clock,
            people: [cadencePerson(lale, name: "Lale", last: "2026-09-01", days: 7)])
        service.preferences.peopleTime = NotificationTime(hour: 18)
        await service.replanNow()
        #expect(center.values["people-2026-10-11"]?.date == notificationDate("2026-10-11", hour: 18))
        clock.set("2026-10-11", hour: 12)
        service.preferences.peopleTime = NotificationTime(hour: 10)
        await service.replanNow()
        #expect(peopleIDs(center) == ["people-2026-10-12", "people-2026-10-15"])
        #expect(CadenceReminderHistory.read(from: defaults.defaults, vaultID: "vault-a").fired.isEmpty)
    }

    /// The previous vault's names must not stay scheduled, and its withdrawn plan must not count as fired.
    @Test func switchingTheVaultCancelsItsPeopleRemindersAndForgetsThePlan() async throws {
        let defaults = try TestDefaults()
        defer { defaults.clean() }
        let clock = ReminderClock("2026-10-11", hour: 8)
        let center = FakeNotificationCenter()
        let person = cadencePerson(lale, name: "Lale", last: "2026-09-01", days: 7)
        let service = service(center, defaults: defaults, clock: clock, people: [person])
        await service.replanNow()
        #expect(peopleIDs(center).count == 3)

        // The new vault is still loading; the injected reader still answers with the old people.
        service.update(snapshot: nil, vaultID: "vault-b")
        await service.replanNow()
        #expect(center.values.isEmpty)
        #expect(CadenceReminderHistory.read(from: defaults.defaults, vaultID: "vault-a") == CadenceReminderMemory())

        service.useCadencePeople([cadencePerson("people/Ada.md", name: "Ada", last: "2026-09-01", days: 7)])
        service.update(snapshot: .empty, vaultID: "vault-b")
        await service.replanNow()
        #expect(center.values.values.allSatisfy { $0.body == "Ada" })
        #expect(CadenceReminderHistory.read(from: defaults.defaults, vaultID: "vault-a") == CadenceReminderMemory())

        // Back in the first vault after its planned hour: nothing fired there, so today is skipped
        // only because the hour has passed, and tomorrow is free.
        clock.set("2026-10-11", hour: 12)
        service.useCadencePeople([person])
        service.update(snapshot: .empty, vaultID: "vault-a")
        await service.replanNow()
        #expect(center.values.values.allSatisfy { $0.body == "Lale" })
        #expect(peopleIDs(center) == ["people-2026-10-12", "people-2026-10-15"])
        // The second vault's 10:00 request did fire, and only its own record says so.
        #expect(
            CadenceReminderHistory.read(from: defaults.defaults, vaultID: "vault-b").fired
                == ["people/Ada.md": today])
    }

    @Test func aFailedPeopleReadPlansNothingAndKeepsTheRecord() async throws {
        let defaults = try TestDefaults()
        defer { defaults.clean() }
        let clock = ReminderClock("2026-10-11", hour: 8)
        let center = FakeNotificationCenter()
        let person = cadencePerson(lale, name: "Lale", last: "2026-09-01", days: 30)
        let service = service(center, defaults: defaults, clock: clock, people: [person])
        await service.replanNow()
        clock.set("2026-10-11", hour: 11)
        service.useCadencePeople(nil)
        await service.replanNow()
        #expect(center.values.isEmpty)
        #expect(CadenceReminderHistory.read(from: defaults.defaults, vaultID: "vault-a").fired == [lale: today])
        // A person who lost the rhythm leaves the record.
        service.useCadencePeople([cadencePerson(lale, name: "Lale", last: "2026-09-01", days: nil)])
        await service.replanNow()
        #expect(CadenceReminderHistory.read(from: defaults.defaults, vaultID: "vault-a").fired.isEmpty)
    }

    @Test func aRequestTheSystemRejectedIsNotRecorded() async throws {
        let defaults = try TestDefaults()
        defer { defaults.clean() }
        let center = FakeNotificationCenter()
        center.failIDs = ["people-2026-10-11"]
        let service = service(
            center, defaults: defaults, clock: ReminderClock("2026-10-11", hour: 8),
            people: [cadencePerson(lale, name: "Lale", last: "2026-09-01", days: 7)])
        await service.replanNow()
        #expect(
            CadenceReminderHistory.read(from: defaults.defaults, vaultID: "vault-a").pending.map(\.day.description)
                == ["2026-10-14", "2026-10-17"])
    }

    @Test func withoutPermissionNothingIsPlannedOrRecorded() async throws {
        let defaults = try TestDefaults()
        defer { defaults.clean() }
        let center = FakeNotificationCenter()
        center.status = .denied
        let service = service(
            center, defaults: defaults, clock: ReminderClock("2026-10-11", hour: 8),
            people: [cadencePerson(lale, name: "Lale", last: "2026-09-01", days: 7)])
        await service.replanNow()
        #expect(center.values.isEmpty)
        #expect(CadenceReminderHistory.read(from: defaults.defaults, vaultID: "vault-a") == CadenceReminderMemory())
    }

    @Test func notificationRouteOpensTheUnseenPeopleSection() {
        #expect(NotificationDestination.from(identifier: "people-2026-10-11") == .people)
        #expect(NotificationDestination.from(identifier: "people-2026-13-01") == nil)
        #expect(NotificationDestination.from(identifier: "people-other") == nil)
        #expect(NotificationRoute(.people) == .unseenPeople)
        #expect(NotificationRoute(.tasks) == .tasks)
        #expect(NotificationRoute(.goals) == .today)
        #expect(NotificationRoute(.journal) == .today)
    }
}

@MainActor
struct CadenceReminderVaultTests {
    @Test func meetingSnoozePauseAndRhythmChangeRebuildThePlan() async throws {
        let context = try TaskTestContext(sample: false)
        defer { context.clean() }
        let people = context.root.appendingPathComponent("people")
        let journal = context.root.appendingPathComponent("journal")
        try FileManager.default.createDirectory(at: people, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: journal, withIntermediateDirectories: true)
        try Data("---\ntype: person\nname: Lale Mor\ncadence_days: 7\n---\n".utf8).write(
            to: people.appendingPathComponent("Lale Mor.md"))
        try Data("---\ntype: journal\ndate: 2026-09-20\n---\n\n## Events\n- [[Lale Mor]]\n".utf8).write(
            to: journal.appendingPathComponent("2026-09-20.md"))
        await context.start()
        let today = CalendarDate("2026-10-11")!
        let path = try #require(context.store.content.entities.first { $0.name == "Lale Mor" }?.id)
        let loaded = try await context.store.cadenceReminderPeople(today: today)
        let lale = try #require(loaded.first { $0.id == path })
        #expect(lale.cadence.days == 7)
        #expect(lale.lastDay == CalendarDate("2026-09-20"))

        let defaults = try TestDefaults()
        defer { defaults.clean() }
        let center = FakeNotificationCenter()
        let service = NotificationService(
            center: center, defaults: defaults.defaults, now: { notificationDate("2026-10-11", hour: 8) },
            timeZone: { notificationUTC })
        service.attach(to: context.store)
        service.preferences.tasksEnabled = false
        service.preferences.goalsEnabled = false
        service.preferences.journalEnabled = false
        service.preferences.peopleEnabled = true
        service.update(snapshot: context.store.content, vaultID: context.store.vaultURL?.path)
        await service.replanNow()
        #expect(service.pending.contains { $0.id == "people-2026-10-11" })

        try await context.store.setField(at: path, key: PersonCadence.snoozeKey, value: .date(today))
        await service.replanNow()
        #expect(!service.pending.contains { $0.id == "people-2026-10-11" })
        #expect(service.pending.contains { $0.id == "people-2026-10-12" })

        try await context.store.setField(at: path, key: PersonCadence.pauseKey, value: .boolean(true))
        await service.replanNow()
        #expect(service.pending.allSatisfy { !$0.id.hasPrefix("people-") })

        try await context.store.removeField(at: path, key: PersonCadence.pauseKey)
        try await context.store.removeField(at: path, key: PersonCadence.snoozeKey)
        try await context.store.setField(at: path, key: PersonCadence.dayKey, value: .integer(365))
        await service.replanNow()
        #expect(service.pending.allSatisfy { !$0.id.hasPrefix("people-") })

        try await context.store.setField(at: path, key: PersonCadence.dayKey, value: .integer(7))
        await service.replanNow()
        #expect(service.pending.contains { $0.id == "people-2026-10-11" })
        #expect(await context.store.addEvent(on: today, text: "[[Lale Mor]]", time: nil))
        await service.replanNow()
        #expect(service.pending.allSatisfy { !$0.id.hasPrefix("people-") })
    }
}
