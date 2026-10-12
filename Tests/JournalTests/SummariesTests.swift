import Foundation
import GoalTracking
import Summaries
import Testing
import VaultFormat

@testable import Journal

@MainActor struct SummariesTests {
    @Test func periodNavigationUsesMondayMonthAndYearBoundariesAndStopsAtToday() throws {
        let context = try TaskTestContext()
        defer { context.clean() }
        let model = SummariesModel(store: context.store, today: { CalendarDate("2026-09-20")! })
        #expect(model.range.lowerBound == CalendarDate("2026-09-14") && model.isCurrent)
        // The week after today's has nothing to count yet.
        #expect(!model.canGoNext)
        model.next()
        #expect(model.range.lowerBound == CalendarDate("2026-09-14"))
        model.previous()
        #expect(model.range.upperBound == CalendarDate("2026-09-13") && !model.isCurrent && model.canGoNext)
        model.period = .month
        #expect(model.range.lowerBound == CalendarDate("2026-09-01"))
        model.previous()
        #expect(model.range.upperBound == CalendarDate("2026-08-31"))
        model.period = .year
        #expect(
            model.range.lowerBound == CalendarDate("2026-01-01") && model.range.upperBound == CalendarDate("2026-12-31")
        )
        model.previous()
        #expect(model.range.lowerBound == CalendarDate("2025-01-01"))
        model.next()
        #expect(model.range.lowerBound == CalendarDate("2026-01-01") && !model.canGoNext)
        model.current()
        #expect(model.day == CalendarDate("2026-09-20"))
    }

    @Test func changeIsWordsAndARunningPeriodNamesTheSameDate() throws {
        let turkish = Locale(identifier: "tr_TR")
        let english = Locale(identifier: "en_US")
        #expect(
            SummaryPresentation.change(4, period: .week, isRunning: false, locale: turkish) == "önceki haftaya göre +4")
        #expect(
            SummaryPresentation.change(0, period: .week, isRunning: false, locale: turkish) == "önceki haftayla aynı")
        #expect(
            SummaryPresentation.change(-3, period: .month, isRunning: false, locale: turkish) == "önceki aya göre −3")
        #expect(
            SummaryPresentation.change(-3, period: .year, isRunning: true, locale: turkish)
                == "geçen yılın aynı tarihine göre −3")
        #expect(
            SummaryPresentation.change(0, period: .year, isRunning: true, locale: turkish)
                == "geçen yılın aynı tarihiyle aynı")
        #expect(
            SummaryPresentation.change(4, period: .week, isRunning: false, locale: english) == "+4 vs the previous week"
        )
        #expect(
            SummaryPresentation.change(2, period: .year, isRunning: true, locale: english)
                == "+2 vs the same date last year")
        #expect(
            SummaryPresentation.carried(overdue: 6, undated: 4, locale: turkish)
                == "Açık görevler: 6 devreden, 4 tarihsiz")
        #expect(
            SummaryPresentation.carried(overdue: 6, undated: 4, locale: english)
                == "Open tasks: 6 carried over, 4 undated")
    }

    @Test func rhythmColumnsAlignThePreviousPeriodAndKeepDaysToComeEmpty() throws {
        let days = (0..<10).compactMap { CalendarDate("2026-09-28")!.addingDays($0) }.map {
            SummaryInput.Day(date: $0, events: $0.day, hasJournal: false)
        }
        let today = CalendarDate("2026-10-07")!
        let turkish = Locale(identifier: "tr_TR")
        let summary = PeriodSummary.compute(
            period: .week, containing: today, data: SummaryInput(days: days), today: today)
        let items = SummaryPresentation.rhythm(summary, locale: turkish)
        #expect(items.map(\.value) == [5, 6, 7, 0, 0, 0, 0])
        #expect(items.map(\.previous) == [28, 29, 30, 1, 2, 3, 4])
        #expect(items.map(\.mark) == [.full, .full, .full, .notStarted, .notStarted, .notStarted, .notStarted])
        #expect(items[0].spokenValue == "5 olay, önceki dönemde 28, Yazıldı")
        #expect(items[4].spokenValue == "önceki dönemde 2")
        let month = PeriodSummary.compute(
            period: .month, containing: today, data: SummaryInput(days: days), today: today)
        #expect(
            SummaryPresentation.rhythm(month, locale: turkish).map(\.label)
                == ["1–7", "8–14", "15–21", "22–28", "29–31"])
        #expect(SummaryPresentation.legend(.week, locale: turkish).count == 4)
        #expect(SummaryPresentation.legend(.year, locale: turkish).count == 5)
    }

    @Test func goalMetaNamesTheChainOfARunningOrEndedPeriod() async throws {
        let context = try TaskTestContext(sample: true)
        defer { context.clean() }
        await context.start()
        let turkish = Locale(identifier: "tr_TR")
        let running = try await context.store.periodSummary(
            .week, containing: CalendarDate("2026-09-23")!, today: CalendarDate("2026-09-23"))
        let su = try #require(running.goals.first { $0.definition.key == "su" })
        #expect(
            SummaryPresentation.goalMeta(su, isRunning: running.isRunning, locale: turkish)
                == "Güncel zincir: 8\nSon 30 gün %80")
        let ended = try await context.store.periodSummary(
            .week, containing: CalendarDate("2026-09-20")!, today: CalendarDate("2026-09-23"))
        let spor = try #require(ended.goals.first { $0.definition.key == "spor" })
        #expect(
            SummaryPresentation.goalMeta(spor, isRunning: ended.isRunning, locale: turkish) == "Dönem sonu zinciri: 1")
        #expect(SummaryPresentation.goalValue(spor, locale: turkish) == "3/3")
    }

    @Test func runningWeekComparesWithTheSameWeekdayOfTheWeekBefore() async throws {
        let context = try TaskTestContext(sample: true)
        defer { context.clean() }
        await context.start()
        // Monday 21 September: the sample has 3 events that day and 3 on Monday 14 September.
        let model = SummariesModel(store: context.store, today: { CalendarDate("2026-09-21")! })
        await model.load()
        let summary = try #require(model.summary)
        #expect(summary.isRunning && summary.measuredRange.upperBound == CalendarDate("2026-09-21"))
        #expect(summary.previousMeasuredRange?.upperBound == CalendarDate("2026-09-14"))
        #expect(summary.counts.events == 3 && summary.previous.events == 3 && summary.change.events == 0)
        #expect(summary.counts.writtenDays == 1 && summary.units.count == 7)
        // Monday of a running week: the streak is the goal list's on that day (the week before only),
        // not the one the week's later logs will earn by Sunday.
        #expect(summary.goals.first { $0.definition.key == "spor" }?.streak == 1)
        #expect(!model.isLoading && model.errorText == nil)
    }

    @Test func emptyRunningMonthKeepsOpenInventoryAndItsLastDayComparesTheWholeMonth() async throws {
        let context = try TaskTestContext(sample: true)
        defer { context.clean() }
        await context.start()
        // The sample's days end on 27 September. On 11 October the month before is counted to 11 September.
        let early = SummariesModel(store: context.store, today: { CalendarDate("2026-10-11")! }, period: .month)
        await early.load()
        #expect(early.summary?.isEmpty == true && early.summary?.isRunning == true)
        #expect(early.summary?.counts.overdueTasks == 11 && early.summary?.counts.undatedTasks == 1)
        #expect(early.summary?.previous.events == 0)
        // On 31 October nothing is still to come: the whole of September is compared.
        let last = SummariesModel(store: context.store, today: { CalendarDate("2026-10-31")! }, period: .month)
        await last.load()
        #expect(last.summary?.isRunning == false && last.summary?.previous.events == 40)
        let year = SummariesModel(store: context.store, today: { CalendarDate("2026-10-11")! }, period: .year)
        await year.load()
        #expect(year.summary?.counts.events == 40 && year.summary?.units.count == 12)
        #expect(year.summary?.units[8].events == 40 && year.summary?.units[10].writing == .notStarted)
    }

    @Test func runningWeekShowsTodaysGoalScoreAndEndedWeekItsOwn() async throws {
        let context = try TaskTestContext(sample: true)
        defer { context.clean() }
        await context.start()
        // Wednesday of 21–27 September. Su met its target on 8 of the 10 days from 14 to 23 September;
        // the days after Wednesday are not misses yet.
        let model = SummariesModel(store: context.store, today: { CalendarDate("2026-09-23")! })
        await model.load()
        #expect(model.summary?.goals.first { $0.definition.key == "su" }?.score == 80)
        // Su's chain on Wednesday is the goal list's: 23–20, 18, 16, 15, 14 September, not 0.
        #expect(model.summary?.goals.first { $0.definition.key == "su" }?.streak == 8)
        #expect(model.summary?.goals.first { $0.definition.key == "spor" }?.score == nil)
        // The ended week 14–20 September is measured through its Sunday: 5 of 7.
        model.previous()
        await model.load()
        #expect(model.summary?.goals.first { $0.definition.key == "su" }?.score == 71)
        // Spor at the end of its first successful week.
        #expect(model.summary?.goals.first { $0.definition.key == "spor" }?.streak == 1)
        // Su on that Sunday: 20, 18, 16, 15, 14 September done, 19 and 17 forgiven.
        #expect(model.summary?.goals.first { $0.definition.key == "su" }?.streak == 5)
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
        let model = SummariesModel(store: context.store, today: { CalendarDate("0100-01-01")! }, period: .month)
        #expect(!model.canGoPrevious && !model.canGoNext)
        model.previous()
        #expect(model.day == CalendarDate("0100-01-01"))
        let last = SummariesModel(store: context.store, today: { CalendarDate("9999-12-31")! }, period: .month)
        #expect(!last.canGoNext && last.canGoPrevious)
    }

    @Test func anotherPeriodKeepsTheShownContentUntilItsFirstAnswer() async throws {
        let context = try TaskTestContext(sample: true)
        defer { context.clean() }
        await context.start()
        let model = SummariesModel(store: context.store, today: { CalendarDate("2026-09-27")! })
        await model.load()
        #expect(model.summary?.range.lowerBound == CalendarDate("2026-09-21"))
        let gate = FirstArrivalGate()
        context.store.testingQueryDidFinish = { await gate.pass() }
        model.previous()
        let load = Task { await model.load() }
        await gate.waitUntilHeld()
        // The week before is being read: the shown week stays, with no blank page in between.
        #expect(model.isLoading && model.summary?.range.lowerBound == CalendarDate("2026-09-21"))
        gate.release()
        await load.value
        #expect(!model.isLoading && model.summary?.range.lowerBound == CalendarDate("2026-09-14"))
    }

    @Test func requestKeyChangesWhenTheDayTurnsOver() throws {
        let context = try TaskTestContext()
        defer { context.clean() }
        let clock = DayBox(CalendarDate("2026-10-07")!)
        let model = SummariesModel(store: context.store, today: { clock.day })
        let before = model.requestKey
        #expect(model.requestKey == before)
        clock.day = CalendarDate("2026-10-08")!
        #expect(model.requestKey != before)
    }

    @Test func goalChangeLineShowsOnlyWhatChangedWithItsUnit() throws {
        let book = try #require(
            GoalDefinition(
                id: "book", key: "book", name: "Kitap", period: .day, kind: .number, target: 20, unit: "sayfa"))
        let logs = [
            GoalLog(day: CalendarDate("2026-09-28")!, value: .number(10)),
            GoalLog(day: CalendarDate("2026-10-05")!, value: .number(12)),
            GoalLog(day: CalendarDate("2026-10-06")!, value: .number(10)),
        ]
        let today = CalendarDate("2026-10-07")!
        let turkish = Locale(identifier: "tr_TR")
        let running = PeriodSummary.compute(
            period: .week, containing: today, data: SummaryInput(goals: [.init(definition: book, logs: logs)]),
            today: today)
        let goal = try #require(running.goals.first)
        #expect(
            SummaryPresentation.goalChange(goal, period: .week, isRunning: true, locale: turkish)
                == "geçen haftanın aynı gününe göre +12 sayfa")
        let ended = PeriodSummary.compute(
            period: .week, containing: CalendarDate("2026-10-11")!,
            data: SummaryInput(goals: [
                .init(definition: book, logs: logs + [GoalLog(day: CalendarDate("2026-10-11")!, value: .number(25))])
            ]))
        let full = try #require(ended.goals.first)
        #expect(
            SummaryPresentation.goalChange(full, period: .week, isRunning: false, locale: turkish)
                == "önceki haftaya göre +37 sayfa · zincir +1")
        // Nothing changed: no line, not "önceki haftayla aynı".
        let still = PeriodSummary.compute(
            period: .week, containing: CalendarDate("2026-08-12")!,
            data: SummaryInput(goals: [.init(definition: book, logs: logs)]))
        #expect(
            SummaryPresentation.goalChange(
                try #require(still.goals.first), period: .week, isRunning: false, locale: turkish) == nil)
    }

    @Test func firstNamesStopAtTenAndChipsNameTheirUnit() {
        let turkish = Locale(identifier: "tr_TR")
        let english = Locale(identifier: "en_US")
        let day = CalendarDate("2026-10-06")!
        let names = (1...13).map { SummaryFirstMention(id: "people/K\($0).md", name: "K\($0)", day: day) }
        #expect(
            SummaryPresentation.firstNames(names, kind: .person, locale: turkish)
                == "İlk kez: K1, K2, K3, K4, K5, K6, K7, K8, K9, K10 ve 3 kişi daha")
        #expect(
            SummaryPresentation.firstNames(Array(names.prefix(2)), kind: .place, locale: turkish) == "İlk kez: K1 ve K2"
        )
        #expect(
            SummaryPresentation.firstNames(Array(names.prefix(11)), kind: .place, locale: english)
                == "First time: K1, K2, K3, K4, K5, K6, K7, K8, K9, K10 and 1 more place")
        #expect(
            SummaryPresentation.chipLabel(name: "Deniz Arıkan", count: 7, isFirst: false, locale: turkish)
                == "Deniz Arıkan, 7 geçiş")
        #expect(
            SummaryPresentation.chipLabel(name: "Nil Akın", count: 1, isFirst: true, locale: english)
                == "Nil Akın, 1 mention, first time")
    }
}

@MainActor private final class DayBox {
    var day: CalendarDate
    init(_ day: CalendarDate) { self.day = day }
}
