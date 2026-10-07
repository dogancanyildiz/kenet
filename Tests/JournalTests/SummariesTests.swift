import Foundation
import Summaries
import Testing
import VaultFormat

@testable import Journal

@MainActor struct SummariesTests {
    @Test func periodNavigationUsesMondayAndMonthBoundariesAndCurrentButton() throws {
        let context = try TaskTestContext()
        defer { context.clean() }
        let model = SummariesModel(store: context.store, today: { CalendarDate("2026-09-20")! })
        #expect(model.range.lowerBound == CalendarDate("2026-09-14"))
        model.next()
        #expect(model.range.lowerBound == CalendarDate("2026-09-21"))
        model.previous()
        #expect(model.range.upperBound == CalendarDate("2026-09-20"))
        model.period = .month
        #expect(model.range.lowerBound == CalendarDate("2026-09-01"))
        model.previous()
        #expect(model.range.upperBound == CalendarDate("2026-08-31"))
        model.next()
        model.next()
        #expect(model.range.lowerBound == CalendarDate("2026-10-01"))
        model.current()
        #expect(model.day == CalendarDate("2026-09-20"))
    }
    @Test func comparisonArrowsDescribeSignWithoutJudgement() {
        #expect(SummaryChange(value: 3).symbol == "arrow.up")
        #expect(SummaryChange(value: -2).symbol == "arrow.down")
        #expect(SummaryChange(value: 0).symbol == "minus")
        #expect(SummaryChange(value: -2.5).magnitude == 2.5)
    }
    @Test func sampleHistoryIsQueriedForBothPeriodsAndEmptyMonthKeepsInventory() async throws {
        let context = try TaskTestContext(sample: true)
        defer { context.clean() }
        await context.start()
        let model = SummariesModel(store: context.store, today: { CalendarDate("2026-09-21")! })
        await model.load()
        let summary = try #require(model.summary)
        #expect(summary.counts.events == 21 && summary.previous.events == 19 && summary.change.events == 2)
        #expect(summary.counts.writtenDays == 7 && summary.people.count == 5)
        #expect(summary.goals.first { $0.definition.key == "spor" }?.streak == 2)
        model.period = .month
        model.next()
        await model.load()
        #expect(model.summary?.isEmpty == true)
        #expect(model.summary?.counts.overdueTasks == 11)
        #expect(model.summary?.previous.events == 40)
        #expect(!model.isLoading && model.errorText == nil)
    }
    @Test func newIndexPublicationReloadsEditedActivityWithoutWritingSummaryFiles() async throws {
        let context = try TaskTestContext()
        defer { context.clean() }
        await context.start()
        let model = SummariesModel(store: context.store, today: { context.today })
        await model.load()
        #expect(model.summary?.isEmpty == true)
        #expect(await context.store.addEvent(on: context.today, text: "A note", time: nil))
        await model.load()
        #expect(model.summary?.counts.events == 1 && model.summary?.counts.writtenDays == 1)
        #expect(!FileManager.default.fileExists(atPath: context.root.appendingPathComponent("summaries").path))
        model.reset()
        #expect(model.summary == nil && model.day == context.today && model.errorText == nil)
    }
    @Test func unsupportedCalendarEdgesDisablePeriodNavigation() throws {
        let context = try TaskTestContext()
        defer { context.clean() }
        let model = SummariesModel(store: context.store, today: { CalendarDate("0100-01-01")! })
        model.period = .month
        #expect(!model.canGoPrevious && model.canGoNext)
        model.previous()
        #expect(model.day == CalendarDate("0100-01-01"))
        let last = SummariesModel(store: context.store, today: { CalendarDate("9999-12-31")! })
        last.period = .month
        #expect(!last.canGoNext && last.canGoPrevious)
    }
}
