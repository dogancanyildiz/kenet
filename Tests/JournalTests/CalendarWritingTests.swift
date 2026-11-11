import EntityRecognition
import EventKit
import Foundation
import Testing
import VaultFormat

@testable import Journal

@MainActor struct CalendarWritingTests {
    private let day = CalendarDate("2026-10-04")!
    private let utc = TimeZone(secondsFromGMT: 0)!

    private func service(_ source: InMemoryCalendarSource) -> CalendarService {
        CalendarService(source: source, defaults: UserDefaults(suiteName: "CalendarWritingTests-\(UUID())")!)
    }

    private func at(_ hour: Int, on date: CalendarDate? = nil) -> Date {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = .current
        return calendar.date(
            bySettingHour: hour, minute: 0, second: 0, of: LocalDay.instant(for: date ?? day))!
    }

    @Test func addEditAndDeleteReachTheDay() async throws {
        let source = InMemoryCalendarSource()
        let calendar = service(source)
        await calendar.load(day)
        var draft = CalendarEventDraft(
            title: "  Ders  ", start: at(10), end: at(11), isAllDay: false, recurrence: .none, calendarID: "work")
        #expect(await calendar.save(draft))
        let added = try #require(calendar.events(on: day).first)
        #expect(added.title == "Ders")
        #expect(added.calendarTitle == "İş")
        #expect(added.isEditable)

        draft = CalendarEventDraft(event: added)
        draft.title = "Toplantı"
        draft.end = at(12)
        #expect(await calendar.save(draft, editing: added))
        #expect(calendar.events(on: day).map(\.title) == ["Toplantı"])
        #expect(calendar.events(on: day).first?.end == at(12))

        let edited = try #require(calendar.events(on: day).first)
        #expect(await calendar.delete(edited))
        #expect(calendar.events(on: day).isEmpty)
        #expect(calendar.writeErrorText == nil)
    }

    @Test func emptyTitleIsNotWrittenAndEndNeverPrecedesStart() async {
        let source = InMemoryCalendarSource()
        let calendar = service(source)
        let blank = CalendarEventDraft(
            title: "   ", start: at(10), end: at(11), isAllDay: false, recurrence: .none, calendarID: nil)
        #expect(!(await calendar.save(blank)))
        #expect(source.stored.isEmpty)
        let backwards = CalendarEventDraft(
            title: "Ders", start: at(10), end: at(9), isAllDay: false, recurrence: .none, calendarID: nil)
        #expect(backwards.normalized().end == at(10))
    }

    @Test func newEventGoesToTheDefaultCalendar() async throws {
        let source = InMemoryCalendarSource()
        let calendar = service(source)
        calendar.defaultCalendarID = "work"
        let draft = CalendarEventDraft(
            title: "Ders", start: at(10), end: at(11), isAllDay: false, recurrence: .none, calendarID: nil)
        #expect(await calendar.save(draft))
        #expect(source.stored.first?.calendarID == "work")
        let calendars = await calendar.writableCalendars()
        #expect(await calendar.resolvedDefaultCalendarID(among: calendars) == "work")
        calendar.defaultCalendarID = "gone"
        #expect(await calendar.resolvedDefaultCalendarID(among: calendars) == "home")
    }

    @Test func defaultCalendarPersistsAsDevicePreference() {
        let defaults = UserDefaults(suiteName: "CalendarWritingTests-\(UUID())")!
        let first = CalendarService(source: InMemoryCalendarSource(), defaults: defaults)
        first.defaultCalendarID = "work"
        let second = CalendarService(source: InMemoryCalendarSource(), defaults: defaults)
        #expect(second.defaultCalendarID == "work")
    }

    @Test func writesNeedReadAccessAndFailuresAreShown() async {
        let denied = InMemoryCalendarSource(authorization: .denied)
        let calendar = service(denied)
        let draft = CalendarEventDraft(
            title: "Ders", start: at(10), end: at(11), isAllDay: false, recurrence: .none, calendarID: nil)
        #expect(!(await calendar.save(draft)))
        #expect(denied.stored.isEmpty)

        let empty = InMemoryCalendarSource(calendars: [])
        let failing = service(empty)
        #expect(!(await failing.save(draft)))
        #expect(failing.writeErrorText != nil)
        failing.clearWriteError()
        #expect(failing.writeErrorText == nil)
    }

    @Test func readOnlySourceRefusesWrites() async throws {
        final class ReadOnly: CalendarEventSource {
            var authorization = CalendarAuthorization.fullAccess
            var onChange: (@MainActor @Sendable () -> Void)?
            func requestFullAccess() async throws -> Bool { true }
            func events(from start: Date, to end: Date) async throws -> [CalendarEvent] { [] }
        }
        let calendar = CalendarService(source: ReadOnly())
        let draft = CalendarEventDraft(
            title: "Ders", start: at(10), end: at(11), isAllDay: false, recurrence: .none, calendarID: nil)
        #expect(!(await calendar.save(draft)))
        #expect(calendar.writeErrorText != nil)
        #expect(await calendar.writableCalendars().isEmpty)
    }

    @Test func weeklyEventRepeatsAndSpanChoicesFollowTheRule() async throws {
        let source = InMemoryCalendarSource()
        let calendar = service(source)
        let draft = CalendarEventDraft(
            title: "Ders", start: at(10), end: at(11), isAllDay: false, recurrence: .weekly, calendarID: nil)
        #expect(await calendar.save(draft))
        let nextWeek = CalendarDate("2026-10-11")!
        await calendar.load(nextWeek)
        let occurrence = try #require(calendar.events(on: nextWeek).first)
        #expect(occurrence.recurrence == .weekly)
        #expect(occurrence.start == at(10, on: nextWeek))

        var same = CalendarEventDraft(event: occurrence)
        same.title = "Ders 2"
        #expect(CalendarEventDraft.spans(saving: same, over: occurrence) == [.thisEvent, .futureEvents])
        var changed = same
        changed.recurrence = .monthly
        #expect(CalendarEventDraft.spans(saving: changed, over: occurrence) == [.futureEvents])
        var single = occurrence
        single.recurrence = .none
        #expect(CalendarEventDraft.spans(saving: CalendarEventDraft(event: single), over: single) == [.thisEvent])
    }

    @Test func eventKitRuleMapping() {
        #expect(EventKitRecurrence.recurrence(of: nil) == .none)
        for value in [CalendarRecurrence.daily, .weekly, .monthly, .yearly] {
            #expect(EventKitRecurrence.recurrence(of: EventKitRecurrence.rules(for: value)) == value)
        }
        #expect(EventKitRecurrence.rules(for: .none) == nil)
        #expect(EventKitRecurrence.rules(for: .custom) == nil)
        let everyOther = EKRecurrenceRule(recurrenceWith: .weekly, interval: 2, end: nil)
        #expect(EventKitRecurrence.recurrence(of: [everyOther]) == .custom)
        let weekdays = EKRecurrenceRule(
            recurrenceWith: .weekly, interval: 1, daysOfTheWeek: [EKRecurrenceDayOfWeek(.monday)],
            daysOfTheMonth: nil, monthsOfTheYear: nil, weeksOfTheYear: nil, daysOfTheYear: nil,
            setPositions: nil, end: nil)
        #expect(EventKitRecurrence.recurrence(of: [weekdays]) == .custom)
    }

    @Test func newDraftStartsAtTheNextHourTodayAndAtNineOtherwise() {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = utc
        let now = calendar.date(
            bySettingHour: 14, minute: 20, second: 0, of: LocalDay.instant(for: day, timeZone: utc))!
        let today = CalendarEventDraft.new(on: day, now: now, calendarID: "home", timeZone: utc)
        #expect(calendar.component(.hour, from: today.start) == 15)
        #expect(today.end.timeIntervalSince(today.start) == 3600)
        #expect(today.calendarID == "home")
        let other = CalendarEventDraft.new(on: CalendarDate("2026-10-09")!, now: now, calendarID: nil, timeZone: utc)
        #expect(calendar.component(.hour, from: other.start) == 9)
    }

    @Test func personMatchesTitleWordsAndAttendeesByNameOrAlias() {
        func event(_ title: String, attendees: [Attendee] = []) -> CalendarEvent {
            CalendarEvent(
                id: title, title: title, start: at(10), end: at(11), isAllDay: false,
                color: CalendarEventColor(red: 0, green: 0, blue: 0, alpha: 1), attendees: attendees)
        }
        let names = ["Deniz Arıkan", "Den"]
        #expect(CalendarPersonMatch.matches(event("Deniz Arıkan ile kahve"), names: names))
        #expect(CalendarPersonMatch.matches(event("DENİZ ARIKAN'ın sunumu"), names: names))
        #expect(CalendarPersonMatch.matches(event("Den ile tenis"), names: names))
        #expect(!CalendarPersonMatch.matches(event("Denizli gezisi"), names: names))
        #expect(!CalendarPersonMatch.matches(event("Deniz kenarı"), names: names))
        #expect(CalendarPersonMatch.matches(event("Proje", attendees: [Attendee(name: "deniz arıkan")]), names: names))
        #expect(
            !CalendarPersonMatch.matches(
                event("Proje", attendees: [Attendee(name: "Deniz Arıkan", isCurrentUser: true)]), names: names))
        #expect(!CalendarPersonMatch.matches(event("Deniz Arıkan"), names: []))
    }

    @Test func birthdayIsAddedYearlyAndFoundOnThePersonPage() async throws {
        let source = InMemoryCalendarSource()
        let calendar = service(source)
        let names = ["Deniz Arıkan"]
        let now = at(8)
        let before = try #require(await calendar.personEvents(names: names, from: now))
        #expect(before.birthday == nil)
        #expect(before.upcoming.isEmpty)

        let birth = Calendar(identifier: .gregorian).date(
            byAdding: .year, value: -30, to: at(12, on: CalendarDate("2026-12-01")!))!
        let draft = CalendarEventDraft.birthday(
            name: "Deniz Arıkan", on: birth, calendarID: nil, locale: Locale(identifier: "tr"))
        #expect(draft.title == "Deniz Arıkan doğum günü")
        #expect(draft.isAllDay)
        #expect(draft.recurrence == .yearly)
        #expect(await calendar.save(draft))
        _ = await calendar.save(
            CalendarEventDraft(
                title: "Deniz Arıkan ile kahve", start: at(15), end: at(16), isAllDay: false, recurrence: .none,
                calendarID: nil))
        _ = await calendar.save(
            CalendarEventDraft(
                title: "Ece Yalın ile kahve", start: at(15), end: at(16), isAllDay: false, recurrence: .none,
                calendarID: nil))

        let after = try #require(await calendar.personEvents(names: names, from: now))
        #expect(after.upcoming.map(\.title) == ["Deniz Arıkan ile kahve", "Deniz Arıkan doğum günü"])
        let found = try #require(after.birthday)
        #expect(LocalDay.today(at: found.start) == CalendarDate("2026-12-01"))
        #expect(CalendarBirthday.isBirthday(found))
    }

    @Test func birthdayRecognitionNeedsYearlyAllDayOrTheBirthdaysCalendar() {
        func event(_ title: String, allDay: Bool, recurrence: CalendarRecurrence, birthdays: Bool = false)
            -> CalendarEvent
        {
            CalendarEvent(
                id: title, title: title, start: at(0), end: at(0), isAllDay: allDay,
                color: CalendarEventColor(red: 0, green: 0, blue: 0, alpha: 1), recurrence: recurrence,
                isFromBirthdayCalendar: birthdays)
        }
        #expect(CalendarBirthday.isBirthday(event("Ece doğum günü", allDay: true, recurrence: .yearly)))
        #expect(CalendarBirthday.isBirthday(event("Ece's Birthday", allDay: true, recurrence: .yearly)))
        #expect(!CalendarBirthday.isBirthday(event("Ece doğum günü", allDay: false, recurrence: .yearly)))
        #expect(!CalendarBirthday.isBirthday(event("Ece doğum günü", allDay: true, recurrence: .none)))
        #expect(CalendarBirthday.isBirthday(event("Ece", allDay: true, recurrence: .none, birthdays: true)))
        #expect(!CalendarBirthday.isBirthday(event("Ece ile yemek", allDay: true, recurrence: .yearly)))
    }

    @Test func personEventsNeedReadAccessAndCapAtFive() async {
        let denied = service(InMemoryCalendarSource(authorization: .denied))
        #expect(await denied.personEvents(names: ["Deniz"], from: at(8)) == nil)
        let source = InMemoryCalendarSource()
        let calendar = service(source)
        _ = await calendar.save(
            CalendarEventDraft(
                title: "Deniz ders", start: at(10), end: at(11), isAllDay: false, recurrence: .daily,
                calendarID: nil))
        let result = await calendar.personEvents(names: ["Deniz"], from: at(8))
        #expect(result?.upcoming.count == 5)
        #expect(result?.birthday == nil)
    }
}
