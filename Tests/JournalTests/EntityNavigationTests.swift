import EntityRecognition
import Foundation
import Testing
import VaultFormat

@testable import Journal

@MainActor
struct EntityNavigationTests {
    @Test func timelineHasSevenIncomingLinksFiveDaysAndSixUniqueBlocks() async throws {
        let context = try EntityPageTestContext()
        defer { context.clean() }
        await context.start()
        let entity = try #require(context.store.content.entities.first { $0.id == context.path })
        #expect(entity.incomingLinks == 7)
        let timeline = try #require(context.store.content.entityTimeline[context.path])
        #expect(
            timeline.map { $0.date.description } == [
                "2026-09-25", "2026-09-22", "2026-09-21", "2026-09-18", "2026-09-14",
            ])
        #expect(timeline.flatMap(\.rows).count == 6)
        #expect(timeline.last?.rows.count == 2)
        let last = try #require(timeline.last)
        #expect(last.rows.first?.ordinal ?? 0 > last.rows.last?.ordinal ?? 0)
        #expect(timeline.allSatisfy { $0.rows.allSatisfy { $0.file.hasPrefix("journal/") } })
    }

    @Test func repeatedLinksInOneBlockProduceOneTimelineRowAfterUpdate() async throws {
        let context = try EntityPageTestContext()
        defer { context.clean() }
        await context.start()
        #expect(await context.store.addEvent(text: "[[Deniz Arıkan]] ve [[Deniz Arıkan|Deniz]]", time: nil))
        let first = try #require(context.store.content.entityTimeline[context.path]?.first)
        #expect(first.date == LocalDay.today())
        #expect(first.rows.count == 1)
        #expect(first.rows.first?.text.plainText == "Deniz Arıkan ve Deniz")
        #expect(context.store.content.entities.first { $0.id == context.path }?.incomingLinks == 9)
    }

    @Test func listOrdersByNameOrRecentUsageAndFiltersAliasesAndQualifiers() async throws {
        let context = try EntityPageTestContext()
        defer { context.clean() }
        await context.start()
        func query(_ search: String = "", _ order: EntityOrdering = .name) -> [EntitySummary] {
            EntityListQuery.entities(
                in: context.store.content, usage: context.store.entityUsage, kind: "person", search: search,
                order: order)
        }
        #expect(query().first?.name == "Baran Tunç")
        #expect(
            EntityListQuery.entities(
                in: context.store.content, usage: [EntityUsage(file: context.path)],
                kind: "person", search: "", order: .recent
            ).first?.name == "Baran Tunç")
        #expect(query("DENIZ AB").map(\.name) == ["Deniz Arıkan"])
        #expect(query("Mert").count == 2)
        #expect(query("iş").map(\.qualifier) == ["iş"])
        #expect(await context.store.addEvent(text: "[[Selin Korkmaz]]", time: nil))
        #expect(query("", .recent).first?.name == "Selin Korkmaz")
        let created = try await context.store.createEntity(kind: .person, name: "Zeta Kurgusal", qualifier: nil)
        #expect(query("", .recent).last?.id == created.file)
        #expect(
            EntityListQuery.entities(
                in: context.store.content, usage: context.store.entityUsage, kind: "place", search: "", order: .name
            ).allSatisfy { $0.kind == "place" })
    }

    @Test func calendarMarksOnlyExistingDaysAndHandlesLeapAndMonthBoundaries() async throws {
        let context = try EntityPageTestContext()
        defer { context.clean() }
        await context.start()
        let september = JournalCalendar(month: CalendarDate("2026-09-15")!, days: context.store.content.days)
        #expect(september.markedDays.count == 14)
        #expect(september.markedDays.contains(CalendarDate("2026-09-14")!))
        #expect(!september.markedDays.contains(CalendarDate("2026-09-13")!))
        let cells = september.cells(firstWeekday: 2)
        #expect(cells.first! == nil)
        #expect(cells.compactMap { $0 }.count == 30)
        let leap = JournalCalendar(month: CalendarDate("2024-02-10")!, days: [])
        #expect(leap.cells(firstWeekday: 1).compactMap { $0 }.last?.description == "2024-02-29")
        #expect(
            JournalCalendar(month: CalendarDate("2026-12-10")!, days: []).adjacentMonth(1).description == "2027-01-01")
    }

    @Test func selectingUnmarkedDayAndWritingCreatesMarkedDay() async throws {
        let context = try EntityPageTestContext()
        defer { context.clean() }
        await context.start()
        let day = CalendarDate("2026-09-13")!
        #expect(context.store.content.day(on: day).events.isEmpty)
        #expect(!JournalCalendar(month: day, days: context.store.content.days).markedDays.contains(day))
        #expect(await context.store.addEvent(on: day, text: "New day", time: nil))
        #expect(JournalCalendar(month: day, days: context.store.content.days).markedDays.contains(day))
    }

    @Test func unresolvedLinkCreationIndexesEntityAndResolvesExistingLink() async throws {
        let context = try EntityPageTestContext()
        defer { context.clean() }
        await context.start()
        #expect(await context.store.addEvent(text: "[[Yeni Kurgusal]]", time: nil))
        let model = UnresolvedEntityModel(store: context.store, target: "Yeni Kurgusal")
        await model.create(.person)
        let entity = try #require(model.created)
        #expect(entity.file == "people/Yeni Kurgusal.md")
        #expect(context.store.content.entities.contains { $0.id == entity.file })
        let event = try #require(context.store.content.day(on: LocalDay.today()).events.first)
        #expect(event.text.spans.contains { $0.destination == entity.file })
        await model.create(.person)
        #expect(context.store.content.entities.filter { $0.id == entity.file }.count == 1)
    }

    @Test func unresolvedCreationAsksQualifierForExistingDisplayName() async throws {
        let context = try EntityPageTestContext()
        defer { context.clean() }
        await context.start()
        _ = try await context.store.createEntity(kind: .place, name: "Yeni Kurgusal", qualifier: "okul")
        let model = UnresolvedEntityModel(store: context.store, target: "Yeni Kurgusal")
        await model.create(.place)
        #expect(model.needsQualifier)
        #expect(model.created == nil)
        model.qualifier = "iş"
        await model.create(.place)
        #expect(model.created?.file == "places/Yeni Kurgusal (iş).md")
    }
}
