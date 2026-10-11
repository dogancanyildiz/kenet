import EntityRecognition
import Foundation
import Testing
import VaultFormat

@testable import Journal

@MainActor
struct CalendarDraftTests {
    @Test func draftCarriesTitleStartAndKnownAttendees() async throws {
        let context = try TaskTestContext(sample: true)
        defer { context.clean() }
        await context.start()
        let model = context.model()
        model.mode = .task
        let known = context.store.knownEntities
        #expect(model.applyCalendarDraft(meeting(on: context.today, hour: 14, minute: 30)))
        #expect(model.mode == .event)
        #expect(model.text == "Proje toplantısı @Deniz Arıkan @Mert Aksu ")
        #expect(model.entryTime == (try LineClock(hour: 14, minute: 30)))
        #expect(model.unknownAttendees == ["Ada Soylu"])
        #expect(model.suggestions().isEmpty)
        let mentions = model.mentions
        #expect(mentions.map(\.spelling) == ["Deniz Arıkan", "Mert Aksu"])
        #expect(model.choices == [mentions[0].position: "people/Deniz Arıkan.md"])
        #expect(mentions[1].isAmbiguous)
        // Nothing is created or bound without the user: the second name still asks.
        #expect(await !model.submit(time: model.entryTime))
        #expect(model.pendingAmbiguity?.spelling == "Mert Aksu")
        #expect(context.store.knownEntities == known)
        #expect(context.store.content.day(on: LocalDay.today()).events.isEmpty)
    }

    @Test func eventWithoutAttendeesBringsOnlyTitleAndTime() async throws {
        let context = try TaskTestContext(sample: true)
        defer { context.clean() }
        await context.start()
        let model = context.model()
        #expect(model.applyCalendarDraft(event(on: context.today, hour: 9, minute: 5, title: " Diş \n hekimi ")))
        #expect(model.text == "Diş hekimi")
        #expect(model.entryTime == (try LineClock(hour: 9, minute: 5)))
        #expect(model.unknownAttendees.isEmpty)
        #expect(model.pins.isEmpty)
    }

    @Test func allDayEventHasNoTimeUntilTheDraftEnds() async throws {
        let context = try TaskTestContext(sample: true)
        defer { context.clean() }
        await context.start()
        let model = context.model()
        #expect(model.includesTime)
        #expect(model.applyCalendarDraft(event(on: context.today, hour: 0, minute: 0, title: "Bayram", allDay: true)))
        #expect(model.entryTime == nil)
        #expect(!model.includesTime)
        // Deleting the draft returns the time control to the day's default.
        model.text = ""
        #expect(model.calendarDraft == nil)
        #expect(model.includesTime)
    }

    @Test func eventThatBeganOnAnotherDayHasNoTime() async throws {
        let context = try TaskTestContext(sample: true)
        defer { context.clean() }
        await context.start()
        let model = context.model()
        let yesterday = CalendarDate("2026-10-02")!
        #expect(model.applyCalendarDraft(event(on: yesterday, hour: 23, minute: 0, title: "Gece vardiyası")))
        #expect(model.text == "Gece vardiyası")
        #expect(model.entryTime == nil)
    }

    @Test func writtenDraftIsKept() async throws {
        let context = try TaskTestContext(sample: true)
        defer { context.clean() }
        await context.start()
        let model = context.model()
        model.mode = .task
        model.text = "yarım kalan cümle"
        #expect(!model.applyCalendarDraft(meeting(on: context.today, hour: 14, minute: 30)))
        #expect(model.text == "yarım kalan cümle")
        #expect(model.mode == .task)
        #expect(model.calendarDraft == nil)
        #expect(model.unknownAttendees.isEmpty)
        #expect(model.errorText != nil)
        // Blanks alone are not a draft.
        model.mode = .event
        model.text = "  "
        #expect(model.applyCalendarDraft(meeting(on: context.today, hour: 14, minute: 30)))
        #expect(model.text == "Proje toplantısı @Deniz Arıkan @Mert Aksu ")
    }

    @Test func unknownAttendeeEntersTheTextOnlyWhenTappedAndStillAsks() async throws {
        let context = try TaskTestContext(sample: true)
        defer { context.clean() }
        await context.start()
        let model = context.model()
        let person = context.root.appendingPathComponent("people/Ada Soylu.md")
        var draft = event(on: context.today, hour: 11, minute: 0, title: "Kahve")
        draft.attendees = [Attendee(name: "Ada Soylu"), Attendee(name: "Baran Tunç")]
        #expect(model.applyCalendarDraft(draft))
        #expect(model.text == "Kahve @Baran Tunç ")
        #expect(model.unknownAttendees == ["Ada Soylu"])
        model.addUnknownAttendee("Ada Soylu")
        #expect(model.text == "Kahve @Baran Tunç @Ada Soylu ")
        #expect(model.unknownAttendees.isEmpty)
        #expect(model.entryTime == (try LineClock(hour: 11, minute: 0)))
        #expect(model.choices.values.sorted() == ["people/Baran Tunç.md"])
        #expect(await !model.submit(time: model.entryTime))
        #expect(model.pendingUnknown?.spelling == "Ada Soylu")
        #expect(!FileManager.default.fileExists(atPath: person.path))
        #expect(!context.store.knownEntities.contains { $0.name == "Ada Soylu" })
    }

    @Test func sentDraftIsOneEventLineInTheDayFile() async throws {
        let context = try TaskTestContext(sample: true)
        defer { context.clean() }
        await context.start()
        let day = CalendarDate("2026-10-01")!
        let today = context.today
        let model = QuickEntryModel(store: context.store, day: day, today: { today })
        #expect(!model.includesTime)
        #expect(model.applyCalendarDraft(meeting(on: day, hour: 9, minute: 15)))
        #expect(await !model.submit(time: model.entryTime))
        let question = try #require(model.pendingAmbiguity)
        model.choose(try #require(question.candidates.first { $0.qualifier == "iş" }), for: question)
        #expect(await model.submit(time: model.entryTime))
        let bytes = try Data(contentsOf: context.root.appendingPathComponent("journal/2026-10-01.md"))
        let event = try #require(RawDocument(bytes: bytes).bodyLines.events.last)
        let id = try #require(event.block.id)
        let expected =
            "---\ntype: journal\ndate: 2026-10-01\n---\n\n## Events\n"
            + "- 09:15 Proje toplantısı [[Deniz Arıkan]] [[Mert Aksu (iş)|Mert Aksu]] ^\(id)\n"
        #expect(bytes == Data(expected.utf8))
        #expect(model.text.isEmpty)
        #expect(model.calendarDraft == nil)
        #expect(!model.includesTime)
        let stranger = context.root.appendingPathComponent("people/Ada Soylu.md")
        #expect(!FileManager.default.fileExists(atPath: stranger.path))
    }

    @Test func inboxHandsTheEventToItsOwnDayOnce() {
        let inbox = CalendarDraftInbox()
        let event = event(on: CalendarDate("2026-10-03")!, hour: 8, minute: 0, title: "Koşu")
        inbox.post(event, on: CalendarDate("2026-10-03")!)
        #expect(inbox.take(on: CalendarDate("2026-10-02")!) == nil)
        #expect(inbox.take(on: CalendarDate("2026-10-03")!) == event)
        #expect(inbox.take(on: CalendarDate("2026-10-03")!) == nil)
    }

    /// A known person, a name two people share, a stranger, an address and the device owner.
    private func meeting(on day: CalendarDate, hour: Int, minute: Int) -> CalendarEvent {
        var event = event(on: day, hour: hour, minute: minute, title: "Proje toplantısı")
        event.attendees = [
            Attendee(name: "Deniz Arıkan"), Attendee(name: "Mert Aksu"), Attendee(name: "Ada Soylu"),
            Attendee(name: "ece@example.com"), Attendee(name: "Selin Korkmaz", isCurrentUser: true),
        ]
        return event
    }

    private func event(on day: CalendarDate, hour: Int, minute: Int, title: String, allDay: Bool = false)
        -> CalendarEvent
    {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = .current
        let start = calendar.date(
            from: DateComponents(year: day.year, month: day.month, day: day.day, hour: hour, minute: minute))!
        return CalendarEvent(
            id: title, title: title, start: start, end: start.addingTimeInterval(allDay ? 86400 : 3600),
            isAllDay: allDay, color: CalendarEventColor(red: 0.2, green: 0.4, blue: 0.8, alpha: 1))
    }
}
