import EntityRecognition
import Foundation
import Testing
import VaultFormat

@testable import Journal

@MainActor struct EntityInsightsTests {
    private let today = CalendarDate("2026-10-04")!
    @Test func samplePersonShowsLastEventCompanionsFirstDateAndFrequency() async throws {
        let context = try TaskTestContext(sample: true)
        defer { context.clean() }
        await context.start()
        let insight = try await Self.insight("people/Deniz Arıkan.md", context.store, today)
        #expect(insight.lastDay == CalendarDate("2026-09-25") && insight.firstDay == CalendarDate("2026-09-14"))
        #expect(insight.recentDayCount == 5 && insight.averageInterval == 2.75)
        #expect(insight.density.totalYearDays == 5)
        #expect(insight.density.busiestMonth == CalendarDate("2026-09-01"))
        #expect(insight.density.busiestMonthCount == 5)
        let mentions = try #require(insight.mentions(locale: Locale(identifier: "tr_TR")))
        #expect(mentions.totalDays == 5)
        #expect(mentions.busiestMonth == "Eylül")
        #expect(mentions.busiestCount == 5)
        #expect(mentions.spokenSummary == "Son 12 ayda 5 gün; en yoğun Eylül, 5 gün")
        #expect(mentions.recentIntervalText == "Son 90 günde 5 gün · ortalama aralık 2,8 gün")
        #expect(mentions.monthly.count == 12)
        #expect(mentions.recentDays.count == 90)
        #expect(insight.rows.count == 1)
        #expect(insight.rows.first?.text.plainText == "Deniz ve Mert ile öğle yemeği")
        #expect(insight.people.map(\.id) == ["people/Mert Aksu (iş).md"])
        #expect(insight.places.map(\.id) == ["places/Tepe Spor Salonu.md"])
        #expect(insight.rows.first?.text.spans.compactMap(\.destination).contains("people/Mert Aksu (iş).md") == true)
    }
    @Test func sameNameWorkPersonHasIndependentHistory() async throws {
        let context = try TaskTestContext(sample: true)
        defer { context.clean() }
        await context.start()
        let insight = try await Self.insight("people/Mert Aksu (iş).md", context.store, today)
        #expect(insight.firstDay == CalendarDate("2026-09-15") && insight.lastDay == CalendarDate("2026-09-25"))
        #expect(insight.recentDayCount == 2 && insight.averageInterval == 10)
        #expect(insight.people.map(\.id) == ["people/Deniz Arıkan.md"])
    }
    @Test func placeHasLastVisitAndSameDayPeople() async throws {
        let context = try TaskTestContext(sample: true)
        defer { context.clean() }
        await context.start()
        let insight = try await Self.insight("places/Tepe Spor Salonu.md", context.store, today)
        #expect(insight.firstDay == CalendarDate("2026-09-14") && insight.lastDay == CalendarDate("2026-09-25"))
        #expect(insight.recentDayCount == 6 && insight.averageInterval == 2.2)
        #expect(insight.rows.count == 2)
        #expect(insight.people.map(\.id) == ["people/Deniz Arıkan.md", "people/Mert Aksu (iş).md"])
        #expect(insight.places.isEmpty)
    }
    @Test func sampleUnseenThresholdChangesImmediatelyAndNeverIsSeparate() async throws {
        let context = try TaskTestContext(sample: true)
        defer { context.clean() }
        await context.start()
        var content = context.store.content
        content.entities.append(
            EntitySummary(
                id: "people/Never.md", kind: "person", name: "Selin Korkmaz",
                qualifier: "örnek", aliases: [], incomingLinks: 0))
        let encounters = try await context.store.computeLastEncounters(asOf: today)
        let groups = UnseenPeople.compute(
            people: content.entities, lastEncounters: encounters, today: today, threshold: 30)
        #expect(groups.overdue.isEmpty && groups.never.map(\.id) == ["people/Never.md"])
        let shorter = UnseenPeople.compute(
            people: content.entities, lastEncounters: encounters, today: today, threshold: 9)
        #expect(
            shorter.overdue.map(\.id) == [
                "people/Mert Aksu.md", "people/Selin Korkmaz.md", "people/Deniz Arıkan.md", "people/Mert Aksu (iş).md",
            ])
        #expect(shorter.overdue.map(\.elapsedDays) == [11, 11, 9, 9])
        #expect(shorter.never.count == 1)
        let filtered = UnseenPeople.compute(
            people: [content.entities.last!], lastEncounters: encounters, today: today, threshold: 1)
        #expect(filtered.overdue.isEmpty && filtered.never.count == 1)
    }
    @Test func ninetyDayWindowDeduplicatesDaysAndIgnoresFuture() throws {
        let path = "people/Deniz Arıkan.md"
        let first = today.addingDays(-90)!
        let boundary = today.addingDays(-89)!
        let timeline = [
            EntityTimelineDay(date: first, rows: []), EntityTimelineDay(date: boundary, rows: []),
            EntityTimelineDay(date: boundary, rows: []), EntityTimelineDay(date: today, rows: []),
            EntityTimelineDay(date: today.addingDays(1)!, rows: []),
        ]
        let insight = EntityInsights.compute(path: path, timeline: timeline, lastDay: nil, entities: [], today: today)
        #expect(insight.firstDay == first && insight.lastDay == today)
        #expect(insight.recentDayCount == 2 && insight.averageInterval == 89)
        let single = EntityInsights.compute(
            path: path, timeline: [EntityTimelineDay(date: today, rows: [])], lastDay: nil, entities: [],
            today: today.addingDays(89)!)
        #expect(single.recentDayCount == 1 && single.averageInterval == nil)
        let singleMentions = try #require(single.mentions(locale: Locale(identifier: "tr_TR")))
        #expect(singleMentions.recentIntervalText == "Son 90 günde 1 gün")

        let olderDay = today.addingDays(-400)!
        let older = EntityInsights.compute(
            path: path, timeline: [EntityTimelineDay(date: olderDay, rows: [])], lastDay: nil, entities: [],
            today: today)
        #expect(older.density.hasHistory)
        #expect(older.density.totalYearDays == 0)
        #expect(older.density.busiestMonth == nil)
        #expect(older.density.busiestMonthCount == 0)
        #expect(older.density.recentDayCount == 0)
        #expect(older.density.averageInterval == nil)
        let olderMentions = try #require(older.mentions(locale: Locale(identifier: "tr_TR")))
        #expect(olderMentions.totalDays == 0)
        #expect(olderMentions.busiestMonth == nil)
        #expect(olderMentions.busiestCount == 0)
        #expect(olderMentions.spokenSummary == "Son 12 ayda 0 gün")
        #expect(olderMentions.recentIntervalText == "Son 90 günde 0 gün")

        let empty = EntityInsights.compute(path: "unknown", timeline: [], lastDay: nil, entities: [], today: today)
        #expect(
            empty.firstDay == nil && empty.lastDay == nil && empty.averageInterval == nil && empty.recentDayCount == 0)
        #expect(empty.mentions(locale: Locale(identifier: "tr_TR")) == nil)
    }
    @Test func taskOnlyAndFutureMentionsDoNotChangeLastEncounter() async throws {
        let context = try TaskTestContext(sample: true)
        defer { context.clean() }
        try "## Tasks\n- [ ] [[Deniz Arıkan]]\n".write(
            to: context.root.appendingPathComponent("journal/2026-10-03.md"), atomically: true, encoding: .utf8)
        try "## Events\n- [[Deniz Arıkan]]\n".write(
            to: context.root.appendingPathComponent("journal/2026-10-05.md"), atomically: true, encoding: .utf8)
        await context.start()
        let insight = try await Self.insight("people/Deniz Arıkan.md", context.store, today)
        #expect(insight.lastDay == CalendarDate("2026-09-25") && insight.recentDayCount == 5)
    }
    /// The card's input as the entity page loads it: the queried timeline, the queried day of the
    /// last encounter, and the published entities.
    private static func insight(_ path: String, _ store: IndexStore, _ today: CalendarDate) async throws
        -> EntityInsights
    {
        let timeline = try await store.computeEntityTimeline(for: path)
        var lastDay: DaySummary?
        if let last = EntityInsights.lastDay(in: timeline, today: today) {
            lastDay = try await store.computeDay(on: last)
        }
        return EntityInsights.compute(
            path: path, timeline: timeline, lastDay: lastDay, entities: store.content.entities, today: today)
    }
    @Test func preferenceDefaultsAndClampsPersistedValues() throws {
        let defaults = try TestDefaults()
        defer { defaults.clean() }
        #expect(PeopleInsightsPreference.threshold(in: defaults.defaults) == 30)
        defaults.defaults.set(9, forKey: PeopleInsightsPreference.key)
        #expect(PeopleInsightsPreference.threshold(in: defaults.defaults) == 9)
        defaults.defaults.set(0, forKey: PeopleInsightsPreference.key)
        #expect(PeopleInsightsPreference.threshold(in: defaults.defaults) == 1)
        defaults.defaults.set(999, forKey: PeopleInsightsPreference.key)
        #expect(PeopleInsightsPreference.threshold(in: defaults.defaults) == 365)
    }
    @Test func mentionNavigationIsConsumedOnceAndAppendsPinnedPersonToDraft() async throws {
        let context = try TaskTestContext(sample: true)
        defer { context.clean() }
        await context.start()
        let person = try #require(context.store.content.entities.first { $0.id == "people/Mert Aksu (iş).md" })
        let navigation = IntentNavigation()
        navigation.mention(person, vault: context.store.vaultURL)
        #expect(navigation.todayRequest != nil)
        let selected = try #require(navigation.takeMention(vault: context.store.vaultURL))
        #expect(navigation.takeMention(vault: context.store.vaultURL) == nil)
        let model = context.model()
        model.text = "A draft"
        model.prefillMention(selected)
        #expect(model.text == "A draft @Mert Aksu ")
        let linked = try EntityRecognizer.linking(model.text, mentions: model.mentions, choices: model.choices)
        #expect(linked == "A draft [[Mert Aksu (iş)|Mert Aksu]] ")
        navigation.mention(person, vault: context.store.vaultURL)
        #expect(navigation.takeMention(vault: nil) == nil)
        navigation.mention(person, vault: context.store.vaultURL)
        navigation.openToday()
        #expect(navigation.mentionRequest == nil)
    }

    @Test func stripCellSizeAdaptsToWidthWithoutScaleDistortion() {
        // iPhone standard width (390 - 32 = 358 pt): (358 - 44) / 45 = 6.9777...
        let phoneCellSize = Entity90DayStrip.computeCellSize(availableWidth: 358, columns: 45)
        #expect(phoneCellSize < 7.0 && phoneCellSize > 6.95)

        // Wide layout (e.g. Mac sheet or column > 500 pt): caps at 8 pt
        let wideCellSize = Entity90DayStrip.computeCellSize(availableWidth: 600, columns: 45)
        #expect(wideCellSize == 8.0)

        // Narrow constraint clamps to lower bound 2 pt
        let narrowCellSize = Entity90DayStrip.computeCellSize(availableWidth: 50, columns: 45)
        #expect(narrowCellSize >= 2.0)
    }
}
