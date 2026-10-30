import Foundation
import Testing
import VaultFormat

@testable import Journal

@MainActor final class LockScreenCalendarSource: CalendarEventSource {
    var authorization = CalendarAuthorization.fullAccess
    var onChange: (@MainActor @Sendable () -> Void)?
    var values: [CalendarEvent] = []
    func requestFullAccess() async throws -> Bool { authorization.canRead }
    func events(from start: Date, to end: Date) async throws -> [CalendarEvent] {
        values.filter { $0.start < end && $0.end > start }
    }
}

@MainActor @Suite("Lock screen widget")
struct LockScreenWidgetTests {
    private let now = WidgetSnapshotTests.noon

    private func source() -> LockScreenCalendarSource {
        let source = LockScreenCalendarSource()
        source.values = (0..<7).reversed().map { index in
            CalendarEvent(
                id: "event-\(index)", title: "Etkinlik \(index)",
                start: now.addingTimeInterval(Double(index + 1) * 600),
                end: now.addingTimeInterval(Double(index + 2) * 600), isAllDay: false,
                color: .init(red: 0, green: 0, blue: 0, alpha: 1))
        }
        return source
    }

    @Test func writerLimitsSortsAndRedactsEvents() async throws {
        let harness = try WidgetSnapshotTests.Harness(calendarSource: source())
        defer { harness.context.clean() }
        await harness.start()
        let snapshot = try #require(harness.snapshot)
        let events = try #require(snapshot.days[0].events)
        #expect(events.count == 5)
        #expect(events.map(\.start) == (1...5).map { now.addingTimeInterval(Double($0) * 600) })
        #expect(events.allSatisfy { $0.title.isEmpty })
        #expect(snapshot.hideContent == true)
        #expect(snapshot.days[0].openTaskCount == 0)
        #expect(harness.timelines.reloads == [WidgetKinds.goalChain, WidgetKinds.lockScreen])
    }

    @Test func preferenceChangeRewritesTitlesAndUnchangedContentDoesNotWrite() async throws {
        var preferences = NotificationPreferences()
        preferences.hideContent = false
        let harness = try WidgetSnapshotTests.Harness(
            calendarSource: source(), hideContent: { preferences.hideContent })
        defer { harness.context.clean() }
        await harness.start()
        #expect(harness.snapshot?.hideContent == false)
        #expect(harness.snapshot?.days[0].events?.first?.title == "Etkinlik 0")
        let data = try Data(contentsOf: harness.file)
        harness.clock.now = now.addingTimeInterval(1)
        harness.writer.update()
        await harness.writer.settle()
        #expect(try Data(contentsOf: harness.file) == data)
        preferences.hideContent = true
        harness.writer.update()
        await harness.writer.settle()
        #expect(harness.snapshot?.hideContent == true)
        #expect(harness.snapshot?.days[0].events?.allSatisfy { $0.title.isEmpty } == true)
        #expect(harness.timelines.reloads.count == 2 * WidgetKinds.all.count)
    }

    @Test func deniedPermissionOmitsEventsAndLockedWriterLeavesBytesAlone() async throws {
        let source = source()
        let harness = try WidgetSnapshotTests.Harness(calendarSource: source)
        defer { harness.context.clean() }
        await harness.start()
        source.authorization = .denied
        harness.writer.update()
        await harness.writer.settle()
        #expect(harness.snapshot?.days.allSatisfy { $0.events == nil } == true)
        #expect(harness.snapshot?.days[0].openTaskCount == 0)
        let data = try Data(contentsOf: harness.file)
        harness.lock.isLocked = true
        source.authorization = .fullAccess
        harness.writer.update()
        await harness.writer.settle()
        #expect(try Data(contentsOf: harness.file) == data)
    }

    @Test func taskCountMatchesNotificationDueDayAndExcludesOverdueAndUndated() async throws {
        let harness = try WidgetSnapshotTests.Harness()
        defer { harness.context.clean() }
        await harness.start()
        let today = GraceDayVault.today
        #expect(await harness.context.store.addTask(on: today, text: "Bugünkü iş", due: today))
        #expect(await harness.context.store.addTask(on: today, text: "Gecikmiş iş", due: today.addingDays(-1)))
        #expect(await harness.context.store.addTask(on: today, text: "Tarihsiz iş", due: nil))
        #expect(await harness.context.store.addTask(on: today, text: "Yarınki iş", due: today.addingDays(1)))
        await harness.writer.settle()
        #expect(harness.snapshot?.days.map(\.openTaskCount) == [1, 1])
        let counts = try await harness.context.store.computeNotificationDays(from: today, through: today)
        #expect(harness.snapshot?.days[0].openTaskCount == counts.dueTasks.count)
    }

    @Test func legacySnapshotReadsWithoutAccessoryFields() throws {
        let json = """
            {"format":1,"writtenAt":"2026-09-20T12:00:00Z","vaultID":"test",            "days":[{"date":"2026-09-20","goals":[]}]}
            """
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let snapshot = try decoder.decode(WidgetSnapshot.self, from: Data(json.utf8))
        #expect(snapshot.hideContent == nil)
        #expect(snapshot.days[0].events == nil)
        #expect(snapshot.days[0].openTaskCount == nil)
    }

    @Test func eventEndsMidnightAndExpiryAreDeterministic() throws {
        let calendar = WidgetDay.deviceCalendar
        let midnight = try #require(WidgetDay.start(of: "2026-09-21", calendar: calendar))
        let expiry = try #require(calendar.date(byAdding: .day, value: 1, to: midnight))
        let firstEnd = now.addingTimeInterval(1200)
        let secondEnd = now.addingTimeInterval(1800)
        let tomorrowEnd = midnight.addingTimeInterval(3600)
        let snapshot = WidgetSnapshot(
            writtenAt: now, vaultID: "test",
            days: [
                .init(
                    date: "2026-09-20", goals: [],
                    events: [
                        .init(title: "A", start: now, end: firstEnd, isAllDay: false),
                        .init(title: "B", start: firstEnd, end: secondEnd, isAllDay: false),
                    ], openTaskCount: 3),
                .init(
                    date: "2026-09-21", goals: [],
                    events: [
                        .init(title: "C", start: midnight, end: tomorrowEnd, isAllDay: false)
                    ], openTaskCount: 2),
            ])
        let entries = snapshot.lockScreenTimeline(from: now, calendar: calendar)
        #expect(entries.map(\.date) == [now, firstEnd, secondEnd, midnight, tomorrowEnd, expiry])
        #expect(entries[3].day?.openTaskCount == 2)
        #expect(entries.last?.day == nil)
        #expect(snapshot.lockScreenTimeline(from: expiry, calendar: calendar).first?.day == nil)
        var locked = snapshot
        locked.lockedAfter = firstEnd
        let timeline = locked.lockScreenTimeline(from: now, calendar: calendar)
        #expect(timeline.map(\.date) == [now, firstEnd])
        #expect(timeline.last?.day == nil)
        #expect(locked.lockScreenTimeline(from: firstEnd, calendar: calendar).first?.day == nil)
    }

    @Test func emptyLegacyAndMissingSnapshotsUseLocalizedStates() {
        for layout in LockScreenLayout.allCases {
            let missing = LockScreenWidgetView(day: nil, date: now, hideContent: true, layout: layout)
            #expect(missing.emptyText == String(localized: "widget.lock.open"))
            let legacy = LockScreenWidgetView(
                day: .init(date: "2026-09-20", goals: []), date: now, hideContent: true, layout: layout)
            #expect(legacy.emptyText == String(localized: "widget.lock.open"))
            let empty = LockScreenWidgetView(
                day: .init(date: "2026-09-20", goals: [], openTaskCount: 0),
                date: now, hideContent: true, layout: layout)
            #expect(empty.emptyText == String(localized: "widget.lock.empty"))
            let tasksOnly = LockScreenWidgetView(
                day: .init(date: "2026-09-20", goals: [], openTaskCount: 3),
                date: now, hideContent: true, layout: layout)
            #expect(tasksOnly.emptyText == nil)
            #expect(tasksOnly.eventText == nil)
        }
    }

    @Test func optionalFieldsParticipateInContentComparison() {
        let original = WidgetSnapshot(
            writtenAt: now, vaultID: "test", days: [.init(date: "2026-09-20", goals: [], openTaskCount: 0)],
            hideContent: true)
        var changed = original
        changed.hideContent = false
        #expect(!original.hasSameContent(as: changed))
        changed = original
        changed.days[0].openTaskCount = 1
        #expect(!original.hasSameContent(as: changed))
        changed = original
        changed.days[0].events = []
        #expect(!original.hasSameContent(as: changed))
    }

    @Test func presentationHidesTitleEvenFromAnUnredactedSnapshot() {
        let day = WidgetSnapshot.Day(
            date: "2026-09-20", goals: [],
            events: [
                .init(title: "Private title", start: now, end: now.addingTimeInterval(60), isAllDay: false)
            ], openTaskCount: 3)
        let hidden = LockScreenWidgetView(day: day, date: now, hideContent: true, layout: .rectangular)
        let visible = LockScreenWidgetView(day: day, date: now, hideContent: false, layout: .rectangular)
        #expect(hidden.eventText?.contains("Private title") == false)
        #expect(visible.eventText?.contains("Private title") == true)
        #expect(hidden.taskText == String(format: String(localized: "widget.lock.tasks"), 3))
        let ended = LockScreenWidgetView(
            day: day, date: now.addingTimeInterval(60), hideContent: false, layout: .inline)
        #expect(ended.nextEvent == nil)
    }
}
