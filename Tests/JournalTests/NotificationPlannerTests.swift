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

    @Test func disabledPeopleReminderMatchesThePlanWithoutPeople() throws {
        let snapshot = try notificationSample()
        let now = notificationDate()
        let baseline = plan(snapshot, now: now)
        var settings = NotificationPreferences()
        settings.peopleEnabled = false
        let people = [
            cadencePerson("people/Lale Mor.md", name: "Lale", last: "2026-08-01", days: 7),
            cadencePerson("people/Ada Kaya.md", name: "Ada", last: "2026-08-01", days: 14),
        ]
        let withPeople = NotificationPlanner.requests(
            snapshot: snapshot, preferences: settings, now: now, timeZone: notificationUTC, people: people,
            lastNotified: ["people/Lale Mor.md": CalendarDate("2026-09-01")!])
        #expect(withPeople == baseline)
        #expect(withPeople.allSatisfy { !$0.id.hasPrefix("people-") })
        #expect(NotificationPlanner.identifiers(on: today).count == 21)
    }

    @Test func enabledPeopleReminderKeepsTheOtherRequestsAndCapsTheDay() throws {
        let snapshot = try notificationSample()
        let now = notificationDate()
        let baseline = plan(snapshot, now: now)
        var settings = NotificationPreferences()
        settings.peopleEnabled = true
        let people = [
            cadencePerson("people/d.md", name: "Cem", last: "2026-09-19", days: 7),
            cadencePerson("people/a.md", name: "Deniz", last: "2026-08-01", days: 7),
            cadencePerson("people/b.md", name: "Ada", last: "2026-09-01", days: 7),
            cadencePerson("people/c.md", name: "Bora", last: "2026-09-10", days: 7),
        ]
        let requests = NotificationPlanner.requests(
            snapshot: snapshot, preferences: settings, now: now, timeZone: notificationUTC, people: people)
        #expect(requests.filter { $0.destination != .people } == baseline)
        let todayPeople = requests.filter { $0.id == "people-2026-09-27" }
        #expect(todayPeople.count == 1)
        let notice = try #require(todayPeople.first)
        #expect(notice.destination == .people)
        #expect(notice.title == String(localized: "Görüşme zamanı"))
        #expect(notice.date == notificationDate(hour: 10))
        #expect(
            notice.body
                == String(localized: "\("Deniz"), \("Ada"), \("Bora") ve \(1) kişi daha"))
        #expect(!notice.body.contains("Cem"))
        #expect(requests.contains { $0.id == "people-2026-09-30" })
        #expect(requests.contains { $0.id == "people-2026-10-03" })
        #expect(!requests.contains { $0.id == "people-2026-09-28" || $0.id == "people-2026-09-29" })
        #expect(!requests.contains { $0.id == "people-2026-10-01" || $0.id == "people-2026-10-02" })
        #expect(!requests.contains { $0.id == "people-2026-10-04" })
    }

    @Test func hiddenPeopleReminderOmitsNames() throws {
        var settings = NotificationPreferences()
        settings.peopleEnabled = true
        settings.tasksEnabled = false
        settings.goalsEnabled = false
        settings.journalEnabled = false
        settings.hideContent = true
        let people = [
            cadencePerson("people/a.md", name: "Deniz", last: "2026-08-01", days: 7),
            cadencePerson("people/b.md", name: "Ada", last: "2026-09-01", days: 7),
            cadencePerson("people/c.md", name: "Bora", last: "2026-09-10", days: 7),
        ]
        let notice = try #require(
            NotificationPlanner.requests(
                snapshot: .empty, preferences: settings, now: notificationDate(), timeZone: notificationUTC,
                people: people
            ).first { $0.id == "people-2026-09-27" })
        #expect(notice.body == String(localized: "Görüşme zamanı gelen \(3) kişi var"))
        #expect(notice.title == String(localized: "Görüşme zamanı"))
        for name in ["Deniz", "Ada", "Bora"] {
            #expect(!notice.title.contains(name))
            #expect(!notice.body.contains(name))
        }
    }

    @Test func peopleDayFollowsTheInjectedTimeZoneAndSkipsAPassedHour() throws {
        var settings = NotificationPreferences()
        settings.tasksEnabled = false
        settings.goalsEnabled = false
        settings.journalEnabled = false
        settings.peopleEnabled = true
        let person = cadencePerson("people/Lale Mor.md", name: "Lale", last: "2026-10-01", days: 10)
        let now = notificationDate("2026-10-10", hour: 22)
        let ahead = try #require(TimeZone(identifier: "Pacific/Kiritimati"))
        let inKiritimati = NotificationPlanner.requests(
            snapshot: .empty, preferences: settings, now: now, timeZone: ahead, people: [person])
        let inUTC = NotificationPlanner.requests(
            snapshot: .empty, preferences: settings, now: now, timeZone: notificationUTC, people: [person])
        #expect(inKiritimati.first { $0.id.hasPrefix("people-") }?.id == "people-2026-10-12")
        #expect(inUTC.first { $0.id.hasPrefix("people-") }?.id == "people-2026-10-11")
        let onTheHour = notificationDate("2026-10-11", hour: 10)
        let skipped = NotificationPlanner.requests(
            snapshot: .empty, preferences: settings, now: onTheHour, timeZone: notificationUTC, people: [person])
        #expect(!skipped.contains { $0.id == "people-2026-10-11" })
        #expect(skipped.contains { $0.id == "people-2026-10-12" })
    }

    @Test func invalidPeopleTimeSchedulesNoPeopleReminder() throws {
        var settings = NotificationPreferences()
        settings.peopleEnabled = true
        settings.peopleTime.hour = 24
        let person = cadencePerson("people/Lale Mor.md", name: "Lale", last: "2026-08-01", days: 7)
        let requests = NotificationPlanner.requests(
            snapshot: try notificationSample(), preferences: settings, now: notificationDate(),
            timeZone: notificationUTC, people: [person])
        #expect(requests.allSatisfy { $0.destination != .people })
        #expect(!requests.isEmpty)
    }
}
