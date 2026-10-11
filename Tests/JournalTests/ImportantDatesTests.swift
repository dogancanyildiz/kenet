import Foundation
import Summaries
import Testing
import VaultFormat

@testable import Journal

@MainActor struct ImportantDatesTests {
    @Test func editingTheFieldReplacesTheLineAndAnotherVaultClearsIt() async throws {
        let context = try TaskTestContext(sample: true)
        defer { context.clean() }
        await context.start()
        let today = try #require(CalendarDate("2026-05-14"))
        let path = "people/Deniz Arıkan.md"
        let model = ImportantDatesModel(store: context.store)
        await model.load(today: today)
        let original = try #require(model.entries.first { $0.file == path && $0.key == "doğum günü" })
        #expect(original.daysUntil == 0 && original.year == 36 && original.date == today)

        try await context.store.setField(
            at: path, key: "doğum günü", value: .date(try #require(CalendarDate("1990-05-20"))))
        await model.load(today: today)
        let moved = try #require(model.entries.first { $0.file == path && $0.key == "doğum günü" })
        #expect(moved.date == CalendarDate("2026-05-20") && moved.daysUntil == 6 && moved.year == 36)
        #expect(model.entries.contains { $0.date == today && $0.file == path } == false)

        try await context.store.removeField(at: path, key: "doğum günü")
        await model.load(today: today)
        #expect(model.entries.contains { $0.file == path && $0.key == "doğum günü" } == false)
        #expect(model.hasLoaded)

        let other = context.directory.appendingPathComponent("Other")
        try FileManager.default.createDirectory(at: other, withIntermediateDirectories: true)
        await context.store.select(other)
        await model.load(today: today)
        #expect(model.entries.isEmpty && model.hasLoaded)
    }

    @Test func twoFieldsAreTwoRowsAndAPlaceIsIgnored() async throws {
        let context = try TaskTestContext(sample: true)
        defer { context.clean() }
        await context.start()
        let today = try #require(CalendarDate("2026-05-14"))
        let path = "people/Deniz Arıkan.md"
        try await context.store.setField(
            at: path, key: "yıldönümü", value: .date(try #require(CalendarDate("2010-05-15"))))
        try await context.store.setField(
            at: "places/Liman Ofis.md", key: "açılış", value: .date(try #require(CalendarDate("1990-05-14"))))
        let model = ImportantDatesModel(store: context.store)
        await model.load(today: today)
        let rows = model.entries.filter { $0.file == path }
        #expect(rows.map(\.key).sorted() == ["doğum günü", "yıldönümü"])
        #expect(rows.first { $0.key == "yıldönümü" }?.daysUntil == 1)
        #expect(model.entries.contains { $0.file.hasPrefix("places/") } == false)
    }

    /// 00:30 on 20 September in Auckland is still 19 September in UTC.
    @Test func aucklandMidnightKeepsItsOwnCalendarDay() async throws {
        let context = try TaskTestContext(sample: true)
        defer { context.clean() }
        await context.start()
        try await context.store.setField(
            at: "people/Deniz Arıkan.md", key: "doğum günü", value: .date(try #require(CalendarDate("1990-09-20"))))
        try await context.store.setField(
            at: "people/Selin Korkmaz.md", key: "doğum günü",
            value: .date(try #require(CalendarDate("1992-09-19"))))

        let zone = try #require(TimeZone(identifier: "Pacific/Auckland"))
        var utc = Calendar(identifier: .gregorian)
        utc.timeZone = try #require(TimeZone(identifier: "UTC"))
        let instant = try #require(
            utc.date(from: DateComponents(year: 2026, month: 9, day: 19, hour: 12, minute: 30)))
        let today = LocalDay.today(at: instant, timeZone: zone)
        #expect(today == CalendarDate("2026-09-20"))
        if TimeZone.current.identifier == zone.identifier {
            #expect(LocalDay.today(at: instant) == today)
        }

        let model = ImportantDatesModel(store: context.store)
        await model.load(today: today)
        #expect(model.entries.map(\.file) == ["people/Deniz Arıkan.md"])
        let text = ImportantDatePresentation(
            entry: try #require(model.entries.first), name: "Deniz Arıkan", locale: Locale(identifier: "en_US"),
            timeZone: zone)
        #expect(text.when == "Today" && text.caption == "doğum günü · 36 years")
    }

    @Test func theEntityPageKeepsTheNearestDateOutsideTheWindow() async throws {
        let context = try TaskTestContext(sample: true)
        defer { context.clean() }
        await context.start()
        let today = try #require(CalendarDate("2026-09-20"))
        let path = "people/Deniz Arıkan.md"
        let model = ImportantDatesModel(store: context.store)
        await model.load(today: today)
        #expect(model.nearest(file: path) == nil)
        await model.load(today: today, within: nil)
        let next = try #require(model.nearest(file: path))
        #expect(next.date == CalendarDate("2027-05-14") && next.year == 37 && next.key == "doğum günü")
    }

    @Test func textUsesPluralYearsAndCapsTheListAtThree() throws {
        let utc = try #require(TimeZone(secondsFromGMT: 0))
        let auckland = try #require(TimeZone(identifier: "Pacific/Auckland"))
        let day = try #require(CalendarDate("2026-09-22"))
        let many = ImportantDate(date: day, daysUntil: 2, year: 31, file: "people/Nila.md", key: "doğum günü")
        let english = ImportantDatePresentation(
            entry: many, name: "Nila", locale: Locale(identifier: "en_US"), timeZone: utc)
        #expect(english.when.contains("22") && english.caption == "doğum günü · 31 years")
        #expect(english.spoken == english.when + ", Nila, doğum günü · 31 years")
        let shifted = ImportantDatePresentation(
            entry: many, name: "Nila", locale: Locale(identifier: "en_US"), timeZone: auckland)
        #expect(shifted.when.contains("22"))
        let turkish = ImportantDatePresentation(
            entry: many, name: "Nila", locale: Locale(identifier: "tr_TR"), timeZone: utc)
        #expect(turkish.caption == "doğum günü · 31 yıl" && turkish.when.contains("22"))

        let today = ImportantDate(
            date: try #require(CalendarDate("2026-09-20")), daysUntil: 0, year: 1, file: "people/Vera.md",
            key: "doğum günü")
        let one = ImportantDatePresentation(
            entry: today, name: "Vera", locale: Locale(identifier: "en_US"), timeZone: utc)
        #expect(one.when == "Today" && one.caption == "doğum günü · 1 year")
        let tomorrow = ImportantDate(
            date: try #require(CalendarDate("2026-09-21")), daysUntil: 1, year: 16, file: "people/Nila.md",
            key: "tanışma")
        #expect(
            ImportantDatePresentation(
                entry: tomorrow, name: "Nila", locale: Locale(identifier: "tr_TR"), timeZone: utc
            ).when == "Yarın")

        #expect(ImportantDatePresentation.more(1, locale: Locale(identifier: "en_US")) == "and 1 more date")
        #expect(ImportantDatePresentation.more(2, locale: Locale(identifier: "en_US")) == "and 2 more dates")
        #expect(ImportantDatePresentation.more(1, locale: Locale(identifier: "tr_TR")) == "ve 1 tarih daha")

        var dates: [ImportantDate] = []
        for offset in 0..<4 {
            dates.append(
                ImportantDate(
                    date: try #require(day.addingDays(offset)), daysUntil: offset, year: 2,
                    file: "people/\(offset).md", key: "doğum günü"))
        }
        let parts = ImportantDateList.partition(dates)
        #expect(parts.shown.count == 3 && parts.extra == 1)

        let entity = EntityImportantDatePresentation(entry: many, locale: Locale(identifier: "en_US"), timeZone: utc)
        #expect(entity.line.contains("doğum günü") && entity.line.contains("22") && entity.line.hasSuffix("31 years"))
        let entityTurkish = EntityImportantDatePresentation(
            entry: many, locale: Locale(identifier: "tr_TR"), timeZone: utc)
        #expect(entityTurkish.line.hasSuffix("31 yıl") && entityTurkish.line.contains("22"))
    }
}
