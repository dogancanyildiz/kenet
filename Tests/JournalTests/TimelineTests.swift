import Foundation
import SwiftUI
import Testing
import VaultFormat

@testable import Journal

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
        let model = timeline(context)
        #expect(model.groups.flatMap(\.rows).count == 5)
        let both = try #require(context.store.content.tasks.first { $0.sourceIdentifier == "both" })
        let range = try #require(TimelineDates(both).span(on: context.today))
        #expect(range.first == CalendarDate("2026-09-28") && range.last == CalendarDate("2026-10-06"))
        let due = try #require(context.store.content.tasks.first { $0.sourceIdentifier == "due" })
        let diamond = try #require(TimelineDates(due).span(on: context.today))
        #expect(diamond.isMilestone && diamond.first == diamond.last)
        let start = try #require(context.store.content.tasks.first { $0.sourceIdentifier == "start" })
        #expect(TimelineDates(start).span(on: context.today)?.last == context.today)
        #expect(TimelineDates(start).span(on: context.today)?.isOpenEnded == true)
        let future = try #require(context.store.content.tasks.first { $0.sourceIdentifier == "future" })
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
        let model = timeline(context)
        model.tasks.projectFilter = "CAFÉ"
        #expect(model.groups.count == 1 && model.groups.first?.rows.count == 2)
        model.collapsed.insert(try #require(model.groups.first?.id))
        #expect(model.collapsed.count == 1)
        model.grouping = .person
        #expect(model.groups.count == 3)
        #expect(model.groups.dropLast().flatMap(\.rows).compactMap(\.sourceIdentifier) == ["shared", "shared"])
        #expect(model.groups.last?.rows.first?.sourceIdentifier == "place")
        model.tasks.entityFilter = "places/Liman Ofis.md"
        #expect(model.groups.count == 1 && model.groups.first?.rows.count == 1)
        model.grouping = .none
        #expect(model.groups.first?.id == "all")
        model.tasks.clearFilters()
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
        let model = timeline(context)
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

    @Test func movingBothDatesPreservesExactSurroundingBOMAndCRLFBytes() async throws {
        let context = try TaskTestContext()
        defer { context.clean() }
        await context.start()
        let source =
            "\u{feff}---\r\ntype: journal\r\ndate: 2026-10-03\r\ncustom: 'keep'\r\n---\r\n\r\n## Tasks\r\n- [/] Plan 🛫 2026-10-03 📅 2026-10-06 🔁 every week #project/demo ^task\r\n  Unchanged note  \r\n\r\n## Other\r\nUntouched\r\n"
        try Data(source.utf8).write(to: context.file)
        await context.store.refresh()
        let model = timeline(context)
        let row = try #require(context.store.content.tasks.first)
        let dates = try #require(TimelineDates(row).shifted(by: 5))
        model.preview(dates, for: row)
        #expect(model.dates(for: row) == dates)
        #expect(await model.save(row, dates: dates, root: context.store.vaultURL))
        let expected = source.replacingOccurrences(of: "🛫 2026-10-03", with: "🛫 2026-10-08").replacingOccurrences(
            of: "📅 2026-10-06", with: "📅 2026-10-11")
        #expect(try Data(contentsOf: context.file) == Data(expected.utf8))
        #expect(model.previews.isEmpty && model.busy.isEmpty)
        #expect(
            context.store.content.tasks.first?.start == dates.start
                && context.store.content.tasks.first?.due == dates.due)
        #expect(try context.document().bodyLines.tasks.count == 1)
    }

    @Test func movingSingleDateDoesNotInventTheMissingEndpoint() async throws {
        for source in ["## Tasks\n- [ ] Due 📅 2026-10-04 ^task\n", "## Tasks\n- [ ] Start 🛫 2026-10-04 ^task\n"] {
            let context = try TaskTestContext()
            defer { context.clean() }
            await context.start()
            try source.write(to: context.file, atomically: true, encoding: .utf8)
            await context.store.refresh()
            let model = timeline(context)
            let row = try #require(context.store.content.tasks.first)
            #expect(
                await model.save(
                    row, dates: try #require(TimelineDates(row).shifted(by: -2)), root: context.store.vaultURL))
            #expect(
                try Data(contentsOf: context.file)
                    == Data(source.replacingOccurrences(of: "2026-10-04", with: "2026-10-02").utf8))
            #expect(context.store.content.tasks.first?.start == (row.start == nil ? nil : CalendarDate("2026-10-02")))
            #expect(context.store.content.tasks.first?.due == (row.due == nil ? nil : CalendarDate("2026-10-02")))
        }
    }

    @Test func resizeChangesOnlyOneTokenAndInvalidRangeDoesNotWrite() async throws {
        let context = try TaskTestContext()
        defer { context.clean() }
        await context.start()
        let source = "## Tasks\n- [ ] Plan 🛫 2026-10-03 📅 2026-10-06 ^task\n"
        try source.write(to: context.file, atomically: true, encoding: .utf8)
        await context.store.refresh()
        let model = timeline(context)
        let row = try #require(context.store.content.tasks.first)
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
        let changed = try #require(context.store.content.tasks.first)
        #expect(
            await model.save(
                changed, dates: try #require(TimelineDates(changed).setting(.start, to: CalendarDate("2026-10-01"))),
                root: context.store.vaultURL))
        #expect(context.store.content.tasks.first?.start == CalendarDate("2026-10-01"))
        #expect(context.store.content.tasks.first?.due == CalendarDate("2026-10-09"))
    }

    @Test func staleDragRefreshesWithoutOverwritingExternalChange() async throws {
        let context = try TaskTestContext()
        defer { context.clean() }
        await context.start()
        try "## Tasks\n- [ ] Plan 🛫 2026-10-03 📅 2026-10-06 ^task\n".write(
            to: context.file, atomically: true, encoding: .utf8)
        await context.store.refresh()
        let model = timeline(context)
        let drag = model.beginDrag(try #require(context.store.content.tasks.first))
        let proposed = try #require(TimelineDates(drag.row).shifted(by: 3))
        model.preview(proposed, for: drag.row)
        let external = "## Tasks\n- [ ] Changed 🛫 2026-10-03 📅 2026-10-06 ^task\n"
        try external.write(to: context.file, atomically: true, encoding: .utf8)
        #expect(await !model.save(drag.row, dates: proposed, root: drag.root))
        #expect(model.errorText != nil && model.previews.isEmpty && model.busy.isEmpty)
        #expect(context.store.content.tasks.first?.sourceText == "Changed")
        #expect(try Data(contentsOf: context.file) == Data(external.utf8))
    }

    @Test func dualWriteReparsesTheIdentifierRepairedByFirstWrite() async throws {
        let context = try TaskTestContext()
        defer { context.clean() }
        await context.start()
        try "## Tasks\n- [ ] Plan 🛫 2026-10-03 📅 2026-10-06\n".write(
            to: context.file, atomically: true, encoding: .utf8)
        await context.store.refresh()
        let model = timeline(context)
        let row = try #require(context.store.content.tasks.first)
        #expect(row.sourceIdentifier == nil)
        #expect(
            await model.save(row, dates: try #require(TimelineDates(row).shifted(by: -2)), root: context.store.vaultURL)
        )
        let task = try #require(context.document().bodyLines.tasks.first)
        #expect(
            task.block.id != nil && task.startDate == CalendarDate("2026-10-01")
                && task.dueDate == CalendarDate("2026-10-04"))
        #expect(context.store.content.tasks.first?.sourceIdentifier == task.block.id)
    }

    @Test func phoneWeekAndMonthBucketsAndRemovingDatesMoveToUndated() async throws {
        let context = try TaskTestContext()
        defer { context.clean() }
        await context.start()
        try "## Tasks\n- [ ] Plan 🛫 2026-10-03 📅 2026-10-06 ^task\n".write(
            to: context.file, atomically: true, encoding: .utf8)
        await context.store.refresh()
        let model = timeline(context)
        #expect(model.mobileGroups.first?.id == "2026-10-01")
        model.scale = .week
        #expect(model.mobileGroups.first?.id == "2026-09-28")
        let row = try #require(context.store.content.tasks.first)
        #expect(await model.save(row, dates: TimelineDates(start: nil, due: nil), root: context.store.vaultURL))
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
        let model = timeline(context)
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
        let model = timeline(context)
        let drag = model.beginDrag(try #require(context.store.content.tasks.first))
        let dates = try #require(TimelineDates(drag.row).shifted(by: 3))
        let next = context.directory.appendingPathComponent("AnotherVault", isDirectory: true)
        try FileManager.default.createDirectory(
            at: next.appendingPathComponent("journal"), withIntermediateDirectories: true)
        let nextFile = next.appendingPathComponent("journal/2026-10-03.md")
        try source.write(to: nextFile, atomically: true, encoding: .utf8)
        await context.store.select(next)
        model.preview(dates, for: drag.row)
        #expect(await !model.save(drag.row, dates: dates, root: drag.root))
        #expect(model.previews.isEmpty && model.busy.isEmpty)
        #expect(try Data(contentsOf: nextFile) == Data(source.utf8))
        #expect(try Data(contentsOf: context.file) == Data(source.utf8))
    }

    #if os(macOS)
        @Test func todayLabelMovesAboveANeighboringDate() {
            // Quarter scale: the 1st prints a date; the 3rd (and the 30th, two days before the
            // next 1st) is close enough that a centered word would cover it.
            let third = Self.placement(
                dayIndex: 2, dayCount: 31, dayWidth: 8, labelWidth: 42, dateLabelWidth: 52, dates: [0])
            #expect(third.centerY == TimelineAxisLayout.upperCenterY)
            Self.expectClear(third, dayCount: 31, dayWidth: 8, labelWidth: 42, dateLabelWidth: 52, dates: [0])

            let beforeNextMonth = Self.placement(
                dayIndex: 28, dayCount: 40, dayWidth: 8, labelWidth: 42, dateLabelWidth: 52, dates: [30])
            #expect(beforeNextMonth.centerY == TimelineAxisLayout.upperCenterY)
            Self.expectClear(
                beforeNextMonth, dayCount: 40, dayWidth: 8, labelWidth: 42, dateLabelWidth: 52, dates: [30])

            // Month scale: Tuesday sits next to Monday's date label.
            let tuesday = Self.placement(
                dayIndex: 8, dayCount: 30, dayWidth: 28, labelWidth: 40, dateLabelWidth: 56, dates: [7])
            Self.expectClear(tuesday, dayCount: 30, dayWidth: 28, labelWidth: 40, dateLabelWidth: 56, dates: [7])
        }

        @Test func todayLabelStaysInsideWhenTodayIsTheFirstOrLastDay() {
            let first = Self.placement(
                dayIndex: 0, dayCount: 40, dayWidth: 8, labelWidth: 42, dateLabelWidth: 52, dates: [])
            Self.expectInside(first, dayCount: 40, dayWidth: 8, labelWidth: 42)
            let last = Self.placement(
                dayIndex: 39, dayCount: 40, dayWidth: 8, labelWidth: 42, dateLabelWidth: 52, dates: [])
            Self.expectInside(last, dayCount: 40, dayWidth: 8, labelWidth: 42)
            // Today is also the day that prints the date (the 1st, at the start of the range).
            let firstWithDate = Self.placement(
                dayIndex: 0, dayCount: 40, dayWidth: 8, labelWidth: 42, dateLabelWidth: 52, dates: [0])
            Self.expectInside(firstWithDate, dayCount: 40, dayWidth: 8, labelWidth: 42)
            Self.expectClear(firstWithDate, dayCount: 40, dayWidth: 8, labelWidth: 42, dateLabelWidth: 52, dates: [0])
        }

        @Test func todayLineStaysBesideTheWord() {
            let open = Self.placement(
                dayIndex: 10, dayCount: 30, dayWidth: 28, labelWidth: 40, dateLabelWidth: 56, dates: [])
            #expect(open.centerY == TimelineDesktopMetrics.axisHeight / 2)
            Self.expectLineBeside(open, dayIndex: 10, dayWidth: 28, labelWidth: 40)
            let third = Self.placement(
                dayIndex: 2, dayCount: 31, dayWidth: 8, labelWidth: 42, dateLabelWidth: 52, dates: [0])
            Self.expectLineBeside(third, dayIndex: 2, dayWidth: 8, labelWidth: 42)
            let first = Self.placement(
                dayIndex: 0, dayCount: 40, dayWidth: 8, labelWidth: 42, dateLabelWidth: 52, dates: [])
            Self.expectLineBeside(first, dayIndex: 0, dayWidth: 8, labelWidth: 42)
            let last = Self.placement(
                dayIndex: 39, dayCount: 40, dayWidth: 8, labelWidth: 42, dateLabelWidth: 52, dates: [])
            Self.expectLineBeside(last, dayIndex: 39, dayWidth: 8, labelWidth: 42)
        }

        @Test func barHeightFollowsTheSharedRowHeight() async throws {
            let context = try TaskTestContext()
            defer { context.clean() }
            await context.start()
            try "## Tasks\n- [ ] Plan 🛫 2026-10-01 📅 2026-10-06 ^task\n".write(
                to: context.file, atomically: true, encoding: .utf8)
            await context.store.refresh()
            let model = timeline(context)
            let row = try #require(context.store.content.tasks.first)
            let bar = TimelineBarView(model: model, row: row, dayWidth: 1, select: {}, edit: { _ in })
            let host = NSHostingView(rootView: bar)
            host.layoutSubtreeIfNeeded()
            #expect(abs(host.fittingSize.height - TimelineDesktopMetrics.rowHeight) < 0.5)
        }

        private static func placement(
            dayIndex: Int, dayCount: Int, dayWidth: CGFloat, labelWidth: CGFloat, dateLabelWidth: CGFloat,
            dates: Set<Int>
        ) -> TimelineTodayLabelPlacement {
            TimelineAxisLayout.todayLabelPlacement(
                dayIndex: dayIndex, dayCount: dayCount, dayWidth: dayWidth, labelWidth: labelWidth,
                dateLabelWidth: dateLabelWidth, dateLabelDayIndices: dates)
        }

        private static func expectClear(
            _ placement: TimelineTodayLabelPlacement, dayCount: Int, dayWidth: CGFloat, labelWidth: CGFloat,
            dateLabelWidth: CGFloat, dates: Set<Int>
        ) {
            expectInside(placement, dayCount: dayCount, dayWidth: dayWidth, labelWidth: labelWidth)
            let word = wordFrame(placement, labelWidth: labelWidth)
            let midline = TimelineDesktopMetrics.axisHeight / 2
            for index in dates {
                let dropped = placement.loweredDateIndices.contains(index)
                let centerY = midline + (dropped ? TimelineAxisLayout.loweredDateOffset : 0)
                let date = CGRect(
                    x: (CGFloat(index) + 0.5) * dayWidth - dateLabelWidth / 2,
                    y: centerY - TimelineAxisLayout.dateLabelHeight / 2,
                    width: dateLabelWidth, height: TimelineAxisLayout.dateLabelHeight)
                #expect(!word.intersects(date), "day \(index) overlaps Bugün")
            }
        }

        private static func expectInside(
            _ placement: TimelineTodayLabelPlacement, dayCount: Int, dayWidth: CGFloat, labelWidth: CGFloat
        ) {
            let word = wordFrame(placement, labelWidth: labelWidth)
            #expect(word.minX >= -0.01)
            #expect(word.maxX <= CGFloat(dayCount) * dayWidth + 0.01)
        }

        private static func expectLineBeside(
            _ placement: TimelineTodayLabelPlacement, dayIndex: Int, dayWidth: CGFloat, labelWidth: CGFloat
        ) {
            let lineX = (CGFloat(dayIndex) + 0.5) * dayWidth
            let word = wordFrame(placement, labelWidth: labelWidth)
            #expect(lineX <= word.minX || lineX >= word.maxX)
        }

        private static func wordFrame(_ placement: TimelineTodayLabelPlacement, labelWidth: CGFloat) -> CGRect {
            CGRect(
                x: placement.centerX - labelWidth / 2,
                y: placement.centerY - TimelineAxisLayout.todayLabelHeight / 2,
                width: labelWidth, height: TimelineAxisLayout.todayLabelHeight)
        }

        @Test func macRowUsesTheSharedDateLine() throws {
            let labels = try String(
                contentsOf: URL(fileURLWithPath: #filePath)
                    .deletingLastPathComponent()
                    .deletingLastPathComponent()
                    .deletingLastPathComponent()
                    .appendingPathComponent("App/Screens/Tasks/Timeline/TimelineDesktopView.swift"),
                encoding: .utf8)
            #expect(labels.contains("TimelineTaskFacts"))
        }
    #endif

    private func timeline(_ context: TaskTestContext) -> TimelineModel {
        TimelineModel(tasks: TasksModel(store: context.store, today: { context.today }))
    }
}
