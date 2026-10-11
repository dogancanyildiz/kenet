import Foundation
import Summaries
import Testing
import VaultFormat

@testable import Journal

@MainActor struct OnThisDayTests {
    private static func writeDay(_ date: String, events: String, in root: URL) throws {
        let text = "---\ntype: journal\ndate: \(date)\n---\n\n## Tasks\n\n## Events\n\(events)\n## Journal\n"
        try text.write(
            to: root.appendingPathComponent("journal/\(date).md"), atomically: true, encoding: .utf8)
    }

    @Test func lineComesFromTheIndexAndOnlyForALinkedPastYear() async throws {
        let context = try TaskTestContext(sample: true)
        defer { context.clean() }
        try Self.writeDay(
            "2025-09-20", events: "- 10:00 [[Deniz Arıkan]] ile [[Çınaraltı Kafe]]'de kahve\n", in: context.root)
        try Self.writeDay("2024-09-20", events: "- 09:00 [[Ece Yalın]] ile yürüyüş\n", in: context.root)
        try Self.writeDay("2025-09-21", events: "- 11:00 [[Okuma Listesi]] güncellendi\n", in: context.root)
        await context.start()
        let model = OnThisDayModel(store: context.store)
        #expect(model.entry == nil && !model.hasLoaded)

        await model.load(today: try #require(CalendarDate("2026-09-20")))
        #expect(
            model.entry
                == OnThisDay(
                    day: try #require(CalendarDate("2025-09-20")),
                    people: [.init(id: "people/Deniz Arıkan.md", name: "Deniz Arıkan")],
                    place: .init(id: "places/Çınaraltı Kafe.md", name: "Çınaraltı Kafe"), otherYears: 1))
        #expect(model.hasLoaded)

        // The sample vault links people on 21 September 2026 itself; last year's file links none.
        await model.load(today: try #require(CalendarDate("2026-09-21")))
        #expect(model.entry == nil && model.hasLoaded)
    }

    /// 00:30 on 20 September in Auckland is still 19 September in UTC and in Istanbul.
    @Test func aucklandMidnightKeepsItsOwnCalendarDay() async throws {
        let context = try TaskTestContext(sample: true)
        defer { context.clean() }
        try Self.writeDay("2025-09-19", events: "- 10:00 [[Baran Tunç]] ile toplantı\n", in: context.root)
        try Self.writeDay("2025-09-20", events: "- 10:00 [[Deniz Arıkan]] ile kahve\n", in: context.root)
        await context.start()

        let zone = try #require(TimeZone(identifier: "Pacific/Auckland"))
        var utc = Calendar(identifier: .gregorian)
        utc.timeZone = try #require(TimeZone(identifier: "UTC"))
        let instant = try #require(
            utc.date(from: DateComponents(year: 2026, month: 9, day: 19, hour: 12, minute: 30)))
        let today = LocalDay.today(at: instant, timeZone: zone)
        #expect(today == CalendarDate("2026-09-20"))
        // CI repeats the Mac suite with TZ=Pacific/Auckland; there the default zone must agree.
        if TimeZone.current.identifier == zone.identifier {
            #expect(LocalDay.today(at: instant) == today)
        }

        let model = OnThisDayModel(store: context.store)
        await model.load(today: today)
        let entry = try #require(model.entry)
        #expect(entry.day == CalendarDate("2025-09-20"))
        #expect(entry.people.map(\.name) == ["Deniz Arıkan"])
        let text = OnThisDayPresentation(entry: entry, today: today, locale: Locale(identifier: "en_US"))
        #expect(text.year == "2025" && text.caption == "1 year ago today")
    }

    @Test func anotherVaultNeverKeepsThePreviousLine() async throws {
        let context = try TaskTestContext(sample: true)
        defer { context.clean() }
        try Self.writeDay("2025-09-20", events: "- 10:00 [[Deniz Arıkan]] ile kahve\n", in: context.root)
        await context.start()
        let today = try #require(CalendarDate("2026-09-20"))
        let model = OnThisDayModel(store: context.store)
        await model.load(today: today)
        #expect(model.entry != nil)

        let other = context.directory.appendingPathComponent("Other")
        try FileManager.default.createDirectory(at: other, withIntermediateDirectories: true)
        await context.store.select(other)
        #expect(context.store.vaultURL?.lastPathComponent == "Other")
        await model.load(today: today)
        #expect(model.entry == nil && model.hasLoaded)
    }

    @Test func textNamesTwoPeopleOnePlaceAndTheOtherYears() throws {
        let today = try #require(CalendarDate("2026-09-20"))
        let full = OnThisDay(
            day: try #require(CalendarDate("2023-09-20")),
            people: [
                .init(id: "people/Deniz Arıkan.md", name: "Deniz Arıkan"),
                .init(id: "people/Selin Korkmaz.md", name: "Selin Korkmaz"),
            ], place: .init(id: "places/Ev.md", name: "Ev"), otherYears: 2)
        let turkish = OnThisDayPresentation(entry: full, today: today, locale: Locale(identifier: "tr_TR"))
        #expect(turkish.year == "2023")
        #expect(turkish.names == "Deniz Arıkan ve Selin Korkmaz · Ev")
        #expect(turkish.caption == "3 yıl önce bugün · ve 2 yıl daha")
        #expect(turkish.spoken == "3 yıl önce bugün · ve 2 yıl daha, Deniz Arıkan ve Selin Korkmaz · Ev")
        let english = OnThisDayPresentation(entry: full, today: today, locale: Locale(identifier: "en_US"))
        #expect(english.names == "Deniz Arıkan and Selin Korkmaz · Ev")
        #expect(english.caption == "3 years ago today · and 2 more years")

        let place = OnThisDay(
            day: try #require(CalendarDate("2025-09-20")), people: [],
            place: .init(id: "places/Ev.md", name: "Ev"), otherYears: 1)
        let single = OnThisDayPresentation(entry: place, today: today, locale: Locale(identifier: "en_US"))
        #expect(single.names == "Ev")
        #expect(single.caption == "1 year ago today · and 1 more year")
    }
}

#if os(macOS)
    import SwiftUI

    /// The mounted page itself: Today loads its context, a past day's page never does.
    @MainActor @Suite(.timeLimit(.minutes(1)))
    struct DayContextMountTests {
        private let watchdog = HostedTestWatchdog()

        @Test(arguments: [true, false])
        func onlyTodayMountsTheContextArea(isToday: Bool) async throws {
            let context = try TaskTestContext(sample: true)
            defer { context.clean() }
            await context.start()
            let day = try #require(CalendarDate("2026-09-20"))
            let defaults = context.defaults.defaults
            let ready = ReadyBox()
            let page = NavigationStack {
                DayView(store: context.store, date: day, isToday: isToday)
            }
            .environment(NotificationService(center: FakeNotificationCenter(), defaults: defaults))
            .environment(CalendarService(source: SilentCalendarSource()))
            .environment(LocationService(source: FakeLocationSource(), defaults: defaults))
            .onPreferenceChange(DayContextReadyKey.self) { ready.isReady = $0 }
            let mount = HostedLayout.Mount(page, size: CGSize(width: 720, height: 900))
            defer { mount.close() }
            for _ in 0..<20 where !ready.isReady { await mount.settle() }
            #expect(ready.isReady == isToday)
        }
    }

    @MainActor private final class ReadyBox {
        var isReady = false
    }

    @MainActor private final class SilentCalendarSource: CalendarEventSource {
        var authorization = CalendarAuthorization.denied
        var onChange: (@MainActor @Sendable () -> Void)?
        func requestFullAccess() async throws -> Bool { false }
        func events(from start: Date, to end: Date) async throws -> [CalendarEvent] { [] }
    }
#endif
