import Foundation
import Testing
import VaultFormat

@testable import Journal

@MainActor struct CalendarServiceTests {
    private let day = CalendarDate("2026-10-04")!
    private let utc = TimeZone(secondsFromGMT: 0)!

    @Test func allDayFirstThenStartTitleAndIdentifier() async {
        let source = FakeCalendarSource()
        source.values = [
            event("late", hour: 15), event("b", hour: 9, title: "Same"),
            event("all", hour: 12, allDay: true), event("a", hour: 9, title: "Same"),
            event("early", hour: 8),
        ]
        let service = CalendarService(source: source)
        await service.load(day)
        #expect(service.events(on: day).map(\.id) == ["all", "early", "a", "b", "late"])
        #expect(service.events(on: day).first?.color == source.values[2].color)
        #expect(service.showsSection(on: day))
    }

    @Test func localDayOverlapAndExclusiveEnd() async {
        let source = FakeCalendarSource()
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = utc
        let midnight = calendar.startOfDay(for: LocalDay.instant(for: day, timeZone: utc))
        source.values = [
            event("previous", start: midnight.addingTimeInterval(-7200), end: midnight),
            event("overlap", start: midnight.addingTimeInterval(-7200), end: midnight.addingTimeInterval(3600)),
            event("next", start: midnight.addingTimeInterval(86400), end: midnight.addingTimeInterval(90000)),
            event("instant", start: midnight, end: midnight),
        ]
        let service = CalendarService(source: source)
        await service.load(day, timeZone: utc)
        #expect(service.events(on: day).map(\.id) == ["overlap", "instant"])
        #expect(source.ranges.first?.start == midnight)
        #expect(source.ranges.first?.duration == 86400)
    }

    @Test func daylightSavingUsesCalendarDayInsteadOf24Hours() async throws {
        let source = FakeCalendarSource()
        let service = CalendarService(source: source)
        let zone = try #require(TimeZone(identifier: "America/New_York"))
        await service.load(CalendarDate("2026-03-08")!, timeZone: zone)
        #expect(source.ranges.last?.duration == Double(23 * 3600))
        await service.load(CalendarDate("2026-11-01")!, timeZone: zone)
        #expect(source.ranges.last?.duration == Double(25 * 3600))
    }

    @Test func authorizationControlsPromptVisibilityAndQueries() async {
        for status in CalendarAuthorization.allCases {
            let source = FakeCalendarSource()
            source.authorization = status
            let service = CalendarService(source: source)
            await service.load(day)
            #expect(service.authorization == status)
            #expect(service.showsSection(on: day) == status.canRequest)
            #expect(source.requests == 0)
            #expect(source.ranges.count == (status.canRead ? 1 : 0))
        }
    }

    @Test func permissionIsRequestedOnlyByExplicitAction() async {
        let source = FakeCalendarSource()
        source.authorization = .notDetermined
        source.values = [event("visible", hour: 10)]
        let service = CalendarService(source: source)
        await service.load(day)
        #expect(source.requests == 0)
        await service.requestAccess()
        #expect(source.requests == 1)
        #expect(service.authorization == .fullAccess)
        #expect(service.events(on: day).count == 1)
        #expect(!service.isRequesting)
        await service.requestAccess()
        #expect(source.requests == 1)
    }

    @Test func denialAndForegroundRevocationClearEvents() async {
        let source = FakeCalendarSource()
        source.values = [event("visible", hour: 10)]
        let service = CalendarService(source: source)
        await service.load(day)
        source.authorization = .denied
        await service.refresh()
        #expect(!service.showsSection(on: day))
        #expect(service.events(on: day).isEmpty)
        await service.requestAccess()
        #expect(source.requests == 0)
        source.authorization = .notDetermined
        source.requestResult = .denied
        await service.refresh()
        await service.requestAccess()
        #expect(service.authorization == .denied)
        #expect(!service.showsSection(on: day))
    }

    @Test func independentDaysAndSourceChangeRefresh() async throws {
        let source = FakeCalendarSource()
        let tomorrow = CalendarDate("2026-10-05")!
        source.values = [
            event("today", hour: 10),
            event(
                "tomorrow", start: LocalDay.instant(for: tomorrow),
                end: LocalDay.instant(for: tomorrow).addingTimeInterval(3600)),
        ]
        let service = CalendarService(source: source)
        await service.load(day)
        await service.load(tomorrow)
        #expect(service.events(on: day).map(\.id) == ["today"])
        #expect(service.events(on: tomorrow).map(\.id) == ["tomorrow"])
        source.values = []
        source.onChange?()
        for _ in 0..<100 {
            if service.events(on: day).isEmpty && service.events(on: tomorrow).isEmpty { break }
            try await Task.sleep(for: .milliseconds(10))
        }
        #expect(service.events(on: day).isEmpty)
        #expect(service.events(on: tomorrow).isEmpty)
    }

    @Test func lateResultCannotRestoreRevokedEvents() async throws {
        let source = FakeCalendarSource()
        source.values = [event("private", hour: 10)]
        source.pauseRead = true
        let service = CalendarService(source: source)
        let load = Task { await service.load(day) }
        for _ in 0..<100 {
            if source.pendingRead != nil { break }
            await Task.yield()
        }
        let pending = try #require(source.pendingRead)
        source.authorization = .denied
        await service.refresh()
        pending.resume(returning: source.values)
        await load.value
        #expect(service.authorization == .denied)
        #expect(service.events(on: day).isEmpty)
        #expect(!service.showsSection(on: day))
    }

    @Test func errorsAreVisibleAndRetryRecovers() async {
        let source = FakeCalendarSource()
        source.failRead = true
        let service = CalendarService(source: source)
        await service.load(day)
        #expect(service.errorText != nil)
        #expect(service.showsSection(on: day))
        source.failRead = false
        await service.load(day)
        #expect(service.errorText == nil)
        #expect(!service.showsSection(on: day))
        source.authorization = .notDetermined
        source.failRequest = true
        await service.refresh()
        await service.requestAccess()
        #expect(service.errorText != nil)
        #expect(!service.isRequesting)
        #expect(service.authorization == .notDetermined)
    }

    private func event(_ id: String, hour: Int, title: String = "Event", allDay: Bool = false) -> CalendarEvent {
        let calendar = Calendar(identifier: .gregorian)
        let start = calendar.date(bySettingHour: hour, minute: 0, second: 0, of: LocalDay.instant(for: day))!
        return event(id, start: start, end: start.addingTimeInterval(3600), title: title, allDay: allDay)
    }
    private func event(_ id: String, start: Date, end: Date, title: String = "Event", allDay: Bool = false)
        -> CalendarEvent
    {
        CalendarEvent(
            id: id, title: title, start: start, end: end, isAllDay: allDay,
            color: CalendarEventColor(red: 0.2, green: 0.4, blue: 0.8, alpha: 1))
    }
}

@MainActor private final class FakeCalendarSource: CalendarEventSource {
    enum Failure: Error { case unavailable }
    var authorization = CalendarAuthorization.fullAccess
    var onChange: (@MainActor @Sendable () -> Void)?
    var values: [CalendarEvent] = []
    var ranges: [DateInterval] = []
    var requests = 0
    var requestResult = CalendarAuthorization.fullAccess
    var pauseRead = false
    var pendingRead: CheckedContinuation<[CalendarEvent], Never>?
    var failRead = false
    var failRequest = false
    func requestFullAccess() async throws -> Bool {
        requests += 1
        if failRequest { throw Failure.unavailable }
        authorization = requestResult
        return authorization.canRead
    }
    func events(from start: Date, to end: Date) async throws -> [CalendarEvent] {
        ranges.append(DateInterval(start: start, end: end))
        if failRead { throw Failure.unavailable }
        if pauseRead { return await withCheckedContinuation { pendingRead = $0 } }
        return values
    }
}
