import Foundation
import Summaries
import Testing
import VaultFormat
import VaultStore

@testable import Journal

/// The weekly review against real vault files: what it writes is compared byte for byte with
/// what it previewed, and everything else in the vault with what was there before.
@MainActor
struct WeeklyReviewTests {
    private static let todayFile =
        "---\ntype: journal\ndate: 2026-10-03\ngoals:\n  spor: true\n  kitap: 5\n---\n\n## Tasks\n"
        + "- [ ] bugünkü 📅 2026-10-03 ^o3\n- [ ] ileri tarihli 📅 2026-10-20 ^o4\n\n"
        + "## Events\n- 09:00 yürüyüş ^e9\n\n## Journal\nSakin bir gün.\n"

    /// Saturday 3 October 2026 is the review day. Sunday 27 September belongs to the reviewed
    /// week only on a Sunday calendar.
    private static let files: [String: String] = [
        "goals/Spor.md": "---\ntype: goal\nname: Spor\nkey: spor\nperiod: day\nkind: boolean\ntarget: 1\n---\n",
        "goals/Kitap.md":
            "---\ntype: goal\nname: Kitap\nkey: kitap\nperiod: week\nkind: number\ntarget: 100\nunit: sayfa\n---\n",
        "goals/Yil.md": "---\ntype: goal\nname: Yil\nkey: yil\nperiod: year\nkind: number\ntarget: 50\n---\n",
        "people/Ada Kurgu.md": "---\ntype: person\nname: Ada Kurgu\n---\n",
        "people/Bora Masal.md": "---\ntype: person\nname: Bora Masal\n---\n",
        "people/Cem Roman.md": "---\ntype: person\nname: Cem Roman\n---\n",
        "journal/2026-08-01.md": "## Events\n- 10:00 [[Ada Kurgu]] ile kahve ^e1\n",
        "journal/2026-09-20.md": "## Tasks\n- [ ] eski açık 📅 2026-09-20 ^o0\n\n## Events\n- 08:00 koşu ^e2\n",
        "journal/2026-09-27.md":
            "---\ntype: journal\ndate: 2026-09-27\ngoals:\n  spor: true\n  kitap: 10\n---\n\n## Tasks\n"
            + "- [x] pazar işi ✅ 2026-09-27 ^t1\n\n## Events\n- 11:00 pazar kahvaltısı ^e3\n",
        "journal/2026-09-28.md":
            "---\ntype: journal\ndate: 2026-09-28\ngoals:\n  spor: true\n  kitap: 20\n---\n\n## Tasks\n"
            + "- [x] pazartesi işi ✅ 2026-09-29 ^t2\n- [ ] açık bir 📅 2026-09-30 ^o1\n- [ ] açık iki ^o2\n\n"
            + "## Events\n- 09:00 toplantı ^e4\n- 13:00 [[Bora Masal]] ile öğle yemeği ^e5\n",
        "journal/2026-10-03.md": todayFile,
    ]

    private static let turkish = Locale(identifier: "tr_TR")
    private static let english = Locale(identifier: "en_US")

    /// The week start is the only thing the review takes from the calendar: a time zone a day
    /// away from the test process changes nothing.
    private static func calendar(firstWeekday: Int) -> Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.firstWeekday = firstWeekday
        calendar.timeZone = TimeZone(identifier: "Pacific/Kiritimati")!
        return calendar
    }

    private func write(_ files: [String: String], in context: TaskTestContext) async throws {
        for (path, text) in files {
            let url = context.root.appendingPathComponent(path)
            try FileManager.default.createDirectory(
                at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            try Data(text.utf8).write(to: url)
        }
        await context.store.refresh()
    }

    /// Every file under the vault root: bytes and modification date.
    private func vaultFiles(_ context: TaskTestContext) throws -> [String: ReviewVaultFile] {
        let root = context.root.resolvingSymlinksInPath()
        var result: [String: ReviewVaultFile] = [:]
        let keys: [URLResourceKey] = [.isRegularFileKey, .contentModificationDateKey]
        let found = try #require(FileManager.default.enumerator(at: root, includingPropertiesForKeys: keys))
        for case let url as URL in found {
            let values = try url.resourceValues(forKeys: Set(keys))
            guard values.isRegularFile == true else { continue }
            let path = String(url.resolvingSymlinksInPath().path.dropFirst(root.path.count + 1))
            result[path] = ReviewVaultFile(bytes: try Data(contentsOf: url), modified: values.contentModificationDate)
        }
        return result
    }

    private func context(_ files: [String: String] = WeeklyReviewTests.files) async throws -> TaskTestContext {
        let context = try TaskTestContext()
        await context.start()
        try await write(files, in: context)
        return context
    }

    private func model(
        _ context: TaskTestContext, firstWeekday: Int = 2, locale: Locale = WeeklyReviewTests.turkish,
        append: (@MainActor (CalendarDate, [String]) async throws -> Void)? = nil
    ) async -> WeeklyReviewModel {
        let model = WeeklyReviewModel(
            store: context.store, today: context.today, calendar: Self.calendar(firstWeekday: firstWeekday),
            locale: locale, defaults: context.defaults.defaults, append: append)
        await model.load()
        return model
    }

    /// The bytes the preview stands for in a file with this line ending: one empty line, then
    /// each previewed line.
    private func block(_ lines: [String], ending: String = "\n") -> Data {
        Data((ending + lines.map { $0 + ending }.joined()).utf8)
    }

    /// True when `after` is `before` with `inserted` put in at one place and nothing else changed.
    private func isInsertion(_ inserted: Data, into before: Data, giving after: Data) -> Bool {
        guard after.count == before.count + inserted.count else { return false }
        return (0...before.count).contains { before.prefix($0) + inserted + before.dropFirst($0) == after }
    }

    private func numbers(_ content: WeeklyReviewContent) -> [Int] {
        [content.events, content.completedTasks, content.writtenDays]
    }

    private func titleCount(_ data: Data, title: String = "### Haftalık inceleme") -> Int {
        String(decoding: data, as: UTF8.self).components(separatedBy: title).count - 1
    }

    // MARK: - Week

    @Test(arguments: [
        (2, "2026-10-03", ["2026-09-28", "2026-10-04", "2026-09-21", "2026-09-27"]),
        (1, "2026-10-03", ["2026-09-27", "2026-10-03", "2026-09-20", "2026-09-26"]),
        // A Sunday closes the Monday week and opens the Sunday week.
        (2, "2026-10-04", ["2026-09-28", "2026-10-04", "2026-09-21", "2026-09-27"]),
        (1, "2026-10-04", ["2026-10-04", "2026-10-10", "2026-09-27", "2026-10-03"]),
        (2, "2026-10-05", ["2026-10-05", "2026-10-11", "2026-09-28", "2026-10-04"]),
        // Across a year boundary.
        (2, "2027-01-01", ["2026-12-28", "2027-01-03", "2026-12-21", "2026-12-27"]),
        (1, "2027-01-01", ["2026-12-27", "2027-01-02", "2026-12-20", "2026-12-26"]),
    ])
    func weekFollowsTheCalendarsFirstWeekday(firstWeekday: Int, day: String, expected: [String]) throws {
        let today = try #require(CalendarDate(day))
        for zone in ["Pacific/Kiritimati", "Pacific/Pago_Pago", "UTC"] {
            var calendar = Calendar(identifier: .gregorian)
            calendar.firstWeekday = firstWeekday
            calendar.timeZone = try #require(TimeZone(identifier: zone))
            let current = WeeklyReviewWeek.current.range(containing: today, calendar: calendar)
            let previous = WeeklyReviewWeek.previous.range(containing: today, calendar: calendar)
            #expect(
                [current.lowerBound, current.upperBound, previous.lowerBound, previous.upperBound].map(\.description)
                    == expected, "\(zone)")
        }
    }

    @Test func theWeeksNumbersFollowTheCalendar() async throws {
        let context = try await context()
        defer { context.clean() }

        let monday = try #require(await model(context, firstWeekday: 2).content)
        #expect(monday.range == CalendarDate("2026-09-28")!...CalendarDate("2026-10-04")!)
        #expect(numbers(monday) == [3, 1, 2])
        // Due by the week's end or written in it undated; the later task is not this week's.
        #expect(monday.openTaskCount == 4 && monday.openTasks == ["eski açık", "açık bir", "bugünkü"])
        // Overdue only: seen this week and never seen are not listed.
        #expect(monday.people == ["Ada Kurgu"])
        // A daily goal is counted up to the review day; the yearly goal is not the week's business.
        #expect(
            monday.goals.map(\.standing) == [
                .amount(done: 25, target: 100, unit: "sayfa"), .days(met: 2, of: 6),
            ])
        #expect(monday.goals.map(\.name) == ["Kitap", "Spor"])

        let sunday = try #require(await model(context, firstWeekday: 1).content)
        #expect(sunday.range == CalendarDate("2026-09-27")!...CalendarDate("2026-10-03")!)
        #expect(numbers(sunday) == [4, 2, 3])
        // The weekly goal is counted over the reviewed days too (Sunday 27 to Saturday 3), not
        // over the goal's own Monday week, which would leave Sunday out.
        #expect(
            sunday.goals.map(\.standing) == [
                .amount(done: 35, target: 100, unit: "sayfa"), .days(met: 3, of: 7),
            ])

        let earlier = await model(context, firstWeekday: 2)
        earlier.week = .previous
        let previous = try #require(earlier.content)
        #expect(previous.range == CalendarDate("2026-09-21")!...CalendarDate("2026-09-27")!)
        #expect(numbers(previous) == [1, 1, 1])
        #expect(previous.openTaskCount == 1 && previous.openTasks == ["eski açık"])
        #expect(
            previous.goals.map(\.standing) == [
                .amount(done: 10, target: 100, unit: "sayfa"), .days(met: 1, of: 7),
            ])
        // The output still goes to the review day.
        #expect(earlier.today == context.today)
    }

    // MARK: - Sentences

    @Test func sentencesInBothLanguages() async throws {
        let context = try await context()
        defer { context.clean() }

        let turkish = await model(context, locale: Self.turkish)
        #expect(
            turkish.lines(for: .numbers) == [
                "Hafta: 2026-09-28 – 2026-10-04", "3 olay", "1 görev tamamlandı", "2 günde kayıt var",
            ])
        #expect(
            turkish.lines(for: .tasks) == [
                "4 görev açık", "Açık: eski açık", "Açık: açık bir", "Açık: bugünkü", "ve 1 görev daha",
            ])
        #expect(turkish.lines(for: .people) == ["Görüşmeyeli bir süre oldu: Ada Kurgu"])
        #expect(turkish.lines(for: .goals) == ["Kitap: 25 / 100 sayfa", "Spor: 2/6 gün"])
        #expect(turkish.previewLines.first == "### Haftalık inceleme")

        let english = await model(context, locale: Self.english)
        #expect(
            english.lines(for: .numbers) == [
                "Week: 2026-09-28 – 2026-10-04", "3 events", "1 task completed", "Entries on 2 days",
            ])
        #expect(
            english.lines(for: .tasks) == [
                "4 tasks open", "Open: eski açık", "Open: açık bir", "Open: bugünkü", "and 1 more task",
            ])
        #expect(english.lines(for: .people) == ["Not seen in a while: Ada Kurgu"])
        #expect(english.lines(for: .goals) == ["Kitap: 25 / 100 sayfa", "Spor: 2/6 days"])
        #expect(english.previewLines.first == "### Weekly review")
    }

    @Test func pluralsAndSilentZeros() throws {
        let range = CalendarDate("2026-09-28")!...CalendarDate("2026-10-04")!
        var one = WeeklyReviewContent(range: range)
        one.events = 1
        one.completedTasks = 1
        one.writtenDays = 1
        one.openTaskCount = 1
        one.openTasks = ["tek"]
        var many = WeeklyReviewContent(range: range)
        many.events = 5
        many.completedTasks = 3
        many.writtenDays = 4
        many.openTaskCount = 7
        many.openTasks = ["a", "b", "c"]
        #expect(
            Array(one.numberLines(locale: Self.english).dropFirst())
                == ["1 event", "1 task completed", "Entries on 1 day"])
        #expect(
            Array(many.numberLines(locale: Self.english).dropFirst())
                == ["5 events", "3 tasks completed", "Entries on 4 days"])
        #expect(one.taskLines(locale: Self.english) == ["1 task open", "Open: tek"])
        #expect(many.taskLines(locale: Self.english).last == "and 4 more tasks")
        #expect(many.taskLines(locale: Self.turkish).first == "7 görev açık")
        #expect(many.taskLines(locale: Self.turkish).last == "ve 4 görev daha")

        // A count of zero has no sentence, and a week without any count has no line at all.
        var partial = WeeklyReviewContent(range: range)
        partial.writtenDays = 2
        #expect(partial.numberLines(locale: Self.turkish) == ["Hafta: 2026-09-28 – 2026-10-04", "2 günde kayıt var"])
        let empty = WeeklyReviewContent(range: range)
        for locale in [Self.turkish, Self.english] {
            #expect(empty.numberLines(locale: locale).isEmpty && empty.taskLines(locale: locale).isEmpty)
            #expect(empty.peopleLines(locale: locale).isEmpty && empty.goalLines(locale: locale).isEmpty)
        }
    }

    /// The text goes into Journal as written, so a name must stay a name: no link syntax.
    @Test func peopleAreWrittenByNameWithoutLinkSyntax() async throws {
        let context = try await context()
        defer { context.clean() }
        let model = await model(context)
        for section in WeeklyReviewSection.allCases where section != .people { model.setIncluded(section, false) }
        #expect(model.previewLines == ["### Haftalık inceleme", "· Görüşmeyeli bir süre oldu: Ada Kurgu"])
        await model.write()
        let written = String(decoding: try Data(contentsOf: context.file), as: UTF8.self)
        #expect(written.contains("Ada Kurgu") && !written.contains("[[") && !written.contains("]]"))
    }

    // MARK: - Writing

    @Test func aMixedSelectionWritesExactlyThePreviewedLines() async throws {
        let context = try await context()
        defer { context.clean() }
        let before = try vaultFiles(context)
        let taskCount = try await context.store.allTasks().count
        let eventCount = try await context.store.days().reduce(0) { $0 + $1.events.count }

        let model = await model(context)
        model.setIncluded(.tasks, false)
        model.note = "İyi bir haftaydı.\n\n  İkinci satır  "
        let preview = model.previewLines
        #expect(
            preview == [
                "### Haftalık inceleme", "· Hafta: 2026-09-28 – 2026-10-04", "· 3 olay", "· 1 görev tamamlandı",
                "· 2 günde kayıt var", "· Görüşmeyeli bir süre oldu: Ada Kurgu", "· Kitap: 25 / 100 sayfa",
                "· Spor: 2/6 gün", "· İyi bir haftaydı.", "· İkinci satır",
            ])
        #expect(model.canWrite)
        await model.write()

        #expect(model.result == .written && model.errorText == nil)
        // The file is the old file with the previewed lines after it, and nothing else.
        let written = try Data(contentsOf: context.file)
        #expect(written == Data(Self.todayFile.utf8) + block(preview))
        var after = try vaultFiles(context)
        #expect(after.count == before.count)
        after["journal/2026-10-03.md"] = before["journal/2026-10-03.md"]
        #expect(after == before)

        // Read back, the block is Journal text: no task and no event came out of it.
        await context.store.refresh()
        #expect(try await context.store.allTasks().count == taskCount)
        #expect(try await context.store.days().reduce(0) { $0 + $1.events.count } == eventCount)
        // "Reviewed this week" lives on the device; the comparison above shows the vault has no mark.
        #expect(
            WeeklyReviewPreference.isReviewed(
                weekStarting: CalendarDate("2026-09-28")!, in: context.defaults.defaults))
        #expect(!model.canWrite)
    }

    @Test func aNoteAloneCreatesTheDayWithOnlyTheNote() async throws {
        var files = Self.files
        files["journal/2026-10-03.md"] = nil
        let context = try await context(files)
        defer { context.clean() }
        let before = try vaultFiles(context)
        #expect(before["journal/2026-10-03.md"] == nil)

        let model = await model(context)
        for section in WeeklyReviewSection.allCases { model.setIncluded(section, false) }
        model.note = "Yalnız bir not."
        #expect(model.previewLines == ["### Haftalık inceleme", "· Yalnız bir not."])
        await model.write()

        #expect(model.result == .written)
        let created = "---\ntype: journal\ndate: 2026-10-03\n---\n\n## Journal\n"
        #expect(try Data(contentsOf: context.file) == Data(created.utf8) + block(model.previewLines))
        var after = try vaultFiles(context)
        after["journal/2026-10-03.md"] = nil
        #expect(after == before)
    }

    @Test func nothingSelectedWritesNoFile() async throws {
        var files = Self.files
        files["journal/2026-10-03.md"] = nil
        let context = try await context(files)
        defer { context.clean() }
        let before = try vaultFiles(context)

        let model = await model(context)
        for section in WeeklyReviewSection.allCases { model.setIncluded(section, false) }
        model.note = " \n\t\n"
        #expect(model.previewLines.isEmpty && !model.canWrite)
        await model.write()

        #expect(model.result == nil)
        #expect(!FileManager.default.fileExists(atPath: context.file.path))
        #expect(try vaultFiles(context) == before)
        #expect(
            !WeeklyReviewPreference.isReviewed(
                weekStarting: CalendarDate("2026-09-28")!, in: context.defaults.defaults))
    }

    @Test func leavingWithoutWritingTouchesNoFile() async throws {
        var files = Self.files
        files["journal/2026-10-03.md"] = nil
        let context = try await context(files)
        defer { context.clean() }
        let before = try vaultFiles(context)

        // Every step, both weeks, choices changed back and forth, a note typed: then "Vazgeç".
        let model = await model(context)
        model.week = .previous
        model.week = .current
        for _ in WeeklyReviewStep.allCases { model.advance() }
        #expect(model.step == .preview)
        model.setIncluded(.goals, false)
        model.note = "yazıldı ama gönderilmedi"
        #expect(model.canWrite && !model.previewLines.isEmpty)
        for _ in WeeklyReviewStep.allCases { model.back() }
        #expect(model.step == .numbers)
        await model.load()

        #expect(model.result == nil)
        #expect(!FileManager.default.fileExists(atPath: context.file.path))
        #expect(try vaultFiles(context) == before)
    }

    /// BOM, CRLF, a task with its note, blank lines at the end of Journal and a section after
    /// it: every one of those bytes stays, and the block takes the file's line ending.
    @Test func existingBytesStayAlsoInACarriageReturnFile() async throws {
        var files = Self.files
        let journal = "## Journal\r\nİlk paragraf.\r\n\r\n- madde\r\n"
        let rest = "\r\n\r\n## Notlar\r\nsonda satır sonu yok"
        let source =
            "\u{FEFF}## Tasks\r\n- [ ] bugünkü 📅 2026-10-03 ^o3\r\n  alt not\r\n\r\n## Events\r\n- 09:00 yürüyüş ^e9\r\n\r\n"
            + journal + rest
        files["journal/2026-10-03.md"] = source
        let context = try await context(files)
        defer { context.clean() }
        let before = try Data(contentsOf: context.file)

        let model = await model(context)
        model.note = "CRLF dosyaya not"
        let preview = model.previewLines
        await model.write()

        #expect(model.result == .written)
        let after = try Data(contentsOf: context.file)
        #expect(isInsertion(block(preview, ending: "\r\n"), into: before, giving: after))
        // Below Journal's last line, above its trailing blank lines and the next section.
        let head = String(source.dropLast(rest.count))
        #expect(after == Data(head.utf8) + block(preview, ending: "\r\n") + Data(rest.utf8))
    }

    /// What the user types is text. Read back from the file it is still no task, no event and
    /// no section, whatever it looks like.
    @Test func aNoteThatLooksLikeStructureAddsNoRecord() async throws {
        let context = try await context()
        defer { context.clean() }
        let document = RawDocument(bytes: try Data(contentsOf: context.file))
        let tasks = document.bodyLines.tasks.count
        let events = document.bodyLines.events.count
        let indexedTasks = try await context.store.allTasks().count

        let model = await model(context)
        for section in WeeklyReviewSection.allCases { model.setIncluded(section, false) }
        model.note =
            "- [ ] süt\n- 09:30 toplantı\n## Tasks\n- [x] bitti ✅ 2026-10-03\n```\n> - [ ] alıntı\n%% yorum\n"
            + "<!-- yorum\n# Başlık\n\t- [ ] girintili"
        let preview = model.previewLines
        #expect(preview.count == 11 && preview.dropFirst().allSatisfy { $0.hasPrefix("· ") })
        await model.write()

        #expect(model.result == .written)
        let written = try Data(contentsOf: context.file)
        #expect(written == Data(Self.todayFile.utf8) + block(preview))
        let reread = RawDocument(bytes: written)
        #expect(reread.bodyLines.tasks.count == tasks && reread.bodyLines.events.count == events)
        // Every line stays in Journal: no heading in the note opened a section of its own.
        #expect(journalHolds(preview, in: reread))
        await context.store.refresh()
        #expect(try await context.store.allTasks().count == indexedTasks)
        #expect(try await !context.store.allTasks().contains { $0.sourceText.contains("süt") })
        #expect(try await context.store.computeDay(on: context.today).events.count == events)
    }

    @Test func twoReviewsAreTwoBlocks() async throws {
        let context = try await context()
        defer { context.clean() }

        let first = await model(context)
        first.note = "birinci"
        let firstPreview = first.previewLines
        await first.write()
        let once = try Data(contentsOf: context.file)
        #expect(once == Data(Self.todayFile.utf8) + block(firstPreview))

        // The flow gone through again: a second block under the first, which keeps its bytes.
        let second = await model(context)
        second.note = "ikinci"
        let secondPreview = second.previewLines
        await second.write()
        let twice = try Data(contentsOf: context.file)
        #expect(twice == once + block(secondPreview))
        #expect(titleCount(twice) == 2)
    }

    /// "Günlüğe yaz" pressed twice in one pass writes once: the second press finds the first
    /// still writing, and a press after it finds the review written.
    @Test func writingTwiceAtOnceWritesOnce() async throws {
        let context = try await context()
        defer { context.clean() }
        let model = await model(context)
        model.note = "bir kez"
        let preview = model.previewLines
        #expect(model.canClose)

        async let first: Void = model.write()
        async let second: Void = model.write()
        _ = await (first, second)
        await model.write()

        #expect(model.result == .written && model.canClose && !model.isWriting)
        let written = try Data(contentsOf: context.file)
        #expect(written == Data(Self.todayFile.utf8) + block(preview))
        #expect(titleCount(written) == 1)
    }

    // MARK: - Refusals

    /// Journal sits inside a code fence that never closes: text added there would be code.
    @Test func anUnclosedCodeFenceRefusesTheWriteAndSaysWhy() async throws {
        var files = Self.files
        let source = "## Events\n- 09:00 yürüyüş ^e9\n\n```\nkapanmayan çit\n\n## Journal\nSakin bir gün.\n"
        files["journal/2026-10-03.md"] = source
        let context = try await context(files)
        defer { context.clean() }
        let before = try vaultFiles(context)

        let model = await model(context)
        model.note = "yazılamayacak"
        await model.write()

        #expect(model.result == nil)
        #expect(model.errorText == WeeklyReviewModel.message(for: EditError.sectionNotWritable, locale: Self.turkish))
        #expect(try vaultFiles(context) == before)
        // Nothing was written, so asking again is allowed.
        #expect(model.canWrite && model.canClose)
        #expect(
            !WeeklyReviewPreference.isReviewed(
                weekStarting: CalendarDate("2026-09-28")!, in: context.defaults.defaults))
    }

    @Test func aFileThatIsNotTextIsLeftAlone() async throws {
        let context = try await context()
        defer { context.clean() }
        try Data([0x23, 0x23, 0x20, 0xFF, 0xFE, 0x0A]).write(to: context.file)
        await context.store.refresh()
        let before = try vaultFiles(context)

        let model = await model(context)
        model.note = "yazılamayacak"
        await model.write()

        #expect(model.result == nil)
        #expect(model.errorText == WeeklyReviewModel.message(for: EditError.readOnlyDocument, locale: Self.turkish))
        #expect(try vaultFiles(context) == before)
    }

    @Test func aReadOnlyVaultIsNotWritten() async throws {
        let context = try TaskTestContext()
        defer { context.clean() }
        var files = Self.files
        // A format newer than this build: the vault opens read-only.
        files[".app/vault.json"] = "{ \"formatVersion\": 2 }\n"
        for (path, text) in files {
            let url = context.root.appendingPathComponent(path)
            try FileManager.default.createDirectory(
                at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            try Data(text.utf8).write(to: url)
        }
        await context.start()
        #expect(context.store.isVaultReadOnly)
        let before = try vaultFiles(context)

        let model = await model(context)
        model.note = "yazılamayacak"
        // The week can still be looked at; only the write is closed, and the reason is given.
        #expect(model.content?.events == 3 && !model.previewLines.isEmpty)
        #expect(!model.canWrite)
        #expect(
            model.blockedText == WeeklyReviewModel.message(for: VaultStoreError.readOnlyVault, locale: Self.turkish))
        await model.write()

        #expect(model.result == nil)
        #expect(try vaultFiles(context) == before)
    }

    /// The file holds the text and only the index did not follow: the review counts as written
    /// and a second press must not add the block again.
    @Test func aFailedIndexUpdateIsNotWrittenAgain() async throws {
        let context = try await context()
        defer { context.clean() }
        let store = context.store
        let model = await model(context) { day, lines in
            try await store.appendToJournal(on: day, lines: lines)
            throw VaultStoreError.indexUpdateFailed(
                path: "journal/\(day).md", underlying: CocoaError(.fileWriteUnknown))
        }
        model.note = "indeks geride kaldı"
        let preview = model.previewLines
        await model.write()

        #expect(model.result == .writtenWithoutIndex && model.errorText == nil && !model.canWrite)
        await model.write()
        let written = try Data(contentsOf: context.file)
        #expect(written == Data(Self.todayFile.utf8) + block(preview))
        #expect(
            WeeklyReviewPreference.isReviewed(
                weekStarting: CalendarDate("2026-09-28")!, in: context.defaults.defaults))
    }

    @Test func aFileChangedOutsideIsReportedAndCanBeTriedAgain() async throws {
        let context = try await context()
        defer { context.clean() }
        let before = try vaultFiles(context)
        let model = await model(context) { _, _ in throw VaultStoreError.staleTarget }
        model.note = "sonra"
        await model.write()

        #expect(model.result == nil && model.canWrite)
        #expect(model.errorText == DayEditError.message(for: VaultStoreError.staleTarget))
        #expect(try vaultFiles(context) == before)
    }

    @Test func everyRefusalHasItsOwnSentenceInBothLanguages() {
        let errors: [any Error] = [
            EditError.sectionNotWritable, EditError.readOnlyDocument, VaultStoreError.readOnlyVault,
        ]
        let turkish = errors.map { WeeklyReviewModel.message(for: $0, locale: Self.turkish) }
        let english = errors.map { WeeklyReviewModel.message(for: $0, locale: Self.english) }
        #expect(Set(turkish).count == 3 && Set(english).count == 3)
        #expect(Set(turkish).isDisjoint(with: english))
        // A structure refusal from the writer reads the same as one from the section check.
        #expect(
            WeeklyReviewModel.message(for: EditError.contentNotRepresentable, locale: Self.english) == english[0])
        #expect(WeeklyReviewNotice(.written, locale: Self.english).kind == .info)
        #expect(WeeklyReviewNotice(.writtenWithoutIndex, locale: Self.english).kind == .warning)
        #expect(
            WeeklyReviewNotice(.written, locale: Self.english).text
                != WeeklyReviewNotice(.writtenWithoutIndex, locale: Self.english).text)
    }

    // MARK: - Same numbers as Özetler

    /// Özetler counts Core's Monday week. On a Monday calendar the review's week is that week,
    /// so the same vault must give the same three numbers on both screens: the sample vault on
    /// four days, and this suite's vault with a task finished in a later week than it was written.
    @Test(arguments: [
        (true, "2026-09-14"), (true, "2026-09-20"), (true, "2026-09-23"), (true, "2026-09-27"), (false, "2026-10-03"),
    ])
    func onAMondayCalendarTheNumbersAreTheSummarysNumbers(sample: Bool, day: String) async throws {
        let context: TaskTestContext
        if sample {
            context = try TaskTestContext(sample: true)
            await context.start()
        } else {
            var files = Self.files
            files["journal/2026-09-20.md"] =
                "## Tasks\n- [ ] eski açık 📅 2026-09-20 ^o0\n- [x] geç biten ✅ 2026-09-29 ^t3\n\n"
                + "## Events\n- 08:00 koşu ^e2\n"
            context = try await self.context(files)
        }
        defer { context.clean() }
        let today = try #require(CalendarDate(day))

        for week in [WeeklyReviewWeek.current, .previous] {
            let model = WeeklyReviewModel(
                store: context.store, today: today, calendar: Self.calendar(firstWeekday: 2), locale: Self.english,
                defaults: context.defaults.defaults)
            model.week = week
            await model.load()
            let content = try #require(model.content)
            let summary = try await context.store.periodSummary(.week, containing: content.range.lowerBound)
            #expect(content.range == summary.range, "\(day) \(week)")
            #expect(
                numbers(content)
                    == [summary.counts.events, summary.counts.completedTasks, summary.counts.writtenDays],
                "\(day) \(week)")
            // The weeks are not empty: the comparison is not between two zeros.
            if week == .current { #expect(content.events > 0 && content.completedTasks > 0) }
        }
    }

    // MARK: - People

    /// The sample vault has two people named "Mert Aksu"; written as a plain name they could
    /// not be told apart, so the qualifier goes with the name (as in Özetler).
    @Test func aQualifierTellsTwoPeopleWithOneNameApart() {
        func person(_ id: String, _ qualifier: String?) -> UnseenPerson {
            UnseenPerson(
                entity: EntitySummary(
                    id: id, kind: "person", name: "Mert Aksu", qualifier: qualifier, aliases: [], incomingLinks: 0),
                lastDay: CalendarDate("2026-08-01"), elapsedDays: 63, overdueDays: 33)
        }
        let range = CalendarDate("2026-09-28")!...CalendarDate("2026-10-04")!
        let content = WeeklyReviewContent.compute(
            range: range, today: CalendarDate("2026-10-03")!, input: SummaryInput(), tasks: [],
            unseen: [person("people/Mert Aksu (iş).md", "iş"), person("people/Mert Aksu.md", nil)])
        #expect(content.people == ["Mert Aksu (iş)", "Mert Aksu"])
        #expect(content.peopleLines(locale: Self.english) == ["Not seen in a while: Mert Aksu (iş), Mert Aksu"])
    }

    // MARK: - Unusual day files

    /// Day files as people leave them. Each one takes the previewed lines as one inserted piece
    /// inside Journal, keeping every other byte, or (`nil`) is refused with nothing written.
    @Test(
        arguments: [
            // Journal with a section after it, LF.
            ("## Journal\nMetin.\n\n## Notlar\nalt\n", "## Journal\nMetin.\n\n{block}\n\n## Notlar\nalt\n"),
            // Empty Journal at the end.
            ("## Events\n- 09:00 yürüyüş\n\n## Journal\n", "## Events\n- 09:00 yürüyüş\n\n## Journal\n\n{block}\n"),
            // Frontmatter alone: Journal is added after it.
            (
                "---\ntype: journal\ndate: 2026-10-03\n---\n",
                "---\ntype: journal\ndate: 2026-10-03\n---\n\n## Journal\n\n{block}\n"
            ),
            // Old Mac line endings: the block takes them.
            ("## Journal\rMetin.\r", "## Journal\rMetin.\r\r{block}\r"),
            // An empty file.
            ("", "## Journal\n\n{block}\n"),
            // The last line has no line ending.
            ("## Journal\nMetin.", "## Journal\nMetin.\n\n{block}\n"),
            // Frontmatter that never closes is body text.
            ("---\ntype: journal\n## Journal\nMetin.\n", "---\ntype: journal\n## Journal\nMetin.\n\n{block}\n"),
            // Journal ends inside a code fence that never closes: the text would be code.
            ("## Journal\nMetin.\n```\n## Notlar\n", nil),
        ] as [(String, String?)])
    func unusualDayFilesKeepTheirBytes(source: String, expected: String?) async throws {
        var files = Self.files
        files["journal/2026-10-03.md"] = source
        let context = try await context(files)
        defer { context.clean() }
        let before = try vaultFiles(context)
        let original = try Data(contentsOf: context.file)

        let model = await model(context)
        for section in WeeklyReviewSection.allCases { model.setIncluded(section, false) }
        model.note = "düşman biçim\n- [ ] süt"
        let preview = model.previewLines
        #expect(preview == ["### Haftalık inceleme", "· düşman biçim", "· - [ ] süt"])
        await model.write()

        guard let expected else {
            #expect(model.result == nil && model.canWrite)
            #expect(
                model.errorText == WeeklyReviewModel.message(for: EditError.sectionNotWritable, locale: Self.turkish))
            #expect(try vaultFiles(context) == before)
            return
        }
        let after = try Data(contentsOf: context.file)
        let ending = source.contains("\r") ? "\r" : "\n"
        #expect(model.result == .written)
        #expect(
            after == Data(expected.replacingOccurrences(of: "{block}", with: preview.joined(separator: ending)).utf8))
        #expect(isOneInsertion(into: original, giving: after))
        // The block reads back as Journal text, in order, and adds no task or event.
        let document = RawDocument(bytes: after)
        #expect(journalHolds(preview, in: document))
        let old = RawDocument(bytes: original)
        #expect(document.bodyLines.tasks.count == old.bodyLines.tasks.count)
        #expect(document.bodyLines.events.count == old.bodyLines.events.count)
        var rest = try vaultFiles(context)
        rest["journal/2026-10-03.md"] = before["journal/2026-10-03.md"]
        #expect(rest == before)
    }

    /// True when the lines stand one after another inside the document's Journal section.
    private func journalHolds(_ lines: [String], in document: RawDocument) -> Bool {
        guard let journal = document.daySections.section(.journal) else { return false }
        let texts = journal.lineRange.map { document.lines[$0].text ?? "" }
        guard texts.count >= lines.count else { return false }
        return (0...(texts.count - lines.count)).contains { Array(texts[$0..<($0 + lines.count)]) == lines }
    }

    /// True when `after` is `before` with one piece put in somewhere and no byte of it changed.
    private func isOneInsertion(into before: Data, giving after: Data) -> Bool {
        guard after.count > before.count else { return false }
        let old = [UInt8](before)
        let new = [UInt8](after)
        var prefix = 0
        while prefix < old.count && old[prefix] == new[prefix] { prefix += 1 }
        let tail = old.count - prefix
        return Array(old[prefix...]) == Array(new[(new.count - tail)...])
    }

    // MARK: - Steps

    @Test func aStepThatAddsNothingIsSkipped() async throws {
        let context = try await context()
        defer { context.clean() }
        let model = await model(context)
        #expect(WeeklyReviewStep.allCases.dropLast().allSatisfy { !model.isSkipped($0) || $0 == .note })
        #expect(model.isSkipped(.note))
        model.note = "bir şey"
        #expect(!model.isSkipped(.note))
        model.setIncluded(.goals, false)
        #expect(model.isSkipped(.goals) && !model.isIncluded(.goals))
        #expect(!model.previewLines.contains { $0.contains("Spor") })
        model.setIncluded(.goals, true)
        #expect(model.previewLines.contains("· Spor: 2/6 gün"))

        #expect(model.step == .numbers)
        model.back()
        #expect(model.step == .numbers)
        for step in WeeklyReviewStep.allCases.dropFirst() {
            model.advance()
            #expect(model.step == step)
        }
        model.advance()
        #expect(model.step == .preview)
    }
}

private struct ReviewVaultFile: Equatable {
    let bytes: Data
    let modified: Date?
}
