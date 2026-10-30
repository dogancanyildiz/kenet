import Darwin
import Foundation
import Testing
import VaultFormat

@testable import Journal

/// The widget snapshot stays the index's answer however often and however late it is written
/// (docs/architecture.md "Widget'lar"): no publish lost, the day changes at midnight without the
/// app, the widget's own mark is reconciled rather than overwritten, and WidgetKit reloads only
/// when the content changed.
@MainActor @Suite("Widget refresh reliability")
struct WidgetRefreshReliabilityTests {
    /// The days the app writes for `now`, straight from the goal query.
    private static func indexDays(_ store: IndexStore, at now: Date) async throws -> [WidgetSnapshot.Day] {
        let today = LocalDay.today(at: now)
        let tomorrow = try #require(today.addingDays(1))
        var days: [WidgetSnapshot.Day] = [
            .init(date: today, rows: try await store.computeGoalStatuses(today: today)),
            .init(date: tomorrow, rows: try await store.computeGoalStatuses(today: tomorrow)),
        ]
        let counts = try await store.computeNotificationDays(from: today, through: tomorrow)
        days[0].openTaskCount = counts.openTaskCounts[today, default: 0]
        days[1].openTaskCount = counts.openTaskCounts[tomorrow, default: 0]
        return days
    }

    /// (a) A hundred goal changes in a row, none awaited by the widget writer: the last snapshot
    /// is the last index state.
    @Test func hundredPublishesInARowEndAtTheLastIndexState() async throws {
        let harness = try WidgetSnapshotTests.Harness()
        defer { harness.context.clean() }
        await harness.start()
        let store = harness.context.store

        for pages in 1...100 {
            try await store.setGoal(on: GraceDayVault.today, key: "okuma", value: .number(Double(pages)))
        }
        await harness.writer.settle()

        let snapshot = try #require(harness.snapshot)
        let reading = try #require(snapshot.days[0].goals.first { $0.key == "okuma" })
        #expect(reading.value == 100)
        #expect(!reading.isPending)
        #expect(snapshot.days == (try await Self.indexDays(store, at: WidgetSnapshotTests.noon)))
        // Publishes that arrive while a write runs fold into one more run, never into none.
        #expect(harness.timelines.reloads.count >= 2 * WidgetKinds.all.count)
        #expect(harness.timelines.reloads.count <= 101 * WidgetKinds.all.count)
    }

    /// (b) At midnight the timeline moves to tomorrow's entry without the app; the app's write
    /// the next day replaces it with the same answer, now as today.
    @Test func midnightMovesToTomorrowAndTheNextDaysWriteReplacesIt() async throws {
        let harness = try WidgetSnapshotTests.Harness()
        defer { harness.context.clean() }
        await harness.start()
        let first = try #require(harness.snapshot)
        let calendar = WidgetDay.deviceCalendar
        let midnight = try #require(WidgetDay.start(of: "2026-09-21", calendar: calendar))

        let end = try #require(calendar.date(byAdding: .day, value: 1, to: midnight))
        let late = first.timeline(from: midnight.addingTimeInterval(-60), calendar: calendar)
        try #require(late.map(\.date) == [midnight.addingTimeInterval(-60), midnight, end])
        #expect(late[1].day == first.days[1])
        #expect(late[1].day?.date == "2026-09-21")
        #expect(late[1].day?.goals.allSatisfy(\.isPending) == true)

        harness.clock.now = WidgetSnapshotTests.noon.addingTimeInterval(24 * 3600)
        harness.writer.update()
        await harness.writer.settle()
        let next = try #require(harness.snapshot)
        #expect(next.days.map(\.date) == ["2026-09-21", "2026-09-22"])
        #expect(next.days[0] == first.days[1])
        #expect(next.days == (try await Self.indexDays(harness.context.store, at: harness.clock.now)))
        #expect(next.timeline(from: harness.clock.now, calendar: calendar).first?.day == next.days[0])
        #expect(harness.timelines.reloads.count == 2 * WidgetKinds.all.count)
    }

    /// (c) After the widget marked a goal, the app's next write (it arrives in the foreground)
    /// rescans the day files before it asks the index: the snapshot keeps the mark, now as the
    /// index's answer, and the widget is not reloaded for the same content.
    @Test func appWriteAfterAWidgetMarkKeepsTheMarkAsTheIndexAnswer() async throws {
        let harness = try CloudWidgetHarness()
        defer { harness.clean() }
        await harness.start()
        #expect(await harness.marker().mark(goalID: try harness.goalID("esneme")) == .marked)
        let marked = try #require(harness.snapshot)
        #expect(marked.markedAt != nil)

        harness.writer.update()
        await harness.writer.settle()

        let snapshot = try #require(harness.snapshot)
        #expect(snapshot.days == marked.days)
        #expect(snapshot.days == (try await harness.indexDays()))
        #expect(snapshot.days[0].goals.last?.key == "esneme")
        #expect(snapshot.days[0].goals.last?.isPending == false)
        #expect(snapshot.markedAt == nil)
        #expect(harness.timelines.reloads.count == WidgetKinds.all.count)
    }

    /// (c) The index wins once it has read the day files: a mark undone in the file before the
    /// app came back (another device, an editor) is not kept.
    @Test func indexWinsOverAWidgetMarkTheFileNoLongerHas() async throws {
        let harness = try CloudWidgetHarness()
        defer { harness.clean() }
        await harness.start()
        #expect(await harness.marker().mark(goalID: try harness.goalID("esneme")) == .marked)
        try Data(WidgetMarkingTests.unmarkedDay.utf8).write(to: harness.dayFile, options: .atomic)

        harness.writer.update()
        await harness.writer.settle()

        let snapshot = try #require(harness.snapshot)
        #expect(snapshot.days[0].goals.first { $0.key == "esneme" }?.isPending == true)
        #expect(snapshot.days == (try await harness.indexDays()))
        #expect(snapshot.markedAt == nil)
        #expect(harness.timelines.reloads.count == 2 * WidgetKinds.all.count)
    }

    /// (d) WidgetKit reloads only when what the widget draws changed: publishes without goal
    /// changes and repeated updates count nothing.
    @Test func reloadsCountOnlyContentChanges() async throws {
        let harness = try WidgetSnapshotTests.Harness()
        defer { harness.context.clean() }
        await harness.start()
        let store = harness.context.store
        #expect(harness.timelines.reloads.count == WidgetKinds.all.count)

        for number in 1...10 {
            #expect(await store.addEvent(on: GraceDayVault.today, text: "Olay \(number)", time: nil))
            harness.writer.update()
        }
        await harness.writer.settle()
        #expect(harness.timelines.reloads.count == WidgetKinds.all.count)

        try await store.setGoal(on: GraceDayVault.today, key: "esneme", value: .boolean(true))
        await harness.writer.settle()
        #expect(harness.timelines.reloads.count == 2 * WidgetKinds.all.count)

        for _ in 1...5 { harness.writer.update() }
        await harness.writer.settle()
        #expect(harness.timelines.reloads.count == 2 * WidgetKinds.all.count)

        try await store.setGoal(on: GraceDayVault.today, key: "esneme", value: nil)
        await harness.writer.settle()
        #expect(harness.timelines.reloads.count == 3 * WidgetKinds.all.count)
    }

    // MARK: - Cost in the widget

    /// Optional (MEASURE_WIDGET=1): the widget's write on the five-year vault, with Core loaded
    /// and the throwaway index Core's writer needs. The widget's memory budget is about 30 MB.
    /// On the iOS simulator xcodebuild passes the variable on with a prefix in its own
    /// environment: `TEST_RUNNER_MEASURE_WIDGET=1` (one earlier run needed
    /// `SIMCTL_CHILD_MEASURE_WIDGET=1`; try both). `-only-testing` names the suite
    /// (`JournalTests_iOS/WidgetRefreshReliabilityTests`): the test's own name selects none.
    /// The footprint is the test host's, not the widget process's.
    @Test(.enabled(if: ProcessInfo.processInfo.environment["MEASURE_WIDGET"] == "1"))
    func fiveYearVaultMarkCost() async throws {
        let directory = try testDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let container = directory.appendingPathComponent("Cloud", isDirectory: true)
        let root = container.appendingPathComponent("Documents/Kenet", isDirectory: true)
        let manifest = try SyntheticVault.generate(at: root, configuration: .fiveYears)
        let group = directory.appendingPathComponent("group", isDirectory: true)
        let day = try #require(manifest.endDate.addingDays(1))
        let calendar = WidgetDay.deviceCalendar
        let now = try #require(WidgetDay.start(of: "\(day)", calendar: calendar)).addingTimeInterval(12 * 3600)
        let goal = WidgetSnapshot.Goal(
            key: "meditasyon", name: "Meditasyon", kind: .boolean, target: 1, unit: nil, value: 0, isPending: true,
            streak: 3, chainDays: 0)
        try WidgetSnapshotFile.write(
            WidgetSnapshot(
                writtenAt: now, vaultID: "v", days: [.init(date: "\(day)", goals: [goal])], vaultKind: .icloud,
                cloudRelativePath: "Documents/Kenet", cloudVaultIdentity: WidgetSnapshot.cloudVaultIdentity(at: root)),
            to: WidgetSnapshotFile.url(in: group))
        let marker = WidgetGoalMarker(groupContainer: group, ubiquityContainer: { container }, now: { now })

        let before = Self.footprint()
        let clock = ContinuousClock()
        let start = clock.now
        let outcome = await marker.mark(goalID: WidgetSnapshot.intentID(vaultID: "v", key: "meditasyon"))
        let elapsed = start.duration(to: clock.now)
        let after = Self.footprint()
        #expect(outcome == .marked)
        let mb = { (bytes: UInt64) in String(format: "%.1f", Double(bytes) / 1_048_576) }
        print(
            "MEASURE_WIDGET files \(manifest.markdownFileCount) mark \(elapsed) "
                + "footprint before \(mb(before.current)) MB after \(mb(after.current)) MB "
                + "peak before \(mb(before.peak)) MB peak after \(mb(after.peak)) MB")
    }

    /// The process's physical footprint now and at its peak.
    private static func footprint() -> (current: UInt64, peak: UInt64) {
        var info = task_vm_info_data_t()
        var count = mach_msg_type_number_t(MemoryLayout<task_vm_info_data_t>.size / MemoryLayout<natural_t>.size)
        let result = withUnsafeMutablePointer(to: &info) {
            $0.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
                task_info(mach_task_self_, task_flavor_t(TASK_VM_INFO), $0, &count)
            }
        }
        guard result == KERN_SUCCESS else { return (0, 0) }
        return (info.phys_footprint, UInt64(info.ledger_phys_footprint_peak))
    }
}
