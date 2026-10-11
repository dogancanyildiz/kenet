import EntityRecognition
import Foundation
import Testing
import VaultFormat

@testable import Journal

/// Every path that writes a picked entity into the field: a digit-only name keeps its at sign, the
/// only way it is recognized, and is linked as before; any other name is written exactly as before.
@MainActor
struct DigitNamePickTests {
    private func context(_ name: String) async throws -> TaskTestContext {
        let context = try TaskTestContext(sample: true)
        try Data("---\ntype: place\nname: \(name)\ncoordinates: [41.0000, 29.0000]\nradius: 80\n---\n".utf8)
            .write(to: context.root.appendingPathComponent("places/\(name).md"))
        await context.start()
        return context
    }

    private func entity(_ name: String, in context: TaskTestContext) throws -> KnownEntity {
        try #require(context.store.knownEntities.first { $0.file == "places/\(name).md" })
    }

    private func savedEvent(_ context: TaskTestContext) throws -> String? {
        let url = context.root.appendingPathComponent("journal/\(LocalDay.today()).md")
        return RawDocument(bytes: try Data(contentsOf: url)).bodyLines.events.last?.block.text
    }

    @Test(arguments: [("12", "bugün @1", "bugün @12"), ("Kuzey", "bugün @Ku", "bugün Kuzey")])
    func pickedSuggestionIsLinked(_ name: String, typed: String, picked: String) async throws {
        let context = try await context(name)
        defer { context.clean() }
        let model = context.model()
        model.text = typed
        #expect(model.composer.suggestions().contains { $0.file == "places/\(name).md" })
        model.selectSuggestion(try entity(name, in: context))
        #expect(model.text == picked)
        // The pick resolves the fragment: neither suggestions nor the create buttons come back.
        #expect(model.composer.suggestions().isEmpty)
        #expect(model.composer.suggestionRange() == nil)
        #expect(await model.submit(time: try LineClock(hour: 13, minute: 0)))
        #expect(try savedEvent(context) == "bugün [[\(name)]]")
    }

    /// The pin, not the at sign, says which of two same-named entities was picked.
    @Test func pickedSuggestionChoosesBetweenSameNamedEntities() async throws {
        let context = try await context("12")
        defer { context.clean() }
        try Data("---\ntype: place\nname: 12\nqualifier: iş\n---\n".utf8)
            .write(to: context.root.appendingPathComponent("places/12 (iş).md"))
        await context.store.refresh()
        let model = context.model()
        model.text = "bugün @1"
        model.selectSuggestion(try #require(context.store.knownEntities.first { $0.file == "places/12 (iş).md" }))
        #expect(model.text == "bugün @12")
        #expect(model.pendingAmbiguity == nil)
        #expect(await model.submit(time: try LineClock(hour: 13, minute: 0)))
        #expect(try savedEvent(context) == "bugün [[12 (iş)|12]]")
    }

    @Test(arguments: ["12", "Kuzey"])
    func nearbyPlaceIsLinked(_ name: String) async throws {
        let context = try await context(name)
        defer { context.clean() }
        let source = FakeLocationSource()
        source.authorization = .authorized
        source.fix = PlaceCoordinate(latitude: 41, longitude: 29)
        let model = context.model()
        model.locationService = LocationService(source: source, defaults: context.defaults.defaults)
        model.text = "bugün"
        model.focusLocation()
        #expect(model.suggestedPlace?.entity.name == name)
        model.selectLocation()
        #expect(model.text == "bugün @\(name)")
        #expect(await model.submit(time: try LineClock(hour: 13, minute: 0)))
        #expect(try savedEvent(context) == "bugün [[\(name)]]")
    }

    @Test(arguments: ["12", "Kuzey"])
    func draftOpenedFromAnEntityIsLinked(_ name: String) async throws {
        let context = try await context(name)
        defer { context.clean() }
        let summary = try #require(context.store.content.entities.first { $0.id == "places/\(name).md" })
        let model = context.model()
        model.text = "bugün"
        model.prefillMention(summary)
        #expect(model.text == "bugün @\(name) ")
        #expect(await model.submit(time: try LineClock(hour: 13, minute: 0)))
        #expect(try savedEvent(context) == "bugün [[\(name)]]")
    }

    @Test(arguments: ["12", "Kuzey"])
    func calendarAttendeeIsLinked(_ name: String) async throws {
        let context = try await context(name)
        defer { context.clean() }
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = .current
        let day = context.today
        let start = try #require(
            calendar.date(from: DateComponents(year: day.year, month: day.month, day: day.day, hour: 9, minute: 5)))
        var event = CalendarEvent(
            id: "toplanti", title: "Toplantı", start: start, end: start.addingTimeInterval(3600), isAllDay: false,
            color: CalendarEventColor(red: 0.2, green: 0.4, blue: 0.8, alpha: 1))
        event.attendees = [Attendee(name: name)]
        let model = context.model()
        #expect(model.applyCalendarDraft(event))
        #expect(model.text == "Toplantı @\(name) ")
        #expect(await model.submit(time: model.entryTime))
        #expect(try savedEvent(context) == "Toplantı [[\(name)]]")
    }

    /// Only a pick closes the list: a typed `@12` still offers it, and a picked one stays shut with the caret inside.
    @Test func typedDigitNameKeepsItsSuggestionsUntilPicked() async throws {
        let context = try await context("12")
        defer { context.clean() }
        let model = context.model()
        model.text = "bugün @12"
        #expect(model.composer.suggestionRange() == "bugün ".utf8.count..<model.text.utf8.count)
        #expect(model.composer.suggestions().contains { $0.file == "places/12.md" })
        model.selectSuggestion(try entity("12", in: context))
        #expect(model.text == "bugün @12")
        #expect(model.composer.suggestionRange() == nil)
        #expect(model.composer.suggestionRange(at: "bugün @1".utf8.count) == nil)
        model.text += " geldi"
        #expect(model.composer.suggestions().isEmpty)
        #expect(await model.submit(time: try LineClock(hour: 13, minute: 0)))
        #expect(try savedEvent(context) == "bugün [[12]] geldi")
    }

    @Test(arguments: [("12", "@1", "@12"), ("Kuzey", "@Ku", "Kuzey")])
    func journalEditorPickIsLinked(_ name: String, typed: String, picked: String) async throws {
        let context = try DayEditingTestContext()
        defer { context.clean() }
        try Data("---\ntype: place\nname: \(name)\n---\n".utf8)
            .write(to: context.root.appendingPathComponent("places/\(name).md"))
        await context.start()
        let model = JournalEditorModel(store: context.store, day: context.day)
        await model.load()
        let original = model.text
        model.text = typed + " geldi.\n" + original
        let entity = try #require(
            model.composer.suggestions(at: typed.utf8.count).first { $0.file == "places/\(name).md" })
        #expect(model.composer.selectSuggestion(entity, at: typed.utf8.count) == picked.utf8.count)
        #expect(model.text == picked + " geldi.\n" + original)
        #expect(model.composer.suggestionRange(at: picked.utf8.count) == nil)
        #expect(await model.save())
        let body = try JournalRecognition.body(of: RawDocument(bytes: try Data(contentsOf: context.file)))
        #expect(body.hasPrefix("[[\(name)]] geldi.\n"))
    }

    @Test(arguments: [("12", "@1", "@12"), ("Kuzey", "@Ku", "Kuzey")])
    func eventEditorPickIsLinked(_ name: String, typed: String, picked: String) async throws {
        let context = try DayEditingTestContext()
        defer { context.clean() }
        try Data("---\ntype: place\nname: \(name)\n---\n".utf8)
            .write(to: context.root.appendingPathComponent("places/\(name).md"))
        await context.start()
        let row = try #require(context.store.content.day(on: context.day).events.first)
        let model = EventEditorModel(store: context.store, day: context.day, row: row)
        await model.load()
        model.text = typed + " ile"
        let entity = try #require(
            model.composer.suggestions(at: typed.utf8.count).first { $0.file == "places/\(name).md" })
        #expect(model.composer.selectSuggestion(entity, at: typed.utf8.count) == picked.utf8.count)
        #expect(model.text == picked + " ile")
        #expect(await model.save())
        let saved = RawDocument(bytes: try Data(contentsOf: context.file)).bodyLines.events.first?.block.text
        #expect(saved == "[[\(name)]] ile")
    }
}
