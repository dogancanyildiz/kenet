import EntityRecognition
import EventKit
import Foundation
import Testing
import VaultFormat

@testable import Kenet

@MainActor struct CalendarWritingTests {
    private let day = CalendarDate("2026-10-04")!
    private let utc = TimeZone(secondsFromGMT: 0)!
    private let color = CalendarEventColor(red: 0, green: 0, blue: 0, alpha: 1)

    private func service(_ source: InMemoryCalendarSource) -> CalendarService {
        CalendarService(source: source, defaults: UserDefaults(suiteName: "CalendarWritingTests-\(UUID())")!)
    }

    private func at(_ hour: Int, on date: CalendarDate? = nil) -> Date {
        Calendar(identifier: .gregorian).date(
            bySettingHour: hour, minute: 0, second: 0, of: LocalDay.instant(for: date ?? day))!
    }

    private func draft(_ title: String, _ hour: Int = 10, recurrence: CalendarRecurrence = .none) -> CalendarEventDraft
    {
        CalendarEventDraft(
            title: title, start: at(hour), end: at(hour + 1), isAllDay: false, recurrence: recurrence, calendarID: nil)
    }

    private func titles(_ calendar: CalendarService, on date: CalendarDate) async -> [String] {
        await calendar.load(date)
        return calendar.events(on: date).map(\.title)
    }

    // MARK: - Single events

    @Test func addEditAndDeleteReachTheDay() async throws {
        let source = InMemoryCalendarSource()
        let calendar = service(source)
        await calendar.load(day)
        var new = draft("  Ders  ")
        new.calendarID = "work"
        #expect(await calendar.save(new))
        let added = try #require(calendar.events(on: day).first)
        #expect(added.title == "Ders")
        #expect(added.calendarTitle == "İş")
        #expect(added.isEditable)

        var edit = CalendarEventDraft(event: added)
        edit.title = "Toplantı"
        edit.end = at(12)
        #expect(await calendar.save(edit, editing: added))
        #expect(calendar.events(on: day).map(\.title) == ["Toplantı"])
        #expect(calendar.events(on: day).first?.end == at(12))

        let edited = try #require(calendar.events(on: day).first)
        #expect(await calendar.delete(edited))
        #expect(calendar.events(on: day).isEmpty)
        #expect(calendar.writeError == nil)
    }

    /// The source's echo of our own write does not refresh at once; a change inside the window is
    /// never dropped either: one refresh follows when the window closes, however many came.
    @Test func changesInsideTheWriteWindowRefreshOnceAfterIt() async {
        let source = InMemoryCalendarSource()
        let calendar = CalendarService(
            source: source, defaults: UserDefaults(suiteName: "CalendarWritingTests-\(UUID())")!, echoWindow: 0.3)
        await calendar.load(day)
        let before = calendar.changeCount
        #expect(await calendar.save(draft("Ders")))
        #expect(calendar.changeCount == before + 1)
        // Another device's change lands inside the window, twice.
        source.onChange?()
        source.onChange?()
        for _ in 0..<20 { await Task.yield() }
        #expect(calendar.changeCount == before + 1)
        let settled = await waitUntil(timeout: .seconds(3)) { calendar.changeCount == before + 2 }
        #expect(settled)
        try? await Task.sleep(for: .seconds(0.5))
        #expect(calendar.changeCount == before + 2)
        // Outside the window a change refreshes at once.
        source.onChange?()
        let direct = await waitUntil(timeout: .seconds(1)) { calendar.changeCount == before + 3 }
        #expect(direct)
    }

    /// EventKit ends an all-day event at 23:59:59 of its last day; a title-only edit writes the
    /// title only and leaves the dates as the calendar has them.
    @Test func allDayEditInEventKitFormWritesOnlyTheTitle() {
        let start = Calendar.current.startOfDay(for: at(10))
        let end = Calendar.current.date(byAdding: .day, value: 2, to: start)!.addingTimeInterval(-1)
        let original = CalendarEvent(
            id: "a", title: "Kamp", start: start, end: end, isAllDay: true, color: color, eventIdentifier: "a",
            calendarID: "home", isEditable: true)
        var draft = CalendarEventDraft(event: original)
        #expect(CalendarWritePlan.changes(draft: draft.normalized(), original: original).isEmpty)
        draft.title = "Yaz kampı"
        #expect(
            CalendarWritePlan.changes(draft: draft.normalized(), original: original)
                == CalendarWritePlan.Changes(title: "Yaz kampı"))
    }

    /// 29 February is written as February's last day: the rule object itself, and the in-memory
    /// calendar shows it on 28 February in a common year, as the anniversary rule says.
    @Test func leapDayBirthdayUsesFebruarysLastDay() async throws {
        let rule = try #require(EventKitRecurrence.rules(for: .lastDayOfFebruary)?.first)
        #expect(rule.frequency == .yearly)
        #expect(rule.interval == 1)
        #expect(rule.monthsOfTheYear == [2])
        #expect(rule.daysOfTheMonth == [-1])
        #expect(rule.daysOfTheWeek == nil && rule.recurrenceEnd == nil)
        #expect(EventKitRecurrence.recurrence(of: [rule]) == .lastDayOfFebruary)
        let plainFeb = EKRecurrenceRule(
            recurrenceWith: .yearly, interval: 1, daysOfTheWeek: nil, daysOfTheMonth: [28], monthsOfTheYear: [2],
            weeksOfTheYear: nil, daysOfTheYear: nil, setPositions: nil, end: nil)
        #expect(EventKitRecurrence.recurrence(of: [plainFeb]) == .custom)

        let field = try #require(PersonBirthday.parse("1996-02-29"))
        let first = try #require(field.firstDay(currentYear: 2026))
        let birthday = CalendarEventDraft.birthday(
            name: "Deniz Arıkan", on: LocalDay.instant(for: first), calendarID: nil, locale: Locale(identifier: "tr"))
        #expect(birthday.recurrence == .lastDayOfFebruary)
        let ordinary = CalendarEventDraft.birthday(
            name: "Deniz Arıkan", on: at(10), calendarID: nil, locale: Locale(identifier: "tr"))
        #expect(ordinary.recurrence == .yearly)
        #expect(CalendarWritePlan.changes(draft: birthday, original: nil).rule == .set(.lastDayOfFebruary, end: nil))

        let calendar = service(InMemoryCalendarSource())
        #expect(await calendar.save(birthday))
        #expect(await titles(calendar, on: CalendarDate("2027-02-28")!) == ["Deniz Arıkan doğum günü"])
        #expect(await titles(calendar, on: CalendarDate("2028-02-28")!).isEmpty)
        #expect(await titles(calendar, on: CalendarDate("2028-02-29")!) == ["Deniz Arıkan doğum günü"])
        let names = CalendarPersonNames(fullName: "Deniz Arıkan", aliases: [])
        let found = await calendar.personEvents(names: names, from: at(8))
        #expect(found?.birthday?.recurrence == .lastDayOfFebruary)
    }

    @Test func emptyTitleIsNotWrittenAndTimesAreNormalized() async {
        let source = InMemoryCalendarSource()
        let calendar = service(source)
        #expect(!(await calendar.save(draft("   "))))
        #expect(source.writeCount == 0)
        var backwards = draft("Ders")
        backwards.end = at(9)
        #expect(backwards.normalized().end == at(10))
        // 23:00–00:00 turned all day stays one day.
        var calendarUTC = Calendar(identifier: .gregorian)
        calendarUTC.timeZone = utc
        let late = calendarUTC.date(
            bySettingHour: 23, minute: 0, second: 0, of: LocalDay.instant(for: day, timeZone: utc))!
        let midnight = late.addingTimeInterval(3600)
        let allDay = CalendarEventDraft(
            title: "Gece", start: late, end: midnight, isAllDay: true, recurrence: .none, calendarID: nil
        ).normalized(timeZone: utc)
        #expect(allDay.start == calendarUTC.startOfDay(for: late))
        #expect(allDay.end == allDay.start)
    }

    @Test func newEventGoesToTheDefaultCalendar() async {
        let source = InMemoryCalendarSource()
        let calendar = service(source)
        calendar.defaultCalendarID = "work"
        #expect(await calendar.save(draft("Ders")))
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

    @Test func writesNeedReadAccessAndFailuresAreTyped() async {
        let denied = InMemoryCalendarSource(authorization: .denied)
        #expect(!(await service(denied).save(draft("Ders"))))
        #expect(denied.writeCount == 0)

        let failing = service(InMemoryCalendarSource(calendars: []))
        #expect(!(await failing.save(draft("Ders"))))
        #expect(failing.writeError == .noCalendar)
        failing.clearWriteError()
        #expect(failing.writeError == nil)
    }

    @Test func readOnlySourceRefusesWrites() async {
        final class ReadOnly: CalendarEventSource {
            var authorization = CalendarAuthorization.fullAccess
            var onChange: (@MainActor @Sendable () -> Void)?
            func requestFullAccess() async throws -> Bool { true }
            func events(from start: Date, to end: Date) async throws -> [CalendarEvent] { [] }
        }
        let calendar = CalendarService(source: ReadOnly())
        #expect(!(await calendar.save(draft("Ders"))))
        #expect(calendar.writeError == .unsupported)
        #expect(await calendar.writableCalendars().isEmpty)
    }

    /// A subscribed calendar or someone else's invitation: neither edit nor delete reaches it.
    @Test func readOnlyEventIsNeverChanged() async throws {
        let invite = CalendarEvent(
            id: "invite", title: "Davet", start: at(10), end: at(11), isAllDay: false, color: color,
            eventIdentifier: "invite", calendarID: "home", calendarTitle: "Ev", isEditable: false)
        let source = InMemoryCalendarSource(events: [invite])
        let calendar = service(source)
        await calendar.load(day)
        let shown = try #require(calendar.events(on: day).first)
        var change = CalendarEventDraft(event: shown)
        change.title = "Değişti"
        #expect(!(await calendar.save(change, editing: shown)))
        #expect(calendar.writeError == .readOnly)
        #expect(!(await calendar.delete(shown)))
        #expect(source.writeCount == 0)
        #expect(await titles(calendar, on: day) == ["Davet"])
    }

    // MARK: - Repeating events

    private let week2 = CalendarDate("2026-10-11")!
    private let week3 = CalendarDate("2026-10-18")!

    private func weekly() async throws -> (InMemoryCalendarSource, CalendarService, CalendarEvent) {
        let source = InMemoryCalendarSource()
        let calendar = service(source)
        #expect(await calendar.save(draft("Ders", recurrence: .weekly)))
        await calendar.load(week2)
        let middle = try #require(calendar.events(on: week2).first)
        #expect(middle.recurrence == .weekly)
        #expect(middle.start == at(10, on: week2))
        return (source, calendar, middle)
    }

    @Test func deleteOnlyThisOccurrence() async throws {
        let (_, calendar, middle) = try await weekly()
        #expect(await calendar.delete(middle, span: .thisEvent))
        #expect(await titles(calendar, on: day) == ["Ders"])
        #expect(await titles(calendar, on: week2).isEmpty)
        #expect(await titles(calendar, on: week3) == ["Ders"])
    }

    @Test func deleteThisAndFollowing() async throws {
        let (_, calendar, middle) = try await weekly()
        #expect(await calendar.delete(middle, span: .futureEvents))
        #expect(await titles(calendar, on: day) == ["Ders"])
        #expect(await titles(calendar, on: week2).isEmpty)
        #expect(await titles(calendar, on: week3).isEmpty)
    }

    @Test func editOnlyThisOccurrence() async throws {
        let (_, calendar, middle) = try await weekly()
        var change = CalendarEventDraft(event: middle)
        change.title = "Sınav"
        #expect(await calendar.save(change, editing: middle, span: .thisEvent))
        #expect(await titles(calendar, on: day) == ["Ders"])
        #expect(await titles(calendar, on: week2) == ["Sınav"])
        #expect(await titles(calendar, on: week3) == ["Ders"])
    }

    @Test func editThisAndFollowing() async throws {
        let (_, calendar, middle) = try await weekly()
        var change = CalendarEventDraft(event: middle)
        change.title = "Yeni ders"
        #expect(await calendar.save(change, editing: middle, span: .futureEvents))
        #expect(await titles(calendar, on: day) == ["Ders"])
        #expect(await titles(calendar, on: week2) == ["Yeni ders"])
        #expect(await titles(calendar, on: week3) == ["Yeni ders"])
    }

    /// The occurrence went away meanwhile: no write lands on the series' first occurrence, and
    /// "Bu ve sonrakiler" does not take the whole series with it.
    @Test func staleOccurrenceIsNotFoundAndTheSeriesStays() async throws {
        let (source, calendar, middle) = try await weekly()
        #expect(await calendar.delete(middle, span: .thisEvent))
        let writes = source.writeCount
        #expect(!(await calendar.delete(middle, span: .futureEvents)))
        #expect(calendar.writeError == .notFound)
        var change = CalendarEventDraft(event: middle)
        change.title = "Yanlış"
        #expect(!(await calendar.save(change, editing: middle, span: .futureEvents)))
        #expect(source.writeCount == writes)
        #expect(await titles(calendar, on: day) == ["Ders"])
        #expect(await titles(calendar, on: week3) == ["Ders"])
    }

    @Test func spanChoicesFollowTheRuleAndTheCalendar() async throws {
        let (_, _, middle) = try await weekly()
        var same = CalendarEventDraft(event: middle)
        same.title = "Ders 2"
        #expect(CalendarEventDraft.spans(saving: same, over: middle) == [.thisEvent, .futureEvents])
        var changed = same
        changed.recurrence = .monthly
        #expect(CalendarEventDraft.spans(saving: changed, over: middle) == [.futureEvents])
        var moved = same
        moved.calendarID = "work"
        #expect(CalendarEventDraft.spans(saving: moved, over: middle) == [.futureEvents])
        var single = middle
        single.recurrence = .none
        #expect(CalendarEventDraft.spans(saving: CalendarEventDraft(event: single), over: single) == [.thisEvent])
    }

    @Test func weeklyRuleWithEndStopsAndKeepsItsEndWhenChanged() async throws {
        let end = at(12, on: week2)
        var series = CalendarEvent(
            id: "s", title: "Kurs", start: at(10), end: at(11), isAllDay: false, color: color, eventIdentifier: "s",
            calendarID: "home", calendarTitle: "Ev", recurrence: .weekly, recurrenceEnd: end, isEditable: true)
        let calendar = service(InMemoryCalendarSource(events: [series]))
        #expect(await titles(calendar, on: week2) == ["Kurs"])
        #expect(await titles(calendar, on: week3).isEmpty)
        series.occurrenceDate = series.start
        var monthly = CalendarEventDraft(event: series)
        monthly.recurrence = .monthly
        #expect(CalendarWritePlan.changes(draft: monthly, original: series).rule == .set(.monthly, end: end))
    }

    // MARK: - Pure write plan

    @Test func pickOccurrenceNeverFallsBackOnASeries() {
        func candidate(_ start: Date, original: Date? = nil, recurring: Bool = true, id: String = "s")
            -> OccurrenceCandidate
        {
            OccurrenceCandidate(identifier: id, start: start, occurrenceDate: original ?? start, isRecurring: recurring)
        }
        var target = CalendarEvent(
            id: "t", title: "Ders", start: at(10, on: week2), end: at(11, on: week2), isAllDay: false, color: color,
            eventIdentifier: "s", recurrence: .weekly, occurrenceDate: at(10, on: week2))
        let first = candidate(at(10))
        // Exact original start, even when this occurrence was moved to 14:00.
        let moved = candidate(at(14, on: week2), original: at(10, on: week2))
        #expect(CalendarWritePlan.pickOccurrence(target, in: [first, moved], fallback: first) == .candidate(1))
        // Gone from the window: the series' first occurrence is not a stand-in.
        #expect(CalendarWritePlan.pickOccurrence(target, in: [], fallback: first) == .notFound)
        #expect(
            CalendarWritePlan.pickOccurrence(target, in: [candidate(at(10, on: week2), id: "other")], fallback: nil)
                == .notFound)
        // Start match when the calendar gives no original start.
        let plain = OccurrenceCandidate(
            identifier: "s", start: at(10, on: week2), occurrenceDate: nil, isRecurring: true)
        #expect(CalendarWritePlan.pickOccurrence(target, in: [plain], fallback: first) == .candidate(0))
        // A single event that moved elsewhere is still itself.
        target.recurrence = .none
        let single = candidate(at(15), recurring: false)
        #expect(CalendarWritePlan.pickOccurrence(target, in: [], fallback: single) == .fallback)
        target.eventIdentifier = nil
        #expect(CalendarWritePlan.pickOccurrence(target, in: [], fallback: single) == .notFound)
    }

    @Test func changesWriteOnlyWhatTheUserChanged() {
        let original = CalendarEvent(
            id: "e", title: "Ders", start: at(10), end: at(11), isAllDay: false, color: color, eventIdentifier: "e",
            calendarID: "home", recurrence: .custom, isEditable: true)
        var draft = CalendarEventDraft(event: original)
        #expect(CalendarWritePlan.changes(draft: draft, original: original).isEmpty)
        draft.title = "Sınav"
        #expect(
            CalendarWritePlan.changes(draft: draft, original: original) == CalendarWritePlan.Changes(title: "Sınav"))
        draft.calendarID = "work"
        draft.recurrence = .none
        let both = CalendarWritePlan.changes(draft: draft, original: original)
        #expect(both.calendarID == "work")
        #expect(both.rule == .remove)
        #expect(both.start == nil && both.end == nil && both.isAllDay == nil)
        let created = CalendarWritePlan.changes(draft: self.draft("Yeni", recurrence: .daily), original: nil)
        #expect(created.title == "Yeni" && created.start == at(10) && created.rule == .set(.daily, end: nil))
    }

    @Test func calendarChoiceAndEditability() {
        let writable: Set = ["home", "work"]
        #expect(
            CalendarWritePlan.calendarID(requested: "work", current: "home", writable: writable, systemDefault: "home")
                == "work")
        #expect(
            CalendarWritePlan.calendarID(requested: "gone", current: "home", writable: writable, systemDefault: "work")
                == "home")
        #expect(
            CalendarWritePlan.calendarID(requested: nil, current: nil, writable: writable, systemDefault: "work")
                == "work")
        #expect(CalendarWritePlan.isEditable(calendarAllowsModifications: true, organizerIsOtherPerson: false))
        #expect(!CalendarWritePlan.isEditable(calendarAllowsModifications: true, organizerIsOtherPerson: true))
        #expect(!CalendarWritePlan.isEditable(calendarAllowsModifications: false, organizerIsOtherPerson: false))
    }

    @Test func eventKitRuleAndSpanMapping() {
        #expect(EventKitRecurrence.recurrence(of: nil) == .none)
        for value in [CalendarRecurrence.daily, .weekly, .monthly, .yearly] {
            #expect(EventKitRecurrence.recurrence(of: EventKitRecurrence.rules(for: value)) == value)
        }
        #expect(EventKitRecurrence.rules(for: .none) == nil)
        #expect(EventKitRecurrence.rules(for: .custom) == nil)
        #expect(EventKitRecurrence.rules(for: .remove) == nil)
        let end = at(10, on: week3)
        let ended = EventKitRecurrence.rules(for: .set(.weekly, end: end))
        #expect(ended?.first?.recurrenceEnd?.endDate == end)
        #expect(EventKitRecurrence.recurrence(of: ended) == .weekly)
        let counted = EKRecurrenceRule(recurrenceWith: .weekly, interval: 1, end: EKRecurrenceEnd(occurrenceCount: 5))
        #expect(EventKitRecurrence.recurrence(of: [counted]) == .custom)
        let everyOther = EKRecurrenceRule(recurrenceWith: .weekly, interval: 2, end: nil)
        #expect(EventKitRecurrence.recurrence(of: [everyOther]) == .custom)
        let weekdays = EKRecurrenceRule(
            recurrenceWith: .weekly, interval: 1, daysOfTheWeek: [EKRecurrenceDayOfWeek(.monday)],
            daysOfTheMonth: nil, monthsOfTheYear: nil, weeksOfTheYear: nil, daysOfTheYear: nil,
            setPositions: nil, end: nil)
        #expect(EventKitRecurrence.recurrence(of: [weekdays]) == .custom)
        #expect(EventKitRecurrence.span(.thisEvent) == .thisEvent)
        #expect(EventKitRecurrence.span(.futureEvents) == .futureEvents)
    }

    @Test func newDraftStartTimes() {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = utc
        func now(_ hour: Int, _ minute: Int) -> Date {
            calendar.date(
                bySettingHour: hour, minute: minute, second: 0, of: LocalDay.instant(for: day, timeZone: utc))!
        }
        let today = CalendarEventDraft.new(on: day, now: now(14, 20), calendarID: "home", timeZone: utc)
        #expect(calendar.component(.hour, from: today.start) == 15)
        #expect(today.end.timeIntervalSince(today.start) == 3600)
        #expect(today.calendarID == "home")
        // After 23:00 the next hour is tomorrow: start now, on today.
        let late = CalendarEventDraft.new(on: day, now: now(23, 37), calendarID: nil, timeZone: utc)
        #expect(late.start == now(23, 35))
        let other = CalendarEventDraft.new(
            on: CalendarDate("2026-10-09")!, now: now(14, 20), calendarID: nil, timeZone: utc)
        #expect(calendar.component(.hour, from: other.start) == 9)
    }

    // MARK: - Person page

    private func event(
        _ title: String, attendees: [Attendee] = [], allDay: Bool = false, recurrence: CalendarRecurrence = .none,
        birthdays: Bool = false
    ) -> CalendarEvent {
        CalendarEvent(
            id: title, title: title, start: at(10), end: at(11), isAllDay: allDay, color: color, attendees: attendees,
            recurrence: recurrence, isFromBirthdayCalendar: birthdays)
    }

    @Test func personMatchingNeedsTheFullNameOrAnAttendee() {
        let names = CalendarPersonNames(fullName: "Deniz Arıkan", aliases: ["Den", "Deniz A."])
        #expect(CalendarPersonMatch.matches(event("Deniz Arıkan ile kahve"), names: names))
        #expect(CalendarPersonMatch.matches(event("DENİZ ARIKAN'ın sunumu"), names: names))
        #expect(CalendarPersonMatch.matches(event("deniz a. ile tenis"), names: names))
        // One word is a common word: "Den", "Deniz kenarı" never match by title.
        #expect(!CalendarPersonMatch.matches(event("Den ile tenis"), names: names))
        #expect(!CalendarPersonMatch.matches(event("Deniz kenarı"), names: names))
        #expect(!CalendarPersonMatch.matches(event("Denizli gezisi"), names: names))
        #expect(CalendarPersonMatch.matches(event("Proje", attendees: [Attendee(name: "deniz arıkan")]), names: names))
        #expect(CalendarPersonMatch.matches(event("Proje", attendees: [Attendee(name: "Den")]), names: names))
        #expect(!CalendarPersonMatch.matches(event("Proje", attendees: [Attendee(name: "Deniz")]), names: names))
        #expect(
            !CalendarPersonMatch.matches(
                event("Proje", attendees: [Attendee(name: "Deniz Arıkan", isCurrentUser: true)]), names: names))
        let single = CalendarPersonNames(fullName: "Can", aliases: [])
        #expect(!CalendarPersonMatch.matches(event("Can sıkıntısı"), names: single))
        #expect(CalendarPersonMatch.matches(event("Ders", attendees: [Attendee(name: "CAN")]), names: single))
        // Turkish İ/ı fold.
        let ilker = CalendarPersonNames(fullName: "İlker Işık", aliases: [])
        #expect(CalendarPersonMatch.matches(event("ilker ışık ile yemek"), names: ilker))
    }

    @Test func birthdayIsOnlyTheFullNamesOwn() {
        let ayse = "Ayşe"
        #expect(
            CalendarBirthday.isBirthday(event("Ayşe doğum günü", allDay: true, recurrence: .yearly), fullName: ayse))
        #expect(
            !CalendarBirthday.isBirthday(
                event("Ayşe Kaya doğum günü", allDay: true, recurrence: .yearly), fullName: ayse))
        #expect(!CalendarBirthday.isBirthday(event("Ayşe Kaya’s Birthday", birthdays: true), fullName: ayse))
        let kaya = "Ayşe Kaya"
        #expect(CalendarBirthday.isBirthday(event("Ayşe Kaya's Birthday", birthdays: true), fullName: kaya))
        #expect(
            CalendarBirthday.isBirthday(event("Ayşe Kaya adlı kişinin doğum günü", birthdays: true), fullName: kaya))
        #expect(
            CalendarBirthday.isBirthday(
                event("AYŞE KAYA'nın doğum günü", allDay: true, recurrence: .yearly), fullName: kaya))
        #expect(
            !CalendarBirthday.isBirthday(
                event("Ayşe Kaya doğum günü", allDay: false, recurrence: .yearly), fullName: kaya))
        #expect(
            !CalendarBirthday.isBirthday(event("Ayşe Kaya doğum günü", allDay: true, recurrence: .none), fullName: kaya)
        )
        #expect(
            !CalendarBirthday.isBirthday(
                event("Ayşe Kaya ile yemek", allDay: true, recurrence: .yearly), fullName: kaya))
        #expect(
            !CalendarBirthday.isBirthday(
                event("Ayşe Kaya doğum günü partisi", allDay: true, recurrence: .yearly), fullName: kaya))
    }

    @Test func birthdayIsAddedYearlyAndFoundOnThePersonPage() async throws {
        let source = InMemoryCalendarSource()
        let calendar = service(source)
        let names = CalendarPersonNames(fullName: "Deniz Arıkan", aliases: [])
        let before = try #require(await calendar.personEvents(names: names, from: at(8)))
        #expect(before.birthday == nil && before.upcoming.isEmpty)

        let field = try #require(PersonBirthday.parse("1996-12-01"))
        let first = try #require(field.firstDay(currentYear: 2026))
        let draft = CalendarEventDraft.birthday(
            name: "Deniz Arıkan", on: LocalDay.instant(for: first), calendarID: nil, locale: Locale(identifier: "tr"))
        #expect(draft.title == "Deniz Arıkan doğum günü")
        #expect(draft.isAllDay && draft.recurrence == .yearly)
        #expect(await calendar.save(draft))
        #expect(await calendar.save(self.draft("Deniz Arıkan ile kahve", 15)))
        #expect(await calendar.save(self.draft("Ece Yalın ile kahve", 15)))

        let after = try #require(await calendar.personEvents(names: names, from: at(8)))
        #expect(after.upcoming.map(\.title) == ["Deniz Arıkan ile kahve", "Deniz Arıkan doğum günü"])
        let found = try #require(after.birthday)
        #expect(LocalDay.today(at: found.start) == CalendarDate("2026-12-01"))
    }

    @Test func personEventsNeedReadAccessAndCapAtFive() async {
        let names = CalendarPersonNames(fullName: "Deniz Arıkan", aliases: [])
        #expect(
            await service(InMemoryCalendarSource(authorization: .denied)).personEvents(names: names, from: at(8)) == nil
        )
        let calendar = service(InMemoryCalendarSource())
        #expect(await calendar.save(draft("Deniz Arıkan ders", recurrence: .daily)))
        let result = await calendar.personEvents(names: names, from: at(8))
        #expect(result?.upcoming.count == 5)
        #expect(result?.birthday == nil)
    }
}
