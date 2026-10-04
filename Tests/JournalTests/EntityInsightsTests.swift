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
        let insight = EntityInsights.compute(
            path: "people/Deniz Arıkan.md", content: context.store.content, today: today)
        #expect(insight.lastDay == CalendarDate("2026-09-25") && insight.firstDay == CalendarDate("2026-09-14"))
        #expect(insight.recentDayCount == 5 && insight.averageInterval == 2.75)
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
        let insight = EntityInsights.compute(
            path: "people/Mert Aksu (iş).md", content: context.store.content, today: today)
        #expect(insight.firstDay == CalendarDate("2026-09-15") && insight.lastDay == CalendarDate("2026-09-25"))
        #expect(insight.recentDayCount == 2 && insight.averageInterval == 10)
        #expect(insight.people.map(\.id) == ["people/Deniz Arıkan.md"])
    }
    @Test func placeHasLastVisitAndSameDayPeople() async throws {
        let context = try TaskTestContext(sample: true)
        defer { context.clean() }
        await context.start()
        let insight = EntityInsights.compute(
            path: "places/Tepe Spor Salonu.md", content: context.store.content, today: today)
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
        let groups = UnseenPeople.compute(people: content.entities, content: content, today: today, threshold: 30)
        #expect(groups.overdue.isEmpty && groups.never.map(\.id) == ["people/Never.md"])
        let shorter = UnseenPeople.compute(people: content.entities, content: content, today: today, threshold: 9)
        #expect(
            shorter.overdue.map(\.id) == [
                "people/Mert Aksu.md", "people/Selin Korkmaz.md", "people/Deniz Arıkan.md", "people/Mert Aksu (iş).md",
            ])
        #expect(shorter.overdue.map(\.elapsedDays) == [11, 11, 9, 9])
        #expect(shorter.never.count == 1)
        let filtered = UnseenPeople.compute(
            people: [content.entities.last!], content: content, today: today, threshold: 1)
        #expect(filtered.overdue.isEmpty && filtered.never.count == 1)
    }
    @Test func ninetyDayWindowDeduplicatesDaysAndIgnoresFuture() {
        let path = "people/Deniz Arıkan.md"
        var content = VaultReadModel()
        let first = today.addingDays(-90)!
        let boundary = today.addingDays(-89)!
        content.entityTimeline[path] = [
            EntityTimelineDay(date: first, rows: []), EntityTimelineDay(date: boundary, rows: []),
            EntityTimelineDay(date: boundary, rows: []), EntityTimelineDay(date: today, rows: []),
            EntityTimelineDay(date: today.addingDays(1)!, rows: []),
        ]
        let insight = EntityInsights.compute(path: path, content: content, today: today)
        #expect(insight.firstDay == first && insight.lastDay == today)
        #expect(insight.recentDayCount == 2 && insight.averageInterval == 89)
        content.entityTimeline[path] = [EntityTimelineDay(date: today, rows: [])]
        let single = EntityInsights.compute(path: path, content: content, today: today.addingDays(89)!)
        #expect(single.recentDayCount == 1 && single.averageInterval == nil)
        let empty = EntityInsights.compute(path: "unknown", content: content, today: today)
        #expect(
            empty.firstDay == nil && empty.lastDay == nil && empty.averageInterval == nil && empty.recentDayCount == 0)
    }
    @Test func taskOnlyAndFutureMentionsDoNotChangeLastEncounter() async throws {
        let context = try TaskTestContext(sample: true)
        defer { context.clean() }
        try "## Tasks\n- [ ] [[Deniz Arıkan]]\n".write(
            to: context.root.appendingPathComponent("journal/2026-10-03.md"), atomically: true, encoding: .utf8)
        try "## Events\n- [[Deniz Arıkan]]\n".write(
            to: context.root.appendingPathComponent("journal/2026-10-05.md"), atomically: true, encoding: .utf8)
        await context.start()
        let insight = EntityInsights.compute(
            path: "people/Deniz Arıkan.md", content: context.store.content, today: today)
        #expect(insight.lastDay == CalendarDate("2026-09-25") && insight.recentDayCount == 5)
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
}
