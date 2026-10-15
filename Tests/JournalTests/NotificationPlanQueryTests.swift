import Foundation
import GoalTracking
import Testing
import VaultFormat
import VaultIndex

@testable import Journal

/// The notification plan from the week the store queries (`IndexStore.computeNotificationDays`)
/// against the plan `dev` made from the read model's `tasks` and published days: every request,
/// id, title, body and date, on every morning of a month, on the sample with the task edge cases,
/// on an edge-case day vault, and after edits.
@MainActor struct NotificationPlanQueryTests {
    @Test func sampleWithTaskEdgeCasesPlansLikeDev() async throws {
        let context = try TaskTestContext(sample: true)
        defer { context.clean() }
        await context.start()
        try TasksStoreQueryTests.writeEdgeCases(context)
        await context.store.refresh()
        let counts = try await expectDevPlans(context, from: "2026-09-12", mornings: 30)
        #expect(counts.task > 20 && counts.journal > 20)

        // By hand: on 3 October "today" and "weekly" are due; on the 4th only the `[?]` task, which
        // is open and named.
        let morning = try await plan(context.store, on: "2026-10-03")
        let task = try #require(morning.first { $0.id == "task-2026-10-03" })
        #expect(task.title == String(localized: "\(2) görev bugün"))
        #expect(morning.first { $0.id == "task-2026-10-04" }?.title == "unknown")
    }

    /// The day reminders by hand: a heading or a CRLF event writes a day; tasks, a goal value, an
    /// empty file, another section or an invalid file do not.
    @Test func edgeCaseDayVaultPlansLikeDev() async throws {
        let context = try TaskTestContext()
        defer { context.clean() }
        try Self.writeDayEdgeCases(context.root)
        await context.start()
        let counts = try await expectDevPlans(context, from: "2026-08-28", mornings: 30)
        #expect(counts.task > 0 && counts.journal > 0)

        let journal = try await plan(context.store, on: "2026-09-02").filter { $0.destination == .journal }
        #expect(
            journal.map(\.id) == ["2026-09-03", "2026-09-04", "2026-09-05", "2026-09-06"].map { "journal-\($0)" })
        let later = try await plan(context.store, on: "2026-09-09").filter { $0.destination == .journal }
        // 2026-9-10 is not a day file, `arsiv/` is not `journal/<date>.md`, and the notes only link
        // to the days; the unreadable 14th stays unwritten.
        #expect(later.map(\.id) == (9...15).map { "journal-2026-09-\(String(format: "%02d", $0))" })
        let task = try #require(try await plan(context.store, on: "2026-09-03").first { $0.id == "task-2026-09-03" })
        #expect(task.title == "yalnız görev")
        #expect(task.body.isEmpty)
    }

    /// After writes through the store and an outside edit the plan still equals `dev`'s.
    @Test func editsKeepThePlanEqualToDev() async throws {
        let context = try TaskTestContext(sample: true)
        defer { context.clean() }
        await context.start()
        try TasksStoreQueryTests.writeEdgeCases(context)
        await context.store.refresh()
        let store = context.store
        let today = context.today
        func check(_ label: String) async throws {
            _ = try await expectDevPlans(context, from: "2026-09-30", mornings: 6, label: label)
        }
        func row(_ identifier: String) async throws -> TaskRow {
            try #require(try await store.allTasks().first { $0.sourceIdentifier == identifier })
        }
        try await store.completeTask(try await row("past"), on: today)
        try await check("complete")
        let moving = try await row("today")
        #expect(await TaskMove.apply([moving], to: CalendarDate("2026-10-05")!, in: store).moved == 1)
        try await check("move")
        #expect(await store.addTask(on: today, text: "yeni iş", due: CalendarDate("2026-10-04")))
        try await check("add")
        #expect(await store.addEvent(on: CalendarDate("2026-10-04")!, text: "Bir an", time: nil))
        try await check("event")
        try FileManager.default.removeItem(at: context.root.appendingPathComponent("notes/Edge.md"))
        // The watcher may still be refreshing after the writes above; `refresh()` then only queues
        // a rescan and returns, so the plan is read once that rescan has published.
        await store.refresh()
        await store.waitWhileRefreshInFlight()
        try await check("outside delete")
    }

    /// The service plans from the store's week: what it schedules equals `dev`'s plan, and a week
    /// that could not be read schedules no task or journal reminder.
    @Test func theServicePlansFromTheStoresWeek() async throws {
        let context = try TaskTestContext(sample: true)
        defer { context.clean() }
        let defaults = try TestDefaults()
        defer { defaults.clean() }
        await context.start()
        let center = FakeNotificationCenter()
        let now = notificationDate("2026-09-27")
        let service = NotificationService(
            center: center, defaults: defaults.defaults, now: { now }, timeZone: { notificationUTC })
        service.attach(to: context.store)
        await service.replanNow()
        let expected = legacyPlan(try LegacyVault(context), now: now, preferences: NotificationPreferences())
        #expect(expected.contains { $0.destination == .tasks } && expected.contains { $0.destination == .journal })
        #expect(service.pending == expected)

        service.useVaultDays(nil)
        await service.replanNow()
        #expect(!service.pending.isEmpty)
        #expect(service.pending.allSatisfy { $0.destination == .goals })
    }

    /// The service reads the whole week: a task due on its seventh day is named, and an event
    /// written that day keeps its evening reminder away.
    @Test func theServiceReadsTheSeventhDayToo() async throws {
        let context = try TaskTestContext(sample: true)
        defer { context.clean() }
        await context.start()
        let seventh = CalendarDate("2026-10-03")!
        #expect(await context.store.addTask(on: seventh, text: "yedinci gün işi", due: seventh))
        #expect(await context.store.addEvent(on: seventh, text: "Yedinci gün olayı", time: nil))
        let (service, now) = serviceAt("2026-09-27", context: context)
        await service.replanNow()
        let expected = legacyPlan(try LegacyVault(context), now: now, preferences: NotificationPreferences())
        #expect(service.pending == expected)
        #expect(service.pending.first { $0.id == "task-\(seventh)" }?.title == "yedinci gün işi")
        #expect(!service.pending.contains { $0.id == "journal-\(seventh)" })
    }

    /// With task reminders off and journal reminders on, the service still reads the week: a
    /// written day gets no journal reminder.
    @Test func journalRemindersAloneStillReadTheWeek() async throws {
        let context = try TaskTestContext(sample: true)
        defer { context.clean() }
        await context.start()
        let day = CalendarDate("2026-09-28")!
        #expect(await context.store.addEvent(on: day, text: "Yazılmış gün", time: nil))
        let (service, now) = serviceAt("2026-09-27", context: context)
        var preferences = NotificationPreferences()
        preferences.tasksEnabled = false
        service.preferences = preferences
        await service.replanNow()
        let expected = legacyPlan(try LegacyVault(context), now: now, preferences: preferences)
        #expect(expected.contains { $0.destination == .journal })
        #expect(service.pending == expected)
        #expect(!service.pending.contains { $0.id == "journal-\(day)" })
        #expect(service.pending.allSatisfy { $0.destination != .tasks })
    }

    private func serviceAt(_ day: String, context: TaskTestContext) -> (NotificationService, Date) {
        let now = notificationDate(day)
        let service = NotificationService(
            center: FakeNotificationCenter(), defaults: context.defaults.defaults, now: { now },
            timeZone: { notificationUTC })
        service.attach(to: context.store)
        return (service, now)
    }

    // MARK: - Construction

    /// Each morning from `first`, at 08:00 and 20:00 and with content shown or hidden, the plan
    /// from the queried week equals `dev`'s. Returns how many task and journal requests it saw.
    @discardableResult
    private func expectDevPlans(
        _ context: TaskTestContext, from first: String, mornings: Int, label: String = ""
    ) async throws -> (task: Int, journal: Int) {
        let start = try #require(CalendarDate(first))
        let legacy = try LegacyVault(context)
        var seen = (task: 0, journal: 0)
        for offset in 0..<mornings {
            let day = try #require(start.addingDays(offset))
            for hour in [8, 20] {
                for hidden in [false, true] {
                    var preferences = NotificationPreferences()
                    preferences.hideContent = hidden
                    let now = notificationDate(day.description, hour: hour)
                    let queried = try await plan(context.store, now: now, preferences: preferences)
                    let expected = legacyPlan(legacy, now: now, preferences: preferences)
                    #expect(queried == expected, "\(label) \(day) \(hour) \(hidden)")
                    seen.task += queried.count { $0.destination == .tasks }
                    seen.journal += queried.count { $0.destination == .journal }
                }
            }
        }
        return seen
    }

    private func plan(
        _ store: IndexStore, on day: String = "", now: Date? = nil,
        preferences: NotificationPreferences = NotificationPreferences()
    ) async throws -> [NotificationRequest] {
        let now = now ?? notificationDate(day)
        let first = LocalDay.today(at: now, timeZone: notificationUTC)
        let week = try await store.computeNotificationDays(from: first, through: try #require(first.addingDays(6)))
        return NotificationPlanner.requests(
            snapshot: store.content, days: week, preferences: preferences, now: now, timeZone: notificationUTC)
    }

    /// What `dev`'s planner read: the task rows and days of a fresh rebuild of the vault, and the
    /// published model's goals.
    @MainActor private struct LegacyVault {
        let model: VaultReadModel
        let tasks: [TaskRow]
        let days: [DaySummary]

        init(_ context: TaskTestContext) throws {
            let index = try VaultIndex()
            try index.rebuild(vaultRoot: context.root)
            let snapshot = try index.snapshot()
            model = context.store.content
            tasks = TaskRow.legacy(snapshot: snapshot)
            days = DaySummary.build(snapshot: snapshot)
        }
    }

    private func legacyPlan(
        _ vault: LegacyVault, now: Date, preferences: NotificationPreferences
    ) -> [NotificationRequest] {
        LegacyNotificationPlanner.requests(
            snapshot: vault.model, tasks: vault.tasks, days: vault.days, preferences: preferences, now: now,
            timeZone: notificationUTC)
    }

    /// Thirteen day-file cases around September 2026, with one task, in a vault of their own.
    static func writeDayEdgeCases(_ root: URL) throws {
        let files = [
            ".app/vault.json": "{ \"formatVersion\": 1 }\n",
            "people/Ada Test.md": "---\ntype: person\nname: Ada Test\n---\n",
            "journal/2026-09-02.md": "## Journal\n### Yalnız başlık\n",
            "journal/2026-09-03.md": "## Tasks\n- [ ] yalnız görev 📅 2026-09-03\n",
            "journal/2026-09-04.md": "---\ntype: journal\ngoals:\n  su: 3\n---\n",
            "journal/2026-09-05.md": "",
            "journal/2026-09-06.md": "## Notlar\nBaşka bölümde paragraf.\n",
            "journal/2026-09-07.md": "\u{FEFF}## Events\r\n- 08:00 CRLF [[Ada Test]]\r\n",
            "journal/2026-09-08.md": "## Journal\nYalnız [[Ada Test]] günlük.\n",
            "journal/2026-09-09.md": "## Events\n\n## Journal\n\n",
            "journal/2026-9-10.md": "## Events\n- 08:00 Tarih değil\n",
            "journal/arsiv/2026-09-11.md": "## Events\n- 08:00 Arşiv\n",
            "notes/Plan.md": "## Events\n- 09:00 [[2026-09-12]] planı\n\n## Journal\n[[2026-09-13]] notu.\n",
        ]
        for (path, text) in files { try IncrementalReadModelVault.write(root, path, text) }
        try Data([0x23, 0x23, 0x20, 0xFF, 0x0A]).write(to: root.appendingPathComponent("journal/2026-09-14.md"))
    }
}

/// The planner as `dev` had it, word for word but for its inputs: the read model's `tasks` and the
/// published day (`DaySummary.day(on:in:)`) in place of the queried week.
private enum LegacyNotificationPlanner {
    static func requests(
        snapshot: VaultReadModel, tasks: [TaskRow], days: [DaySummary], preferences: NotificationPreferences,
        now: Date, timeZone: TimeZone
    ) -> [NotificationRequest] {
        let today = LocalDay.today(at: now, timeZone: timeZone)
        var result: [NotificationRequest] = []
        for offset in 0..<7 {
            guard let day = today.addingDays(offset) else { continue }
            if preferences.tasksEnabled,
                let date = NotificationPlanner.fireDate(day, time: preferences.taskTime, timeZone: timeZone),
                date > now,
                let message = taskMessage(tasks, on: day, hideContent: preferences.hideContent)
            {
                result.append(
                    NotificationRequest(
                        id: "task-\(day)", date: date, title: message.title, body: message.body, destination: .tasks))
            }
            if preferences.goalsEnabled,
                let date = NotificationPlanner.fireDate(day, time: preferences.goalTime, timeZone: timeZone),
                date > now
            {
                let remaining = snapshot.goals.filter {
                    $0.period == .day
                        && !GoalProgress.compute(definition: $0, logs: snapshot.goalLogs[$0.key] ?? [], today: day)
                            .progress.isComplete
                }.sorted { $0.id < $1.id }.map(\.name)
                if !remaining.isEmpty {
                    let body =
                        preferences.hideContent
                        ? String(localized: "Bugün bekleyen hedefler var")
                        : String(localized: "Bugün bekleyen hedefler: \(remaining.joined(separator: ", "))")
                    result.append(
                        NotificationRequest(
                            id: "goals-\(day)", date: date, title: String(localized: "Günlük hedefler"),
                            body: body, destination: .goals))
                }
            }
            if preferences.journalEnabled,
                let date = NotificationPlanner.fireDate(day, time: preferences.journalTime, timeZone: timeZone),
                date > now
            {
                let summary = DaySummary.day(on: day, in: days)
                if summary.events.isEmpty && summary.journal.isEmpty {
                    result.append(
                        NotificationRequest(
                            id: "journal-\(day)", date: date, title: String(localized: "Gününden bir an"),
                            body: String(localized: "Bugünden bir an yazmak ister misin?"), destination: .journal))
                }
            }
        }
        return result.sorted { $0.date == $1.date ? $0.id < $1.id : $0.date < $1.date }
    }

    private static func taskMessage(
        _ tasks: [TaskRow], on day: CalendarDate, hideContent: Bool
    ) -> (title: String, body: String)? {
        let open = tasks.filter { !$0.isClosed }
        let due = open.filter { $0.due == day }.sorted { $0.id < $1.id }
        let overdue = open.filter { $0.due.map { $0 < day } ?? false }.count
        guard !due.isEmpty || overdue > 0 else { return nil }
        let title: String
        if due.isEmpty {
            title = String(localized: "Bugünkü görevler")
        } else if hideContent || due.count > 1 {
            title = String(localized: "\(due.count) görev bugün")
        } else {
            title = due[0].text.plainText
        }
        let body = overdue > 0 ? String(localized: "Önceki günlerden \(overdue) açık görev.") : ""
        return (title, body)
    }
}
