import Foundation
import GoalTracking
import Testing
import VaultFormat
import VaultIndex
import VaultStore

@testable import Journal

/// Optional scale measurement. Enable with MEASURE_READ_MODEL=1 (skipped in default CI).
struct IncrementalReadModelMeasureTests {
    @Test(
        .enabled(if: ProcessInfo.processInfo.environment["MEASURE_READ_MODEL"] == "1")
    )
    func fiveYearEventUpdateCost() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(
            "read-model-measure-" + UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }

        _ = try SyntheticVault.generate(at: root, configuration: .fiveYears)
        let index = try VaultIndex()
        try index.rebuild(vaultRoot: root)
        let today = CalendarDate("2026-10-05")!
        let store = VaultStore(vaultRoot: root, index: index)
        let baseline = VaultReadModel(snapshot: try index.snapshot(), today: today)

        _ = try await store.addingEvent(on: today, text: "Measure event", time: nil)
        let day = "journal/\(today).md"

        let fullStart = DispatchTime.now()
        let full = VaultReadModel(snapshot: try index.snapshot(), today: today)
        let fullMs = Double(DispatchTime.now().uptimeNanoseconds - fullStart.uptimeNanoseconds) / 1_000_000

        let incStart = DispatchTime.now()
        let incremental = try VaultPublishedContent.applying(
            previous: baseline, index: index, changedPaths: [day], today: today
        ).content
        let incMs = Double(DispatchTime.now().uptimeNanoseconds - incStart.uptimeNanoseconds) / 1_000_000
        let peakMB = Int(residentMemoryBytes() / 1_024 / 1_024)

        // Where the incremental apply spends its time, step by step as `VaultReadModel.apply` takes
        // them: the changed fragment, the files linking to it, then for each identifier of the old
        // and new fragment its owner and a scan of every fragment's blocks, and the patch.
        let loadStart = DispatchTime.now()
        let fragment = try #require(try index.loadFragment(path: day))
        let loadMs = milliseconds(since: loadStart)
        let linksStart = DispatchTime.now()
        let linking = try index.links(to: day).map(\.file)
        let linksMs = milliseconds(since: linksStart)
        let identifiers = Set(
            (baseline.fragments[day]?.blocks.compactMap(\.identifier) ?? []) + fragment.blocks.compactMap(\.identifier))
        let ownerStart = DispatchTime.now()
        for identifier in identifiers { _ = try index.owner(of: identifier) }
        let ownerMs = milliseconds(since: ownerStart)
        let scanStart = DispatchTime.now()
        var holders = Set<String>()
        for identifier in identifiers {
            for (file, fragment) in baseline.fragments
            where fragment.blocks.contains(where: { $0.identifier == identifier }) {
                holders.insert(file)
            }
        }
        let scanMs = milliseconds(since: scanStart)
        var patched = baseline
        let patchStart = DispatchTime.now()
        patched.patchDerived(
            before: baseline.fragments.filter { $0.key == day }, touched: [day], removed: [], today: today)
        let patchMs = milliseconds(since: patchStart)
        // Every synthetic day records goal values; the same patch on a file without any (and not
        // an entity) leaves the goal statuses alone.
        let plain = try #require(
            baseline.fragments.keys.sorted().last {
                baseline.fragments[$0]?.entity == nil && baseline.fragments[$0]?.goalLogs.isEmpty == true
            })
        var plainPatched = baseline
        let plainStart = DispatchTime.now()
        plainPatched.patchDerived(
            before: baseline.fragments.filter { $0.key == plain }, touched: [plain], removed: [], today: today)
        let plainMs = milliseconds(since: plainStart)

        print(
            """
            MEASURE_READ_MODEL fiveYears:
              full snapshot+build: \(String(format: "%.1f", fullMs)) ms
              incremental apply: \(String(format: "%.1f", incMs)) ms
                load fragment: \(String(format: "%.1f", loadMs)) ms
                links to the file (\(linking.count)): \(String(format: "%.1f", linksMs)) ms
                owners of \(identifiers.count) identifiers: \(String(format: "%.1f", ownerMs)) ms
                scan of \(baseline.fragments.count) fragments per identifier (\(holders.count) holders): \(String(format: "%.1f", scanMs)) ms
                patch (\(fragment.goalLogs.count) goal values in the day): \(String(format: "%.1f", patchMs)) ms
                patch of \(plain) (no goal values): \(String(format: "%.1f", plainMs)) ms
              resident memory: \(peakMB) MB
              equal: \(incremental.matchesScreenFields(full))
            """)
        #expect(incremental.matchesScreenFields(full))
        // The incremental path must stay cheaper than rebuilding the model and within a frame budget
        // a publish can afford. It once had to be five times cheaper; since the days left the read
        // model (Aşama 11) the full build fell from about 1200 ms to about 390 ms while the
        // incremental apply stayed near 80 ms, so the ratio no longer says whether the patch works.
        #expect(incMs < fullMs)
        #expect(incMs < 150)
    }

    /// Per-field rows and payload bytes of the five-year read model, and how long a rederive
    /// takes: the baseline later slices measure against as fields move to Core queries.
    @Test(
        .enabled(if: ProcessInfo.processInfo.environment["MEASURE_READ_MODEL"] == "1")
    )
    func fiveYearFieldSizesAndRederiveCost() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(
            "read-model-fields-" + UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }

        _ = try SyntheticVault.generate(at: root, configuration: .fiveYears)
        let index = try VaultIndex()
        try index.rebuild(vaultRoot: root)
        let today = CalendarDate("2026-10-05")!

        var snapshotMs: [Double] = []
        var rederiveMs: [Double] = []
        var model = VaultReadModel.empty
        for _ in 0..<5 {
            let snapshotStart = DispatchTime.now()
            let snapshot = try index.snapshot()
            snapshotMs.append(milliseconds(since: snapshotStart))
            let rederiveStart = DispatchTime.now()
            model = VaultReadModel(snapshot: snapshot, today: today)
            rederiveMs.append(milliseconds(since: rederiveStart))
        }

        var lines = ["MEASURE_READ_MODEL fields fiveYears (field | rows | nested rows | bytes):"]
        var total = PayloadSize()
        for child in Mirror(reflecting: model).children {
            guard let label = child.label else { continue }
            let size = PayloadSize(of: child.value)
            total.rows += size.rows
            total.nestedRows += size.nestedRows
            total.bytes += size.bytes
            lines.append("  \(label) | \(size.rows) | \(size.nestedRows) | \(size.bytes)")
        }
        lines.append("  total | \(total.rows) | \(total.nestedRows) | \(total.bytes)")
        lines.append("  snapshot median: \(String(format: "%.1f", median(snapshotMs))) ms")
        lines.append("  rederive median: \(String(format: "%.1f", median(rederiveMs))) ms")
        // The graph's share moved out of the rederive: what the screen now queries on demand.
        var graphMs: [Double] = []
        for _ in 0..<5 {
            let start = DispatchTime.now()
            _ = GraphInput(entities: model.entities, mentions: try index.graphMentions(kinds: GraphInput.kinds))
            graphMs.append(milliseconds(since: start))
        }
        lines.append("  graph query median: \(String(format: "%.1f", median(graphMs))) ms")
        // The entity timelines left the rederive as well: their old construction for comparison, and
        // the two queries the screens now run on demand (the busiest entity's timeline; every
        // file's last encounter).
        let snapshot = try index.snapshot()
        var buildMs: [Double] = []
        var timelines: [String: [EntityTimelineDay]] = [:]
        for _ in 0..<5 {
            let start = DispatchTime.now()
            timelines = EntityTimeline.build(snapshot: snapshot)
            buildMs.append(milliseconds(since: start))
        }
        let old = PayloadSize(of: timelines)
        lines.append("  old entityTimeline field | \(old.rows) | \(old.nestedRows) | \(old.bytes)")
        lines.append("  old entityTimeline build median: \(String(format: "%.1f", median(buildMs))) ms")
        let busiest = try #require(timelines.max { $0.value.count < $1.value.count })
        var timelineMs: [Double] = []
        var encounterMs: [Double] = []
        for _ in 0..<5 {
            var start = DispatchTime.now()
            let days = EntityTimeline.days(from: try index.entityTimeline(for: busiest.key))
            timelineMs.append(milliseconds(since: start))
            #expect(days.count == busiest.value.count)
            start = DispatchTime.now()
            _ = try index.lastEncounters(asOf: today)
            encounterMs.append(milliseconds(since: start))
        }
        lines.append(
            "  timeline query median (\(busiest.value.count) days): \(String(format: "%.1f", median(timelineMs))) ms")
        lines.append("  last encounters query median: \(String(format: "%.1f", median(encounterMs))) ms")
        // The days left the rederive as well: their old construction for comparison, and the
        // queries the screens now run on demand (the whole day list, one month for the calendar,
        // the busiest day's page).
        var daysMs: [Double] = []
        var days: [DaySummary] = []
        for _ in 0..<5 {
            let start = DispatchTime.now()
            days = DaySummary.build(snapshot: snapshot)
            daysMs.append(milliseconds(since: start))
        }
        let oldDays = PayloadSize(of: days)
        lines.append("  old days field | \(oldDays.rows) | \(oldDays.nestedRows) | \(oldDays.bytes)")
        lines.append("  old days build median: \(String(format: "%.1f", median(daysMs))) ms")
        let busiestDay = try #require(
            days.max { $0.events.count + $0.journal.count < $1.events.count + $1.journal.count })
        let month = JournalCalendar.range(of: today)
        var listMs: [Double] = []
        var monthMs: [Double] = []
        var dayMs: [Double] = []
        var list: [DayOverview] = []
        for _ in 0..<5 {
            var start = DispatchTime.now()
            list = try index.daySummaries().map(DayOverview.init(entry:))
            listMs.append(milliseconds(since: start))
            start = DispatchTime.now()
            _ = try index.daySummaries(from: month.lowerBound, to: month.upperBound).map(DayOverview.init(entry:))
            monthMs.append(milliseconds(since: start))
            start = DispatchTime.now()
            let day = DaySummary(contents: try index.day(on: busiestDay.date), date: busiestDay.date)
            dayMs.append(milliseconds(since: start))
            #expect(day.events.count == busiestDay.events.count)
        }
        let listSize = PayloadSize(of: list)
        lines.append(
            "  day list query (\(list.count) days, \(listSize.bytes) bytes) median: \(String(format: "%.1f", median(listMs))) ms"
        )
        lines.append("  month query median: \(String(format: "%.1f", median(monthMs))) ms")
        lines.append(
            "  day query median (\(busiestDay.events.count) events, \(busiestDay.journal.count) journal): \(String(format: "%.1f", median(dayMs))) ms"
        )
        // The goal statuses left the rederive too: their old construction (every log, as the
        // rederive folded it) for comparison, and the query the goal list and day page now run.
        var oldGoalMs: [Double] = []
        var goalQueryMs: [Double] = []
        var oldGoals: [String: GoalStatus] = [:]
        var goalRows: [GoalStatusRow] = []
        for _ in 0..<5 {
            var start = DispatchTime.now()
            let logs = Dictionary(grouping: snapshot.goalLogs, by: \.key).mapValues {
                $0.compactMap(GoalLog.init(indexed:))
            }
            oldGoals = [:]
            for goal in model.goals {
                oldGoals[goal.key] = GoalProgress.compute(definition: goal, logs: logs[goal.key] ?? [], today: today)
            }
            oldGoalMs.append(milliseconds(since: start))
            start = DispatchTime.now()
            goalRows = try index.goalStatuses(today: today)
            goalQueryMs.append(milliseconds(since: start))
        }
        let oldGoalSize = PayloadSize(of: oldGoals)
        lines.append(
            "  old goalStatuses field | \(oldGoalSize.rows) | \(oldGoalSize.nestedRows) | \(oldGoalSize.bytes)")
        lines.append("  old goalStatuses build median: \(String(format: "%.1f", median(oldGoalMs))) ms")
        lines.append(
            "  goal status query (\(goalRows.count) goals, \(snapshot.goalLogs.count) logs) median: \(String(format: "%.1f", median(goalQueryMs))) ms"
        )
        #expect(TodayPresentation.goalStatuses(goalRows) == oldGoals)
        print(lines.joined(separator: "\n"))
        #expect(model.isBuilt && list.count == days.count)
    }
}

/// Approximate payload of a value: UTF-8 bytes of its strings plus the width of its scalars.
/// `rows` are a collection's direct elements; `nestedRows` counts every collection element at
/// any depth, so a dictionary of arrays reports its keys and all their entries.
private struct PayloadSize {
    var rows = 0
    var nestedRows = 0
    var bytes = 0

    init() {}

    init(of value: Any) {
        self = Self.measure(value)
        if Self.isCollection(Mirror(reflecting: value)) { rows = Mirror(reflecting: value).children.count }
    }

    private static func isCollection(_ mirror: Mirror) -> Bool {
        mirror.displayStyle.map { [.collection, .dictionary, .set].contains($0) } ?? false
    }

    private static func measure(_ value: Any) -> PayloadSize {
        var size = PayloadSize()
        switch value {
        case let text as String:
            size.bytes = text.utf8.count
            return size
        case is Bool:
            size.bytes = 1
            return size
        case is Int, is Double, is Float, is Int64, is UInt64:
            size.bytes = 8
            return size
        default:
            break
        }
        let mirror = Mirror(reflecting: value)
        let collection = isCollection(mirror)
        if mirror.children.isEmpty && mirror.displayStyle == .enum { size.bytes = 1 }
        for child in mirror.children {
            let inner = measure(child.value)
            size.nestedRows += inner.nestedRows + (collection ? 1 : 0)
            size.bytes += inner.bytes
        }
        return size
    }
}

private func milliseconds(since start: DispatchTime) -> Double {
    Double(DispatchTime.now().uptimeNanoseconds - start.uptimeNanoseconds) / 1_000_000
}

private func median(_ values: [Double]) -> Double {
    values.sorted()[values.count / 2]
}

private func residentMemoryBytes() -> UInt64 {
    var info = mach_task_basic_info()
    var count = mach_msg_type_number_t(MemoryLayout<mach_task_basic_info>.size) / 4
    let result = withUnsafeMutablePointer(to: &info) {
        $0.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
            task_info(mach_task_self_, task_flavor_t(MACH_TASK_BASIC_INFO), $0, &count)
        }
    }
    return result == KERN_SUCCESS ? info.resident_size : 0
}
