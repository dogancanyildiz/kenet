import Foundation
import SwiftUI
import Testing
import VaultFormat

@testable import Kenet

#if os(macOS)
    import AppKit
#endif

@MainActor struct TimelineTests {
    @Test func intervalsSingleDayAndOpenEndsUseSourceDates() async throws {
        let context = try TaskTestContext()
        defer { context.clean() }
        await context.start()
        try """
        ## Tasks
        - [ ] Both 🛫 2026-09-28 📅 2026-10-06 ^both
        - [ ] Due 📅 2026-10-04 ^due
        - [ ] Start 🛫 2026-09-30 ^start
        - [ ] Future 🛫 2026-10-10 ^future
        - [ ] Free ^free
        - [x] Done 🛫 2026-10-01 📅 2026-10-03 ✅ 2026-10-03 ^done
        - [-] Cancel 📅 2026-10-03 ^cancel
        """.write(to: context.file, atomically: true, encoding: .utf8)
        await context.store.refresh()
        let model = await timeline(context)
        #expect(model.groups.flatMap(\.rows).count == 5)
        let both = try #require(try await context.store.allTasks().first { $0.sourceIdentifier == "both" })
        let range = try #require(TimelineDates(both).span(on: context.today))
        #expect(range.first == CalendarDate("2026-09-28") && range.last == CalendarDate("2026-10-06"))
        let due = try #require(try await context.store.allTasks().first { $0.sourceIdentifier == "due" })
        let diamond = try #require(TimelineDates(due).span(on: context.today))
        #expect(diamond.isMilestone && diamond.first == diamond.last)
        let start = try #require(try await context.store.allTasks().first { $0.sourceIdentifier == "start" })
        #expect(TimelineDates(start).span(on: context.today)?.last == context.today)
        #expect(TimelineDates(start).span(on: context.today)?.isOpenEnded == true)
        let future = try #require(try await context.store.allTasks().first { $0.sourceIdentifier == "future" })
        #expect(TimelineDates(future).span(on: context.today)?.last == future.start)
        #expect(model.undated.compactMap(\.sourceIdentifier) == ["free"])
    }

    @Test func groupsAndFiltersUseProjectsAndResolvedPeople() async throws {
        let context = try TaskTestContext(sample: true)
        defer { context.clean() }
        await context.start()
        try """
        ## Tasks
        - [ ] [[Deniz Arıkan]] [[Ece Yalın]] Shared 🛫 2026-10-01 📅 2026-10-07 #project/Café ^shared
        - [ ] [[Liman Ofis]] Place 📅 2026-10-04 #project/café ^place
        - [ ] Unassigned 📅 2026-10-03 ^free
        """.write(to: context.file, atomically: true, encoding: .utf8)
        await context.store.refresh()
        let model = await timeline(context)
        model.tasks.projectFilter = "CAFÉ"
        await model.load()
        #expect(model.groups.count == 1 && model.groups.first?.rows.count == 2)
        model.collapsed.insert(try #require(model.groups.first?.id))
        #expect(model.collapsed.count == 1)
        model.grouping = .person
        #expect(model.groups.count == 3)
        #expect(model.groups.dropLast().flatMap(\.rows).compactMap(\.sourceIdentifier) == ["shared", "shared"])
        #expect(model.groups.last?.rows.first?.sourceIdentifier == "place")
        model.tasks.entityFilter = "places/Liman Ofis.md"
        await model.load()
        #expect(model.groups.count == 1 && model.groups.first?.rows.count == 1)
        model.grouping = .none
        #expect(model.groups.first?.id == "all")
        model.tasks.clearFilters()
        await model.load()
        #expect(model.groups.first?.rows.contains { $0.sourceIdentifier == "free" } == true)
    }

    @Test func defaultRangeAndClippingRespectOneYearBounds() async throws {
        let context = try TaskTestContext()
        defer { context.clean() }
        await context.start()
        try """
        ## Tasks
        - [ ] Long 🛫 2025-01-01 📅 2028-01-01 ^long
        - [ ] Old 📅 2026-01-01 ^old
        - [ ] Far 📅 2027-05-01 ^far
        """.write(to: context.file, atomically: true, encoding: .utf8)
        await context.store.refresh()
        let model = await timeline(context)
        #expect(model.visibleRange == context.today.addingDays(-28)!...context.today.addingDays(84)!)
        #expect(model.days.count == 731)
        #expect(model.bounds.lowerBound == context.today.addingDays(-365))
        #expect(model.bounds.upperBound == context.today.addingDays(365))
        #expect(model.groups.flatMap(\.rows).compactMap(\.sourceIdentifier) == ["long"])
        let row = try #require(model.groups.first?.rows.first)
        #expect(
            TimelineDates(row).span(on: context.today)?.clipped(to: model.visibleRange)?.first
                == model.visibleRange.lowerBound)
        #expect(
            TimelineDates(row).span(on: context.today)?.clipped(to: model.visibleRange)?.last
                == model.visibleRange.upperBound)
        model.setVisibleRange(CalendarDate("2024-01-01")!...CalendarDate("2029-01-01")!)
        #expect(model.visibleRange == model.bounds)
        #expect(model.groups.flatMap(\.rows).contains { $0.sourceIdentifier == "old" })
        model.showToday()
        #expect(model.groups.flatMap(\.rows).count == 1)
        model.shiftWindow(by: 1000)
        #expect(model.visibleRange.upperBound == model.bounds.upperBound)
        #expect(model.visibleRange.upperBound.ordinal - model.visibleRange.lowerBound.ordinal == 112)
        model.shiftWindow(by: -1000)
        #expect(model.visibleRange.lowerBound == model.bounds.lowerBound)
    }

    @Test func shiftsResizeAndSnappingRejectReversedOrOverflowDates() throws {
        let dates = TimelineDates(start: CalendarDate("2024-02-28"), due: CalendarDate("2024-03-01"))
        #expect(dates.shifted(by: 1)?.start == CalendarDate("2024-02-29"))
        #expect(dates.shifted(by: -1)?.due == CalendarDate("2024-02-29"))
        #expect(dates.setting(.start, to: CalendarDate("2024-03-02")) == nil)
        #expect(dates.setting(.due, to: CalendarDate("2024-02-27")) == nil)
        #expect(dates.setting(.due, to: CalendarDate("2024-03-05"))?.start == dates.start)
        #expect(dates.shifted(by: Int.max) == nil)
        #expect(TimelineDates(start: nil, due: CalendarDate("9999-12-31")).shifted(by: 1) == nil)
        #expect(TimelineModel.snappedDays(points: 14, dayWidth: 10) == 1)
        #expect(TimelineModel.snappedDays(points: 16, dayWidth: 10) == 2)
        #expect(TimelineModel.snappedDays(points: -16, dayWidth: 10) == -2)
        #expect(TimelineModel.snappedDays(points: .infinity, dayWidth: 10) == nil)
        #expect(TimelineModel.snappedDays(points: 10, dayWidth: 0) == nil)
    }

    /// The dates a drag proposes: whole days only, the body moves both dates, an end moves
    /// its own; a drag that would reverse the range proposes nothing.
    @Test func dragProposesWholeDaysForTheBodyOrOneEnd() throws {
        let dates = TimelineDates(start: CalendarDate("2026-09-23"), due: CalendarDate("2026-09-25"))
        let week: Double = 28
        #expect(
            TimelineModel.proposedDates(from: dates, edge: .due, points: 2 * week + 3, dayWidth: week)
                == TimelineDates(start: CalendarDate("2026-09-23"), due: CalendarDate("2026-09-27")))
        #expect(
            TimelineModel.proposedDates(from: dates, edge: .start, points: -week, dayWidth: week)
                == TimelineDates(start: CalendarDate("2026-09-22"), due: CalendarDate("2026-09-25")))
        #expect(
            TimelineModel.proposedDates(from: dates, edge: nil, points: 3 * week - 5, dayWidth: week)
                == TimelineDates(start: CalendarDate("2026-09-26"), due: CalendarDate("2026-09-28")))
        // Less than half a day snaps back to the dates the task has.
        #expect(TimelineModel.proposedDates(from: dates, edge: .due, points: 13, dayWidth: week) == dates)
        #expect(TimelineModel.proposedDates(from: dates, edge: .start, points: 3 * week, dayWidth: week) == nil)
        #expect(TimelineModel.proposedDates(from: dates, edge: .due, points: .nan, dayWidth: week) == nil)
        // An end the task does not have is not invented.
        let due = TimelineDates(start: nil, due: CalendarDate("2026-09-25"))
        #expect(TimelineModel.proposedDates(from: due, edge: .start, points: week, dayWidth: week) == nil)
    }

    /// Touch: each end of a bar answers in its own half. A bar long enough keeps both ends'
    /// full 37 × 36 pt areas; a short one (quarter scale) splits at its middle, so the start end
    /// is not under the due end's area.
    @Test func barEndsKeepTheirOwnHalfOfAShortBar() {
        let grip = TimelineBarTouch.gripWidth
        let outset: CGFloat = 12
        for barWidth: CGFloat in [26, 30, 41, 49.5, 50, 120] {
            let start = TimelineBarTouch.handleArea(.start, barWidth: barWidth, outset: outset)
            // The due grip sits at the bar's trailing edge.
            let due = TimelineBarTouch.handleArea(.due, barWidth: barWidth, outset: outset)
                .offsetBy(dx: barWidth - grip, dy: 0)
            #expect(start.maxX <= due.minX + 0.001, "bar \(barWidth): \(start) overlaps \(due)")
            #expect(start.minX == -outset && due.maxX == barWidth + outset, "bar \(barWidth)")
            #expect(start.maxX >= grip && due.minX <= barWidth - grip, "bar \(barWidth): a grip lost its area")
            #expect(start.height == TimelineBarTouch.gripHeight + outset * 2)
        }
        let long = TimelineBarTouch.handleArea(.start, barWidth: 120, outset: outset)
        #expect(long.size == CGSize(width: grip + outset * 2, height: TimelineBarTouch.gripHeight + outset * 2))
        let short = TimelineBarTouch.handleArea(.start, barWidth: 30, outset: outset)
        #expect(short.maxX == 15, "the start end reaches the middle of a 30 pt bar: \(short)")
        // The pointer (Mac, no outset) keeps the drawn grip.
        #expect(
            TimelineBarTouch.handleArea(.due, barWidth: 30, outset: 0)
                == CGRect(x: 0, y: 0, width: grip, height: TimelineBarTouch.gripHeight))
    }

    @Test func movingBothDatesPreservesExactSurroundingBOMAndCRLFBytes() async throws {
        let context = try TaskTestContext()
        defer { context.clean() }
        await context.start()
        let source =
            "\u{feff}---\r\ntype: diary\r\ndate: 2026-10-03\r\ncustom: 'keep'\r\n---\r\n\r\n## Tasks\r\n- [/] Plan 🛫 2026-10-03 📅 2026-10-06 🔁 every week #project/demo ^task\r\n  Unchanged note  \r\n\r\n## Other\r\nUntouched\r\n"
        try Data(source.utf8).write(to: context.file)
        await context.store.refresh()
        let model = await timeline(context)
        let row = try #require(try await context.store.allTasks().first)
        let dates = try #require(TimelineDates(row).shifted(by: 5))
        model.preview(dates, for: row)
        #expect(model.dates(for: row) == dates)
        #expect(await model.save(row, dates: dates, root: context.store.vaultURL))
        let expected = source.replacingOccurrences(of: "🛫 2026-10-03", with: "🛫 2026-10-08").replacingOccurrences(
            of: "📅 2026-10-06", with: "📅 2026-10-11")
        #expect(try Data(contentsOf: context.file) == Data(expected.utf8))
        #expect(model.previews.isEmpty && model.busy.isEmpty)
        let saved = try await context.store.allTasks().first
        #expect(saved?.start == dates.start && saved?.due == dates.due)
        #expect(try context.document().bodyLines.tasks.count == 1)
    }

    @Test func movingSingleDateDoesNotInventTheMissingEndpoint() async throws {
        for source in ["## Tasks\n- [ ] Due 📅 2026-10-04 ^task\n", "## Tasks\n- [ ] Start 🛫 2026-10-04 ^task\n"] {
            let context = try TaskTestContext()
            defer { context.clean() }
            await context.start()
            try source.write(to: context.file, atomically: true, encoding: .utf8)
            await context.store.refresh()
            let model = await timeline(context)
            let row = try #require(try await context.store.allTasks().first)
            #expect(
                await model.save(
                    row, dates: try #require(TimelineDates(row).shifted(by: -2)), root: context.store.vaultURL))
            #expect(
                try Data(contentsOf: context.file)
                    == Data(source.replacingOccurrences(of: "2026-10-04", with: "2026-10-02").utf8))
            let moved = try await context.store.allTasks().first
            #expect(moved?.start == (row.start == nil ? nil : CalendarDate("2026-10-02")))
            #expect(moved?.due == (row.due == nil ? nil : CalendarDate("2026-10-02")))
        }
    }

    @Test func resizeChangesOnlyOneTokenAndInvalidRangeDoesNotWrite() async throws {
        let context = try TaskTestContext()
        defer { context.clean() }
        await context.start()
        let source = "## Tasks\n- [ ] Plan 🛫 2026-10-03 📅 2026-10-06 ^task\n"
        try source.write(to: context.file, atomically: true, encoding: .utf8)
        await context.store.refresh()
        let model = await timeline(context)
        let row = try #require(try await context.store.allTasks().first)
        #expect(
            await !model.save(
                row, dates: TimelineDates(start: row.start, due: CalendarDate("2026-10-02")),
                root: context.store.vaultURL))
        #expect(model.errorText != nil)
        #expect(try Data(contentsOf: context.file) == Data(source.utf8))
        #expect(
            await model.save(
                row, dates: try #require(TimelineDates(row).setting(.due, to: CalendarDate("2026-10-09"))),
                root: context.store.vaultURL))
        #expect(
            try Data(contentsOf: context.file)
                == Data(source.replacingOccurrences(of: "📅 2026-10-06", with: "📅 2026-10-09").utf8))
        let changed = try #require(try await context.store.allTasks().first)
        #expect(
            await model.save(
                changed, dates: try #require(TimelineDates(changed).setting(.start, to: CalendarDate("2026-10-01"))),
                root: context.store.vaultURL))
        #expect(try await context.store.allTasks().first?.start == CalendarDate("2026-10-01"))
        #expect(try await context.store.allTasks().first?.due == CalendarDate("2026-10-09"))
    }

    @Test func staleDragRefreshesWithoutOverwritingExternalChange() async throws {
        let context = try TaskTestContext()
        defer { context.clean() }
        await context.start()
        try "## Tasks\n- [ ] Plan 🛫 2026-10-03 📅 2026-10-06 ^task\n".write(
            to: context.file, atomically: true, encoding: .utf8)
        await context.store.refresh()
        let model = await timeline(context)
        let drag = model.beginDrag(try #require(try await context.store.allTasks().first))
        let proposed = try #require(TimelineDates(drag.row).shifted(by: 3))
        model.preview(proposed, for: drag.row)
        let external = "## Tasks\n- [ ] Changed 🛫 2026-10-03 📅 2026-10-06 ^task\n"
        try external.write(to: context.file, atomically: true, encoding: .utf8)
        #expect(await !model.save(drag.row, dates: proposed, root: drag.root))
        #expect(model.errorText != nil && model.previews.isEmpty && model.busy.isEmpty)
        #expect(try await context.store.allTasks().first?.sourceText == "Changed")
        #expect(try Data(contentsOf: context.file) == Data(external.utf8))
    }

    @Test func dualWriteReparsesTheIdentifierRepairedByFirstWrite() async throws {
        let context = try TaskTestContext()
        defer { context.clean() }
        await context.start()
        try "## Tasks\n- [ ] Plan 🛫 2026-10-03 📅 2026-10-06\n".write(
            to: context.file, atomically: true, encoding: .utf8)
        await context.store.refresh()
        let model = await timeline(context)
        let row = try #require(try await context.store.allTasks().first)
        #expect(row.sourceIdentifier == nil)
        #expect(
            await model.save(row, dates: try #require(TimelineDates(row).shifted(by: -2)), root: context.store.vaultURL)
        )
        let task = try #require(context.document().bodyLines.tasks.first)
        #expect(
            task.block.id != nil && task.startDate == CalendarDate("2026-10-01")
                && task.dueDate == CalendarDate("2026-10-04"))
        #expect(try await context.store.allTasks().first?.sourceIdentifier == task.block.id)
    }

    @Test func phoneMonthBucketsAndRemovingDatesMoveToUndated() async throws {
        let context = try TaskTestContext()
        defer { context.clean() }
        await context.start()
        try "## Tasks\n- [ ] Plan 🛫 2026-10-03 📅 2026-10-06 ^task\n".write(
            to: context.file, atomically: true, encoding: .utf8)
        await context.store.refresh()
        let model = await timeline(context)
        #expect(model.mobileGroups.first?.id == "2026-10-01")
        // The phone list only draws Çeyrek; any scale buckets by month.
        model.scale = .week
        #expect(model.mobileGroups.first?.id == "2026-10-01")
        let row = try #require(try await context.store.allTasks().first)
        #expect(await model.save(row, dates: TimelineDates(start: nil, due: nil), root: context.store.vaultURL))
        await model.load()
        #expect(model.groups.isEmpty && model.mobileGroups.isEmpty)
        #expect(model.undated.first?.sourceIdentifier == "task")
        #expect(try Data(contentsOf: context.file) == Data("## Tasks\n- [ ] Plan ^task\n".utf8))
    }

    @Test func externallyReversedRangeIsVisibleButCannotBeShifted() async throws {
        let context = try TaskTestContext()
        defer { context.clean() }
        await context.start()
        let source = "## Tasks\n- [ ] Plan 🛫 2026-10-06 📅 2026-10-03 ^task\n"
        try source.write(to: context.file, atomically: true, encoding: .utf8)
        await context.store.refresh()
        let model = await timeline(context)
        let row = try #require(model.groups.first?.rows.first)
        #expect(TimelineDates(row).span(on: context.today)?.isReversed == true)
        #expect(TimelineDates(row).shifted(by: 1) == nil)
        #expect(try Data(contentsOf: context.file) == Data(source.utf8))
        #expect(
            await model.save(
                row, dates: try #require(TimelineDates(row).setting(.due, to: CalendarDate("2026-10-08"))),
                root: context.store.vaultURL))
    }
    @Test func dragFromPreviousVaultCannotChangeAnIdenticalTaskInNewVault() async throws {
        let context = try TaskTestContext()
        defer { context.clean() }
        await context.start()
        let source = "## Tasks\n- [ ] Plan 🛫 2026-10-03 📅 2026-10-06 ^task\n"
        try source.write(to: context.file, atomically: true, encoding: .utf8)
        await context.store.refresh()
        let model = await timeline(context)
        let drag = model.beginDrag(try #require(try await context.store.allTasks().first))
        let dates = try #require(TimelineDates(drag.row).shifted(by: 3))
        let next = context.directory.appendingPathComponent("AnotherVault", isDirectory: true)
        try FileManager.default.createDirectory(
            at: next.appendingPathComponent("diary"), withIntermediateDirectories: true)
        let nextFile = next.appendingPathComponent("diary/2026-10-03.md")
        try source.write(to: nextFile, atomically: true, encoding: .utf8)
        await context.store.select(next)
        model.preview(dates, for: drag.row)
        #expect(await !model.save(drag.row, dates: dates, root: drag.root))
        #expect(model.previews.isEmpty && model.busy.isEmpty)
        #expect(try Data(contentsOf: nextFile) == Data(source.utf8))
        #expect(try Data(contentsOf: context.file) == Data(source.utf8))
    }

    @Test func todayBadgeSitsOnTheTodayLineBelowTheDates() {
        // Quarter scale: the badge is centered on the line, under the date row, inside the axis.
        let center = TimelineAxisLayout.todayCenter(
            dayIndex: 20, dayWidth: 8, labelWidth: 48, badgeHeight: 18, chartWidth: 320)
        #expect(center.x == 20.5 * 8)
        let badge = CGRect(x: center.x - 24, y: center.y - 9, width: 48, height: 18)
        #expect(badge.maxY <= TimelineDesktopMetrics.axisHeight)
        let dates = TimelineAxisLayout.dateLabelPlacements(
            dayIndices: [0, 18, 39], dayWidth: 8, labelWidth: 52, chartWidth: 320)
        for date in dates {
            let frame = CGRect(
                x: date.centerX - 26, y: date.centerY - TimelineAxisLayout.dateLabelHeight / 2, width: 52,
                height: TimelineAxisLayout.dateLabelHeight)
            #expect(!badge.intersects(frame), "day \(date.dayIndex) overlaps Bugün")
        }
    }

    @Test func axisLabelsShareOneRowAndStayInsideTheChart() {
        let dates = TimelineAxisLayout.dateLabelPlacements(
            dayIndices: [0, 10, 39], dayWidth: 8, labelWidth: 52, chartWidth: 320)
        #expect(Set(dates.map(\.centerY)) == [TimelineAxisLayout.dateRowCenterY])
        for date in dates {
            #expect(date.centerX - 26 >= -0.01)
            #expect(date.centerX + 26 <= 320.01)
        }
        // A label in the middle stays centered on its day.
        #expect(dates[1].centerX == 10.5 * 8)
        // Today on the first or last day: the badge shifts inward.
        let first = TimelineAxisLayout.todayCenter(
            dayIndex: 0, dayWidth: 8, labelWidth: 48, badgeHeight: 18, chartWidth: 320)
        let last = TimelineAxisLayout.todayCenter(
            dayIndex: 39, dayWidth: 8, labelWidth: 48, badgeHeight: 18, chartWidth: 320)
        #expect(first.x == 24 && last.x == 320 - 24)
    }

    @Test func gridLinesStartUnderTheDateRow() {
        // The today line and the week rules start under the dates, so they cross no label.
        let dateRowBottom = TimelineAxisLayout.dateRowCenterY + TimelineAxisLayout.dateLabelHeight / 2
        #expect(TimelineAxisLayout.dateRowBottom >= dateRowBottom)
        let badgeTop = TimelineAxisLayout.todayCenterY(badgeHeight: 18) - 9
        #expect(TimelineAxisLayout.dateRowBottom <= badgeTop)
    }

    @Test func dateLabelsTheScrollEdgeWouldCutAreLeftOut() throws {
        let first = try #require(CalendarDate("2026-10-01"))
        let lower = try #require(first.addingDays(10))
        let upper = try #require(first.addingDays(49))
        // Days 10...49 at 4 pt: the visible part runs from 40 to 200 chart points.
        let span = TimelineAxisLayout.visibleSpan(lower...upper, firstDay: first, dayWidth: 4)
        #expect(span == 40...200)
        #expect(TimelineAxisLayout.showsWhole(centerX: 120, labelWidth: 40, in: span))
        #expect(TimelineAxisLayout.showsWhole(centerX: 180, labelWidth: 40, in: span))
        // "1 Şub" at the right edge: half of it would be cut, so it is not drawn.
        #expect(!TimelineAxisLayout.showsWhole(centerX: 195, labelWidth: 40, in: span))
        #expect(!TimelineAxisLayout.showsWhole(centerX: 50, labelWidth: 40, in: span))
    }

    @Test func openBarsAreAccentOnTheDesktopChartAndProjectColoredOnThePhone() {
        // The desktop chart draws every open bar in the accent; the phone keeps the project hue
        // ("Ev" is `place`; the palette has no amber, decisions.md 2026-11-11).
        #expect(ProjectColor.color(for: "Ev") == .ink.place)
        #expect(TimelineBarChrome.openColor(project: "Ev", usesProjectColor: false) == .ink.accent)
        #expect(TimelineBarChrome.openColor(project: "Ev", usesProjectColor: true) == .ink.place)
        #expect(TimelineBarChrome.openColor(project: nil, usesProjectColor: false) == .ink.accent)
    }

    @Test func undatedUnderTheChartCountsOpenTasksOnly() async throws {
        let context = try TaskTestContext()
        defer { context.clean() }
        await context.start()
        try "## Tasks\n- [ ] Open ^open\n- [x] Done ^done\n- [-] Dropped ^dropped\n".write(
            to: context.file, atomically: true, encoding: .utf8)
        await context.store.refresh()
        let model = await timeline(context)
        #expect(model.openUndated.map(\.sourceIdentifier) == ["open"])
        await model.tasks.loadList()
        // Liste's "Tarihsiz" and the chart's give the same count.
        #expect(model.openUndated.count == model.tasks.undated.count)
    }

    @Test func quarterScaleDrawsNoWeekendWells() {
        #expect(!TimelineAxisLayout.showsWeekends(scale: .quarter))
        #expect(TimelineAxisLayout.showsWeekends(scale: .month))
        #expect(TimelineAxisLayout.showsWeekends(scale: .week))
    }

    @Test func barChromeFollowsTheTaskState() throws {
        let today = try #require(CalendarDate("2026-09-20"))
        let past = try #require(CalendarDate("2026-09-18"))
        let open = TaskStatusPresentation.make(due: today, asOf: today, isCompleted: false)
        let carried = TaskStatusPresentation.make(due: past, asOf: today, isCompleted: false)
        let done = TaskStatusPresentation.make(due: past, asOf: today, isCompleted: true)
        #expect(TimelineBarChrome.make(isValid: true, presentation: open) == .filled)
        #expect(TimelineBarChrome.make(isValid: true, presentation: carried) == .carried)
        #expect(TimelineBarChrome.make(isValid: true, presentation: done) == .done)
        // An invalid range keeps its filled warning bar.
        #expect(TimelineBarChrome.make(isValid: false, presentation: carried) == .filled)
    }

    #if os(macOS)
        @Test func barHeightFollowsTheSharedRowHeight() async throws {
            let context = try TaskTestContext()
            defer { context.clean() }
            await context.start()
            try "## Tasks\n- [ ] Plan 🛫 2026-10-01 📅 2026-10-06 ^task\n".write(
                to: context.file, atomically: true, encoding: .utf8)
            await context.store.refresh()
            let model = await timeline(context)
            let row = try #require(try await context.store.allTasks().first)
            let bar = TimelineBarView(model: model, row: row, dayWidth: 1, select: {}, edit: { _ in })
            let host = NSHostingView(rootView: bar)
            host.layoutSubtreeIfNeeded()
            #expect(abs(host.fittingSize.height - TimelineDesktopMetrics.rowHeight) < 0.5)
        }
    #endif

    @Test func dateLabelVisibilityFollowsScale() throws {
        let monday = try #require(CalendarDate("2026-10-05"))
        #expect(monday.weekday == 0 && monday.day != 1)
        let tuesday = try #require(CalendarDate("2026-10-06"))
        #expect(tuesday.weekday == 1 && tuesday.day != 1)
        let firstOfMonth = try #require(CalendarDate("2026-10-01"))
        #expect(firstOfMonth.day == 1)

        // Week scale: every day shows date label
        #expect(TimelineAxisLayout.showsAxisDateLabel(monday, scale: .week))
        #expect(TimelineAxisLayout.showsAxisDateLabel(tuesday, scale: .week))
        #expect(TimelineAxisLayout.showsAxisDateLabel(firstOfMonth, scale: .week))

        // Month scale: Mondays and 1st of month show date label
        #expect(TimelineAxisLayout.showsAxisDateLabel(monday, scale: .month))
        #expect(!TimelineAxisLayout.showsAxisDateLabel(tuesday, scale: .month))
        #expect(TimelineAxisLayout.showsAxisDateLabel(firstOfMonth, scale: .month))

        // Quarter scale: only 1st of month shows date label
        #expect(!TimelineAxisLayout.showsAxisDateLabel(monday, scale: .quarter))
        #expect(!TimelineAxisLayout.showsAxisDateLabel(tuesday, scale: .quarter))
        #expect(TimelineAxisLayout.showsAxisDateLabel(firstOfMonth, scale: .quarter))
    }

    /// The timeline once its query has answered, as the view loads it.
    private func timeline(_ context: TaskTestContext) async -> TimelineModel {
        let model = TimelineModel(tasks: TasksModel(store: context.store, today: { context.today }))
        await model.load()
        return model
    }
}
