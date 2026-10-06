import Foundation
import GoalTracking
import Testing
import VaultFormat

@testable import Journal

struct NotificationPlannerTests {
    private let today = CalendarDate("2026-09-27")!
    private func plan(
        _ snapshot: VaultReadModel, preferences: NotificationPreferences = NotificationPreferences(),
        now: Date = notificationDate()
    ) -> [NotificationRequest] {
        NotificationPlanner.requests(snapshot: snapshot, preferences: preferences, now: now, timeZone: notificationUTC)
    }

    @Test func sampleDayHasSingleMorningSummaryDailyGoalsAndNoJournalReminder() throws {
        let requests = plan(try notificationSample())
        let morning = try #require(requests.first { $0.id == "task-2026-09-27" })
        #expect(morning.title == String(localized: "Bugünkü görevler"))
        #expect(morning.body == String(localized: "Önceki günlerden \(10) açık görev."))
        let goals = try #require(requests.first { $0.id == "goals-2026-09-27" })
        #expect(goals.body == String(localized: "Bugün bekleyen hedefler: \("Kitap, Su")"))
        #expect(!requests.contains { $0.id == "journal-2026-09-27" })
        let tomorrow = try #require(requests.first { $0.id == "task-2026-09-28" })
        #expect(tomorrow.title == "Toplantı Notları dosyasını güncelle")
        #expect(Set(requests.filter { $0.id.hasSuffix(today.description) }.map(\.destination)) == [.tasks, .goals])
    }

    @Test func multipleDueTasksUseCountAndExcludeClosedCancelledAndUndated() throws {
        var snapshot = try notificationSample()
        snapshot.tasks = try notificationTasks(
            "- [ ] first 📅 2026-09-27 ^a\n- [ ] second 📅 2026-09-27 ^b\n- [ ] third 📅 2026-09-27 ^c\n- [x] done 📅 2026-09-27 ^d\n- [-] cancelled 📅 2026-09-27 ^e\n- [ ] undated ^f\n"
        )
        let request = try #require(plan(snapshot).first { $0.id == "task-2026-09-27" })
        #expect(request.title == String(localized: "\(3) görev bugün"))
        #expect(request.body.isEmpty)
    }

    @Test func completedDailyGoalsSuppressOnlyTheirDayAndWeeklyYearlyGoalsNeverNotify() throws {
        var snapshot = try notificationSample()
        snapshot.goalLogs["kitap", default: []].append(GoalLog(day: today, value: .number(20)))
        snapshot.goalLogs["su", default: []].append(GoalLog(day: today, value: .number(8)))
        #expect(!plan(snapshot).contains { $0.id == "goals-2026-09-27" })
        #expect(plan(snapshot).contains { $0.id == "goals-2026-09-28" })
        snapshot.goals = [
            GoalDefinition(
                id: "goals/Annual.md", key: "annual", name: "Annual", period: .year, kind: .number, target: 24)!
        ]
        #expect(plan(snapshot).allSatisfy { $0.destination != .goals })
        snapshot.goals.append(
            GoalDefinition(id: "goals/Day.md", key: "daily", name: "Daily", period: .day, kind: .boolean, target: 1)!)
        snapshot.goalLogs["daily"] = [GoalLog(day: today, value: .boolean(true))]
        #expect(!plan(snapshot).contains { $0.id == "goals-2026-09-27" })
    }

    @Test func absentOrGoalOnlyDayGetsJournalReminderButEventsOrWritingSuppressIt() throws {
        var snapshot = VaultReadModel.empty
        snapshot.days = [
            DaySummary(id: "journal/\(today).md", date: today, events: [], journal: [], hasGoalRecords: true)
        ]
        #expect(plan(snapshot).contains { $0.id == "journal-2026-09-27" })
        let sample = try notificationSample().day(on: today)
        snapshot.days = [DaySummary(id: sample.id, date: today, events: sample.events, journal: [])]
        #expect(!plan(snapshot).contains { $0.id == "journal-2026-09-27" })
        snapshot.days = [DaySummary(id: sample.id, date: today, events: [], journal: sample.journal)]
        #expect(!plan(snapshot).contains { $0.id == "journal-2026-09-27" })
    }

    @Test func categoriesDisableIndependentlyAndInvalidTimesDoNotSchedule() throws {
        let snapshot = try notificationSample()
        var settings = NotificationPreferences()
        settings.tasksEnabled = false
        settings.goalsEnabled = false
        settings.journalEnabled = false
        #expect(plan(snapshot, preferences: settings).isEmpty)
        settings.goalsEnabled = true
        #expect(plan(snapshot, preferences: settings).allSatisfy { $0.destination == .goals })
        settings.goalTime.hour = 24
        #expect(plan(snapshot, preferences: settings).isEmpty)
        settings.goalsEnabled = false
        settings.journalEnabled = true
        #expect(plan(snapshot, preferences: settings).allSatisfy { $0.destination == .journal })
    }

    @Test func pastAndExactlyCurrentTimesAreSkippedWithDeterministicSevenDayBoundary() throws {
        let snapshot = try notificationSample()
        let requests = plan(snapshot, now: notificationDate(hour: 20))
        #expect(!requests.contains { $0.id == "task-2026-09-27" || $0.id == "goals-2026-09-27" })
        #expect(requests.allSatisfy { $0.date > notificationDate(hour: 20) })
        #expect(requests.contains { $0.id == "journal-2026-10-03" })
        #expect(!requests.contains { $0.id.hasSuffix("2026-10-04") })
        #expect(requests == plan(snapshot, now: notificationDate(hour: 20)))
        #expect(NotificationPlanner.identifiers(on: today).count == 21)
        #expect(Set(requests.map(\.id)).count == requests.count)
    }

    @Test func hideContentOmitsTaskTextAndGoalNames() throws {
        var snapshot = try notificationSample()
        snapshot.tasks = try notificationTasks(
            "- [ ] first secret 📅 2026-09-27 ^a\n- [ ] second secret 📅 2026-09-27 ^b\n"
        )
        var settings = NotificationPreferences()
        settings.hideContent = true
        let requests = plan(snapshot, preferences: settings)
        let morning = try #require(requests.first { $0.id == "task-2026-09-27" })
        #expect(morning.title == String(localized: "\(2) görev bugün"))
        #expect(!morning.title.contains("secret"))
        #expect(!morning.body.contains("secret"))
        let goals = try #require(requests.first { $0.id == "goals-2026-09-27" })
        #expect(goals.body == String(localized: "Bugün bekleyen hedefler var"))
        #expect(!goals.body.contains("Kitap"))
        #expect(!goals.body.contains("Su"))
        settings.hideContent = false
        let visible = plan(snapshot, preferences: settings)
        let visibleMorning = try #require(visible.first { $0.id == "task-2026-09-27" })
        #expect(visibleMorning.title == String(localized: "\(2) görev bugün"))
        let visibleGoals = try #require(visible.first { $0.id == "goals-2026-09-27" })
        #expect(visibleGoals.body == String(localized: "Bugün bekleyen hedefler: \("Kitap, Su")"))
    }

    @Test func hideContentReplacesSingleTaskTextWithCount() throws {
        var snapshot = try notificationSample()
        snapshot.tasks = try notificationTasks("- [ ] private errand 📅 2026-09-27 ^a\n")
        var settings = NotificationPreferences()
        settings.hideContent = true
        let hidden = try #require(plan(snapshot, preferences: settings).first { $0.id == "task-2026-09-27" })
        #expect(hidden.title == String(localized: "\(1) görev bugün"))
        #expect(!hidden.title.contains("private"))
        settings.hideContent = false
        let visible = try #require(plan(snapshot, preferences: settings).first { $0.id == "task-2026-09-27" })
        #expect(visible.title == "private errand")
    }

    @Test func daylightSavingAndCustomTimesKeepLocalCalendarDates() throws {
        let zone = try #require(TimeZone(identifier: "America/New_York"))
        let now = notificationDate("2026-03-07", hour: 0, zone: zone)
        var settings = NotificationPreferences()
        settings.tasksEnabled = false
        settings.goalsEnabled = false
        settings.journalTime = NotificationTime(hour: 21, minute: 15)
        let requests = NotificationPlanner.requests(snapshot: .empty, preferences: settings, now: now, timeZone: zone)
        #expect(requests.count == 7)
        #expect(requests[1].date.timeIntervalSince(requests[0].date) == Double(23 * 3600))
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = zone
        #expect(
            requests.allSatisfy {
                calendar.component(.hour, from: $0.date) == 21 && calendar.component(.minute, from: $0.date) == 15
            })
        #expect(requests.first?.id == "journal-2026-03-07" && requests.last?.id == "journal-2026-03-13")
    }
}
