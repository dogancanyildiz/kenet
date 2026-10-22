import EntityRecognition
import Foundation
import Testing
import VaultFormat

@testable import Journal

/// A picked journaling suggestion (built directly: the framework's picker opens on a device only)
/// becomes event text in the quick entry; nothing is written until the user sends it.
@MainActor
struct JournalingSuggestionsTests {
    nonisolated private static let turkish = Locale(identifier: "tr_TR")
    nonisolated private static let english = Locale(identifier: "en_US")
    nonisolated private static let zone = TimeZone(identifier: "Europe/Istanbul")!

    // MARK: - One item, one kind

    struct KindCase: CustomTestStringConvertible, Sendable {
        let name: String
        let title: String
        let item: SuggestionContent
        let text: String?
        let mentions: [SuggestionLine.Mention]
        let skipped: Int
        var testDescription: String { name }
    }

    nonisolated private static let kinds: [KindCase] = [
        .init(
            name: "location", title: "Akşam yürüyüşü",
            item: .location(name: "Moda Sahili", city: "İstanbul", date: nil),
            text: "Akşam yürüyüşü", mentions: [.init(name: "Moda Sahili", kind: .place)], skipped: 0),
        .init(
            name: "location by city", title: "Gezi", item: .location(name: " ", city: "Kadıköy", date: nil),
            text: "Gezi", mentions: [.init(name: "Kadıköy", kind: .place)], skipped: 0),
        .init(
            name: "contact titled by its name", title: "Deniz Arıkan", item: .contact(name: "Deniz Arıkan"),
            text: "", mentions: [.init(name: "Deniz Arıkan", kind: .person)], skipped: 0),
        .init(
            name: "contact cleaned as contact import does", title: "Sohbet", item: .contact(name: " Ada [Soylu] "),
            text: "Sohbet", mentions: [.init(name: "Ada Soylu", kind: .person)], skipped: 0),
        .init(
            name: "address is no name", title: "Sohbet", item: .contact(name: "ece@example.com"),
            text: nil, mentions: [], skipped: 0),
        .init(
            name: "workout", title: "Sabah", item: .workout(name: "Koşu", duration: 32 * 60 + 10, start: nil),
            text: "Koşu 32 dk", mentions: [], skipped: 0),
        .init(
            name: "workout without a name", title: "Sabah", item: .workout(name: nil, duration: 20, start: nil),
            text: "Egzersiz 1 dk", mentions: [], skipped: 0),
        .init(
            name: "song", title: "Müzik", item: .song(title: "Yol", artist: "Grup Mavi", date: nil),
            text: "Yol – Grup Mavi", mentions: [], skipped: 0),
        .init(
            name: "song without artist", title: "Müzik", item: .song(title: "Yol", artist: nil, date: nil),
            text: "Yol", mentions: [], skipped: 0),
        .init(
            name: "artist alone", title: "Müzik", item: .song(title: nil, artist: "Grup Mavi", date: nil),
            text: nil, mentions: [], skipped: 0),
        .init(
            name: "podcast", title: "Dinle", item: .podcast(episode: "Bölüm 12", show: "Gün Sonu", date: nil),
            text: "Bölüm 12 – Gün Sonu", mentions: [], skipped: 0),
        .init(
            name: "other media", title: "Dinle", item: .media(title: "Sesli kitap", artist: "Yazar", date: nil),
            text: "Sesli kitap – Yazar", mentions: [], skipped: 0),
        .init(
            name: "steps", title: "Yürüyüş", item: .motion(steps: 5234, start: nil),
            text: "5.234 adım", mentions: [], skipped: 0),
        .init(
            name: "reflection", title: "Yansıma", item: .reflection(prompt: "Bugün seni ne\ngülümsetti?"),
            text: "Bugün seni ne gülümsetti?", mentions: [], skipped: 0),
        .init(
            name: "mood", title: "Ruh hali", item: .mood(.pleasant), text: "Ruh hali: iyi", mentions: [], skipped: 0),
        .init(
            name: "event with place", title: "Takvim",
            item: .event(title: "Diş hekimi", start: date(hour: 16, minute: 0), place: "Gülen Diş"),
            text: "Diş hekimi", mentions: [.init(name: "Gülen Diş", kind: .place)], skipped: 0),
        .init(
            name: "markup in a title", title: "Müzik",
            item: .song(title: "Hit #1 [[Yol]] @Ev", artist: "Grup", date: nil),
            text: "Hit ＃1 [Yol] ＠Ev – Grup", mentions: [], skipped: 0),
        .init(
            name: "markup in a reflection", title: "Yansıma", item: .reflection(prompt: "#bugün [[[Ev]]] e@posta"),
            text: "＃bugün [Ev] e@posta", mentions: [], skipped: 0),
        .init(
            name: "photo", title: "Anılar", item: .attachment(.photo), text: nil, mentions: [], skipped: 1),
        .init(
            name: "live photo", title: "Anılar", item: .attachment(.livePhoto), text: nil, mentions: [], skipped: 1),
        .init(
            name: "video", title: "Anılar", item: .attachment(.video), text: nil, mentions: [], skipped: 1),
    ]

    @Test(arguments: kinds)
    func eachKindBecomesItsText(_ kind: KindCase) {
        let draft = SuggestionText.draft(
            from: SuggestionPick(title: kind.title, date: nil, items: [kind.item]), locale: Self.turkish)
        #expect(draft.skippedMedia == kind.skipped)
        if let text = kind.text {
            #expect(draft.lines.count == 1)
            #expect(draft.lines.first?.text == text)
            #expect(draft.lines.first?.mentions == kind.mentions)
        } else {
            #expect(draft.lines.isEmpty)
        }
    }

    @Test func textFollowsTheChosenLanguage() {
        let pick = SuggestionPick(
            title: "Day", date: nil,
            items: [
                .workout(name: nil, duration: 32 * 60, start: nil), .motion(steps: 1, start: nil),
                .motion(steps: 40, start: nil), .mood(.veryUnpleasant),
            ])
        let lines = SuggestionText.draft(from: pick, locale: Self.english).lines
        #expect(lines.map(\.text) == ["Workout 32 min", "1 step", "40 steps", "Mood: very unpleasant"])
    }

    @Test func everyMoodHasItsOwnWords() {
        let texts = SuggestionContent.MoodValence.allCases.map { valence in
            SuggestionText.draft(
                from: SuggestionPick(title: "", date: nil, items: [.mood(valence)]), locale: Self.turkish
            ).lines.first?.text
        }
        #expect(Set(texts.compactMap { $0 }).count == 7)
    }

    // MARK: - Several items

    /// Each item with words of its own is its own event line; people and places join the first
    /// line, once each; photos are counted, not written.
    @Test func severalItemsBecomeSeveralLines() {
        let pick = SuggestionPick(
            title: "Cumartesi", date: DateInterval(start: Self.date(hour: 9, minute: 0), duration: 3600),
            items: [
                .song(title: "Yol", artist: "Grup Mavi", date: Self.date(hour: 10, minute: 30)),
                .attachment(.photo),
                .location(name: "Moda Sahili", city: nil, date: nil),
                .song(title: "Deniz", artist: nil, date: nil),
                .contact(name: "Deniz Arıkan"),
                .contact(name: "DENİZ ARIKAN"),
                .attachment(.video),
            ])
        let draft = SuggestionText.draft(from: pick, locale: Self.turkish)
        #expect(draft.lines.map(\.text) == ["Yol – Grup Mavi", "Deniz"])
        #expect(
            draft.lines[0].mentions == [
                .init(name: "Moda Sahili", kind: .place), .init(name: "Deniz Arıkan", kind: .person),
            ])
        #expect(draft.lines[1].mentions.isEmpty)
        // An item's own moment first, the suggestion's otherwise.
        #expect(draft.lines.map(\.start) == [Self.date(hour: 10, minute: 30), Self.date(hour: 9, minute: 0)])
        #expect(draft.skippedMedia == 2)
    }

    /// As a calendar draft writes an event: its start is the entry's time, not words.
    @Test func eventStartIsTheEntryTime() {
        let start = Self.date(hour: 16, minute: 0)
        let pick = SuggestionPick(
            title: "Takvim", date: DateInterval(start: Self.date(hour: 9, minute: 0), duration: 3600),
            items: [.event(title: "Diş hekimi", start: start, place: nil)])
        let line = SuggestionText.draft(from: pick, locale: Self.turkish).lines.first
        #expect(line?.text == "Diş hekimi")
        #expect(line?.start == start)
    }

    @Test func photosAloneWriteNothing() {
        let pick = SuggestionPick(title: "Anılar", date: nil, items: [.attachment(.photo), .attachment(.livePhoto)])
        let draft = SuggestionText.draft(from: pick, locale: Self.turkish)
        #expect(draft == SuggestionDraft(lines: [], skippedMedia: 2))
    }

    // MARK: - The field

    /// Known names are pinned, an unknown place waits beside the text as a chip; nothing reaches
    /// the vault until the user sends.
    @Test func pickFillsTheFieldAndWritesNothing() async throws {
        let context = try TaskTestContext(sample: true)
        defer { context.clean() }
        await context.start()
        let day = CalendarDate("2026-10-01")!
        let today = context.today
        let model = QuickEntryModel(store: context.store, day: day, today: { today })
        model.mode = .task
        let known = context.store.knownEntities
        let pick = SuggestionPick(
            title: "Koşu", date: nil,
            items: [
                .workout(name: "Koşu", duration: 32 * 60, start: nil),
                .location(name: "Çınaraltı Kafe", city: nil, date: nil),
                .location(name: "Moda Sahili", city: nil, date: nil),
                .contact(name: "Deniz Arıkan"),
                .contact(name: "Mert Aksu"),
            ])
        #expect(model.applySuggestion(pick, locale: Self.turkish, timeZone: Self.zone))
        #expect(model.mode == .event)
        #expect(model.text == "Koşu 32 dk @Çınaraltı Kafe @Deniz Arıkan @Mert Aksu ")
        #expect(model.choices.values.sorted() == ["people/Deniz Arıkan.md", "places/Çınaraltı Kafe.md"])
        #expect(model.suggestedNames == [.init(name: "Moda Sahili", kind: .place)])
        let file = context.root.appendingPathComponent("journal/2026-10-01.md")
        #expect(!FileManager.default.fileExists(atPath: file.path))
        // Two people answer to "Mert Aksu": sending asks which one, as for a calendar attendee.
        #expect(await !model.submit(time: model.entryTime))
        #expect(model.pendingAmbiguity?.spelling == "Mert Aksu")
        #expect(!FileManager.default.fileExists(atPath: file.path))
        #expect(context.store.knownEntities == known)
    }

    struct UnknownNameCase: CustomTestStringConvertible, Sendable {
        let name: String
        let title: String
        let item: SuggestionContent
        let chip: SuggestionLine.Mention
        var testDescription: String { name }
    }

    nonisolated private static let unknownNames: [UnknownNameCase] = [
        // The sample's "Ev" is a place; the person "Ev" is no one the vault knows.
        .init(
            name: "person named as a place", title: "Sohbet", item: .contact(name: "Ev"),
            chip: .init(name: "Ev", kind: .person)),
        // "Ece" is Ece Yalın's alias; the whole name is a stranger's.
        .init(
            name: "stranger whose first word is an alias", title: "Sohbet", item: .contact(name: "Ece van Dijk"),
            chip: .init(name: "Ece van Dijk", kind: .person)),
        .init(
            name: "place of several words", title: "Kahve",
            item: .location(name: "Café de Flore", city: nil, date: nil),
            chip: .init(name: "Café de Flore", kind: .place)),
        .init(
            name: "lower-case place", title: "Kahve", item: .location(name: "starbucks", city: nil, date: nil),
            chip: .init(name: "starbucks", kind: .place)),
    ]

    /// A name no entity of its own kind answers to waits as a chip with its whole name; sending
    /// the line writes the words alone, neither a link nor a bare `@`, and creates nothing.
    @Test(arguments: unknownNames)
    func unknownNameIsAChipAndNeverWrittenUnasked(_ unknown: UnknownNameCase) async throws {
        let context = try TaskTestContext(sample: true)
        defer { context.clean() }
        await context.start()
        let today = context.today
        let model = QuickEntryModel(store: context.store, day: CalendarDate("2026-10-01")!, today: { today })
        let known = context.store.knownEntities
        let pick = SuggestionPick(title: unknown.title, date: nil, items: [unknown.item])
        #expect(model.applySuggestion(pick, locale: Self.turkish, timeZone: Self.zone))
        #expect(model.text == unknown.title)
        #expect(model.suggestedNames == [unknown.chip])
        #expect(await model.submit(time: model.entryTime))
        let bytes = try Data(contentsOf: context.root.appendingPathComponent("journal/2026-10-01.md"))
        let id = try #require(RawDocument(bytes: bytes).bodyLines.events.last?.block.id)
        let expected = "---\ntype: journal\ndate: 2026-10-01\n---\n\n## Events\n- \(unknown.title) ^\(id)\n"
        #expect(bytes == Data(expected.utf8))
        #expect(context.store.knownEntities == known)
    }

    /// The chip creates its whole name with its own kind; the name then enters the text pinned
    /// and is linked on sending.
    @Test func chipCreatesTheWholeNameAndLinksIt() async throws {
        let context = try TaskTestContext(sample: true)
        defer { context.clean() }
        await context.start()
        let today = context.today
        let model = QuickEntryModel(store: context.store, day: CalendarDate("2026-10-01")!, today: { today })
        let pick = SuggestionPick(
            title: "Kahve", date: nil, items: [.location(name: "Café de Flore", city: nil, date: nil)])
        #expect(model.applySuggestion(pick, locale: Self.turkish, timeZone: Self.zone))
        await model.addSuggestedName(.init(name: "Café de Flore", kind: .place))
        let place = context.root.appendingPathComponent("places/Café de Flore.md")
        #expect(FileManager.default.fileExists(atPath: place.path))
        #expect(model.text == "Kahve @Café de Flore ")
        #expect(model.suggestedNames.isEmpty)
        #expect(await model.submit(time: model.entryTime))
        let bytes = try Data(contentsOf: context.root.appendingPathComponent("journal/2026-10-01.md"))
        let id = try #require(RawDocument(bytes: bytes).bodyLines.events.last?.block.id)
        let expected = "---\ntype: journal\ndate: 2026-10-01\n---\n\n## Events\n- Kahve [[Café de Flore]] ^\(id)\n"
        #expect(bytes == Data(expected.utf8))
    }

    /// The person "Ev" collides with the place "Ev": the chip asks for a qualifier; dismissing
    /// it leaves the text and the chip as they were, creating it links the person, never the place.
    @Test func chipOfATakenNameAsksForAQualifier() async throws {
        let context = try TaskTestContext(sample: true)
        defer { context.clean() }
        await context.start()
        let today = context.today
        let model = QuickEntryModel(store: context.store, day: CalendarDate("2026-10-01")!, today: { today })
        let chip = SuggestionLine.Mention(name: "Ev", kind: .person)
        #expect(model.applySuggestion(SuggestionPick(title: "Sohbet", date: nil, items: [.contact(name: "Ev")])))
        await model.addSuggestedName(chip)
        #expect(model.needsQualifier)
        let question = try #require(model.pendingUnknown)
        #expect(question.spelling == "Ev")
        #expect(model.text == "Sohbet")
        #expect(model.composer.dismissCreation(question) == .keepEditing)
        #expect(model.text == "Sohbet")
        #expect(model.pendingUnknown == nil)
        #expect(model.suggestedNames == [chip])

        await model.addSuggestedName(chip)
        model.qualifier = "komşu"
        await model.create(.person)
        let person = context.root.appendingPathComponent("people/Ev (komşu).md")
        #expect(FileManager.default.fileExists(atPath: person.path))
        #expect(model.text == "Sohbet @Ev ")
        #expect(model.suggestedNames.isEmpty)
        #expect(await model.submit(time: model.entryTime))
        let bytes = try Data(contentsOf: context.root.appendingPathComponent("journal/2026-10-01.md"))
        let id = try #require(RawDocument(bytes: bytes).bodyLines.events.last?.block.id)
        let expected = "---\ntype: journal\ndate: 2026-10-01\n---\n\n## Events\n- Sohbet [[Ev (komşu)|Ev]] ^\(id)\n"
        #expect(bytes == Data(expected.utf8))
    }

    /// A title's markup stays words in the file: no link, no tag, no mention.
    @Test func markupInATitleIsWrittenAsWords() async throws {
        let context = try TaskTestContext(sample: true)
        defer { context.clean() }
        await context.start()
        let today = context.today
        let model = QuickEntryModel(store: context.store, day: CalendarDate("2026-10-01")!, today: { today })
        let pick = SuggestionPick(
            title: "Müzik", date: nil, items: [.song(title: "Hit #1 [[Yol]] @Liman", artist: "Grup", date: nil)])
        #expect(model.applySuggestion(pick, locale: Self.turkish))
        #expect(await model.submit(time: model.entryTime))
        let bytes = try Data(contentsOf: context.root.appendingPathComponent("journal/2026-10-01.md"))
        let id = try #require(RawDocument(bytes: bytes).bodyLines.events.last?.block.id)
        let expected =
            "---\ntype: journal\ndate: 2026-10-01\n---\n\n## Events\n- Hit ＃1 [Yol] ＠Liman – Grup ^\(id)\n"
        #expect(bytes == Data(expected.utf8))
    }

    /// The second line enters the field only after the first is saved; each is its own event.
    @Test func severalLinesAreSentOneByOne() async throws {
        let context = try TaskTestContext(sample: true)
        defer { context.clean() }
        await context.start()
        let day = CalendarDate("2026-10-01")!
        let today = context.today
        let model = QuickEntryModel(store: context.store, day: day, today: { today })
        model.includesTime = false
        let pick = SuggestionPick(
            title: "Müzik", date: nil,
            items: [
                .song(title: "Yol", artist: "Grup Mavi", date: nil), .attachment(.photo),
                .podcast(episode: "Bölüm 12", show: "Gün Sonu", date: nil),
            ])
        #expect(model.applySuggestion(pick, locale: Self.turkish, timeZone: Self.zone))
        #expect(model.text == "Yol – Grup Mavi")
        #expect(model.suggestionQueue?.remaining.map(\.text) == ["Bölüm 12 – Gün Sonu"])
        #expect(model.suggestionQueue?.skippedMedia == 1)
        // A typed draft is never replaced by the waiting line.
        #expect(!model.takeNextSuggestion())
        #expect(model.text == "Yol – Grup Mavi")

        let file = context.root.appendingPathComponent("journal/2026-10-01.md")
        // `submit` is the bar's only way to send: the next line comes with it.
        #expect(await model.submit(time: model.entryTime))
        // The second line waits in the field: only the first was written.
        #expect(RawDocument(bytes: try Data(contentsOf: file)).bodyLines.events.count == 1)
        #expect(model.text == "Bölüm 12 – Gün Sonu")
        #expect(model.suggestionQueue?.remaining.isEmpty == true)
        #expect(await model.submit(time: model.entryTime))
        #expect(model.text.isEmpty)
        #expect(model.suggestionQueue == nil)

        let bytes = try Data(contentsOf: file)
        let events = RawDocument(bytes: bytes).bodyLines.events
        #expect(events.count == 2)
        let text = String(decoding: bytes, as: UTF8.self)
        #expect(text.contains("- Yol – Grup Mavi ^"))
        #expect(text.contains("- Bölüm 12 – Gün Sonu ^"))
    }

    /// An entry the user wrote, a task or an event, leaves the waiting lines and the mode alone.
    @Test func onlyASentSuggestionLineBringsTheNext() async throws {
        let context = try TaskTestContext(sample: true)
        defer { context.clean() }
        await context.start()
        let today = context.today
        let model = QuickEntryModel(store: context.store, day: CalendarDate("2026-10-01")!, today: { today })
        model.languages = [.turkish, .english]
        let pick = SuggestionPick(
            title: "", date: nil, items: [.reflection(prompt: "Bir"), .reflection(prompt: "İki")])
        #expect(model.applySuggestion(pick, locale: Self.turkish))
        model.text = ""
        model.mode = .task
        model.text = "süt al"
        #expect(await model.submit(time: nil))
        #expect(model.mode == .task)
        #expect(model.text.isEmpty)
        #expect(model.suggestionQueue?.remaining.map(\.text) == ["İki"])

        model.mode = .event
        model.text = "kendi notum"
        #expect(await model.submit(time: nil))
        #expect(model.text.isEmpty)
        #expect(model.suggestionQueue?.remaining.map(\.text) == ["İki"])

        // The waiting line comes on request; sending it ends the suggestion.
        #expect(model.takeNextSuggestion())
        #expect(model.text == "İki")
        #expect(await model.submit(time: nil))
        #expect(model.suggestionQueue == nil)
    }

    @Test func emptiedFieldTakesTheNextLineOnRequest() async throws {
        let context = try TaskTestContext(sample: true)
        defer { context.clean() }
        await context.start()
        let model = context.model()
        let pick = SuggestionPick(
            title: "", date: nil, items: [.reflection(prompt: "Bir"), .reflection(prompt: "İki")])
        #expect(model.applySuggestion(pick, locale: Self.turkish))
        model.text = ""
        #expect(model.takeNextSuggestion())
        #expect(model.text == "İki")
        model.dropSuggestions()
        #expect(model.suggestionQueue == nil)
        #expect(model.text == "İki")
    }

    @Test func typedDraftRefusesThePick() async throws {
        let context = try TaskTestContext(sample: true)
        defer { context.clean() }
        await context.start()
        let model = context.model()
        model.text = "yarım kalan cümle"
        #expect(!model.applySuggestion(SuggestionPick(title: "", date: nil, items: [.reflection(prompt: "Soru")])))
        #expect(model.text == "yarım kalan cümle")
        #expect(model.suggestionQueue == nil)
        #expect(model.errorText != nil)
    }

    @Test func photosAloneLeaveTheFieldEmptyWithANote() async throws {
        let context = try TaskTestContext(sample: true)
        defer { context.clean() }
        await context.start()
        let model = context.model()
        #expect(!model.applySuggestion(SuggestionPick(title: "Anılar", date: nil, items: [.attachment(.photo)])))
        #expect(model.text.isEmpty)
        #expect(model.suggestionQueue == .init(remaining: [], skippedMedia: 1))
        #expect(
            SuggestionCopy.note(remaining: 0, skippedMedia: 1, locale: Self.turkish)
                == "Fotoğraf ve videolar yazılmaz.")
        #expect(
            SuggestionCopy.note(remaining: 2, skippedMedia: 1, locale: Self.turkish)
                == "Sırada 2 öneri satırı var. Fotoğraf ve videolar yazılmaz.")
        #expect(SuggestionCopy.note(remaining: 0, skippedMedia: 0, locale: Self.turkish) == nil)
        // The note ends with the next saved entry, whoever wrote it.
        model.advanceSuggestions(afterSending: nil)
        #expect(model.suggestionQueue == nil)
    }

    // MARK: - The moment's day

    /// A moment of the page's day sets the entry's time, as a calendar event does.
    @Test func momentOfTheDaySetsTheTime() async throws {
        let context = try TaskTestContext(sample: true)
        defer { context.clean() }
        await context.start()
        let day = CalendarDate("2026-10-01")!
        let today = context.today
        let model = QuickEntryModel(store: context.store, day: day, today: { today })
        let start = Self.date(day: 1, hour: 7, minute: 40, zone: .current)
        let pick = SuggestionPick(
            title: "", date: nil, items: [.workout(name: "Yüzme", duration: 1800, start: start)])
        // The entry's clock reads the device's zone; the pick is made in the same one.
        #expect(model.applySuggestion(pick, locale: Self.turkish, timeZone: .current))
        #expect(model.suggestionDay == nil)
        #expect(model.entryTime == (try LineClock(hour: 7, minute: 40)))
    }

    /// Yesterday's moment goes to yesterday's file at its own time, and the note over the field
    /// names that day before anything is written; today's file is not touched.
    @Test func anotherDaysMomentGoesToItsOwnDay() async throws {
        let context = try TaskTestContext(sample: true)
        defer { context.clean() }
        await context.start()
        let today = context.today
        let model = QuickEntryModel(store: context.store, day: today, today: { today })
        let start = Self.date(day: 2, hour: 7, minute: 40, zone: .current)
        let pick = SuggestionPick(
            title: "", date: nil, items: [.workout(name: "Yüzme", duration: 1800, start: start)])
        #expect(model.applySuggestion(pick, locale: Self.turkish, timeZone: .current))
        let yesterday = CalendarDate("2026-10-02")!
        #expect(model.suggestionDay == yesterday)
        #expect(model.entryTime == (try LineClock(hour: 7, minute: 40)))
        #expect(
            SuggestionCopy.note(
                day: model.suggestionDay, today: today, remaining: 0, skippedMedia: 0, locale: Self.turkish)
                == "2 Eki için.")
        #expect(await model.submit(time: model.entryTime))
        let bytes = try Data(contentsOf: context.root.appendingPathComponent("journal/2026-10-02.md"))
        let id = try #require(RawDocument(bytes: bytes).bodyLines.events.last?.block.id)
        let expected = "---\ntype: journal\ndate: 2026-10-02\n---\n\n## Events\n- 07:40 Yüzme 30 dk ^\(id)\n"
        #expect(bytes == Data(expected.utf8))
        #expect(!FileManager.default.fileExists(atPath: context.file.path))
        // What the user writes next is the page's again.
        #expect(model.suggestionDay == nil)
    }

    /// Emptying the field takes the day with it: what the user writes next is the page's.
    @Test func emptiedFieldForgetsTheMomentsDay() async throws {
        let context = try TaskTestContext(sample: true)
        defer { context.clean() }
        await context.start()
        let today = context.today
        let model = QuickEntryModel(store: context.store, day: today, today: { today })
        let start = Self.date(day: 2, hour: 7, minute: 40, zone: .current)
        let pick = SuggestionPick(
            title: "", date: nil, items: [.workout(name: "Yüzme", duration: 1800, start: start)])
        #expect(model.applySuggestion(pick, locale: Self.turkish, timeZone: .current))
        model.text = ""
        #expect(model.suggestionDay == nil)
        #expect(
            SuggestionCopy.note(
                day: model.suggestionDay, today: today, remaining: 0, skippedMedia: 0, locale: Self.turkish) == nil)
        model.text = "kendi notum"
        #expect(await model.submit(time: nil))
        #expect(FileManager.default.fileExists(atPath: context.file.path))
        let yesterday = context.root.appendingPathComponent("journal/2026-10-02.md")
        #expect(!FileManager.default.fileExists(atPath: yesterday.path))
    }

    // MARK: - Where the button shows

    #if os(iOS)
        /// iPad has the framework too; the picker stays an iPhone feature (a product decision).
        @Test func pickerIsOfferedOnAnIPhoneWithTheFrameworkOnly() {
            #expect(JournalingSuggestionsAvailability.current(idiom: .phone, frameworkPresent: true))
            #expect(!JournalingSuggestionsAvailability.current(idiom: .pad, frameworkPresent: true))
            #expect(!JournalingSuggestionsAvailability.current(idiom: .phone, frameworkPresent: false))
            // The simulator lacks the framework: the button never shows there.
            #expect(!JournalingSuggestionsAvailability.current())
        }
    #else
        @Test func macNeverOffersThePicker() {
            #expect(!JournalingSuggestionsAvailability.current())
        }
    #endif

    nonisolated private static func date(day: Int = 1, hour: Int, minute: Int, zone: TimeZone = zone) -> Date {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = zone
        return calendar.date(from: DateComponents(year: 2026, month: 10, day: day, hour: hour, minute: minute))!
    }
}
