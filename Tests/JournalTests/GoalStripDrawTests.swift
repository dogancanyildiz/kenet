import Foundation
import GoalTracking
import Observation
import SwiftUI
import Testing
import VaultFormat

@testable import Journal

/// The Today strip lists the goals still open for their period first, then the complete ones;
/// each group by name, as Finder sorts names (case and digits).
struct GoalStripOrderTests {
    @Test func openGoalsComeFirstThenEachGroupByName() throws {
        let day = try #require(CalendarDate("2026-09-20"))
        func goal(_ id: String, _ name: String) throws -> GoalDefinition {
            try #require(GoalDefinition(id: id, key: id, name: name, period: .day, kind: .boolean))
        }
        let goals = [
            try goal("a", "Su"), try goal("b", "Kitap 10"), try goal("c", "kitap 2"), try goal("d", "Ara"),
            try goal("e", "Yoga"), try goal("f", "Bahçe"),
        ]
        let done: Set = ["a", "d"]
        let ordered = GoalStripPresentation.ordered(goals) { goal in
            let logs = done.contains(goal.id) ? [GoalLog(day: day, value: .boolean(true))] : []
            return GoalProgress.compute(definition: goal, logs: logs, today: day)
        }
        #expect(ordered.map(\.name) == ["Bahçe", "kitap 2", "Kitap 10", "Yoga", "Ara", "Su"])
    }
}

/// One draw of the strip computes each goal's status at most once, from the model's history; a
/// draw over the same history computes none, and an edit computes only the edited goal again.
@MainActor struct GoalStripDrawTests {
    /// Draws the strip once, off screen; returns the statuses the model computed for it.
    private func draw(_ model: GoalDayModel) -> Int {
        let before = model.statusComputations
        let renderer = ImageRenderer(content: GoalStripView(model: model).frame(width: 400))
        _ = renderer.cgImage
        return model.statusComputations - before
    }

    @Test func aDrawComputesEachStatusAtMostOnce() async throws {
        let context = try TaskTestContext(sample: true)
        defer { context.clean() }
        await context.start()
        let model = GoalDayModel(store: context.store, day: context.today)
        await model.load()
        let goals = model.goals
        try #require(goals.count >= 3)

        let first = draw(model)
        #expect(first > 0 && first <= goals.count, "first draw: \(first) for \(goals.count) goals")
        for _ in 0..<3 { #expect(draw(model) == 0, "the same history is not computed again") }

        // A reload that brings the same history keeps every status.
        await model.load()
        #expect(draw(model) == 0)

        // A draw may start the strip's own reload; the edit waits until the model takes edits.
        for _ in 0..<200 where !model.canEdit { try await Task.sleep(for: .milliseconds(10)) }
        try #require(model.canEdit)
        let water = try #require(goals.first { $0.key == "su" })
        let amount: Double = model.value(for: water) == .number(7) ? 6 : 7
        #expect(await model.set(water, value: .number(amount)))
        #expect(draw(model) == 1, "only the edited goal is computed again")
        #expect(model.status(for: water).progress.done == amount)
        #expect(draw(model) == 0)
    }

    /// A goal file edited in place keeps its id and key: the status follows the new definition.
    @Test func aChangedDefinitionIsComputedAgain() async throws {
        let context = try TaskTestContext(sample: true)
        defer { context.clean() }
        await context.start()
        let model = GoalDayModel(store: context.store, day: context.today)
        await model.load()
        let water = try #require(model.goals.first { $0.key == "su" })
        #expect(model.status(for: water).progress.target == water.target)
        let raised = try #require(
            GoalDefinition(
                id: water.id, key: water.key, name: water.name, period: water.period, kind: water.kind,
                target: water.target + 5, unit: water.unit, place: water.place))
        #expect(model.status(for: raised).progress.target == water.target + 5)
        #expect(model.status(for: water).progress.target == water.target)
    }

    /// A kept status still reads the goal's history: a view drawn from it is told when it changes.
    @Test func aKeptStatusIsObservedWithTheHistory() async throws {
        let context = try TaskTestContext(sample: true)
        defer { context.clean() }
        await context.start()
        let model = GoalDayModel(store: context.store, day: context.today)
        await model.load()
        let water = try #require(model.goals.first { $0.key == "su" })
        _ = model.status(for: water)
        let kept = model.statusComputations
        let changed = ChangeFlag()
        withObservationTracking {
            _ = model.status(for: water)
        } onChange: {
            changed.set()
        }
        #expect(model.statusComputations == kept, "the tracked read was the kept status")
        let amount: Double = model.value(for: water) == .number(7) ? 6 : 7
        #expect(await model.set(water, value: .number(amount)))
        #expect(changed.isSet)
    }

    /// A goal's first record (its key had no history at all), here or written by another model and
    /// reloaded, computes its status again.
    @Test func aGoalsFirstRecordComputesItAgain() async throws {
        let context = try TaskTestContext()
        defer { context.clean() }
        try StripVault.write(at: context.root)
        await context.start()
        let page = GoalDayModel(store: context.store, day: context.today)
        let other = GoalDayModel(store: context.store, day: context.today)
        await page.load()
        await other.load()
        let alfa = try #require(page.goals.first { $0.key == "alfa" })
        let beta = try #require(page.goals.first { $0.key == "beta" })
        try #require(page.logs["alfa"] == nil && page.logs["beta"] == nil)
        #expect(page.status(for: alfa).progress.done == 0)
        #expect(await page.set(alfa, value: .number(1)))
        #expect(page.status(for: alfa).progress.done == 1)

        #expect(page.status(for: beta).progress.done == 0)
        #expect(await other.set(beta, value: .number(1)))
        await page.load()
        #expect(page.status(for: beta).progress.done == 1)
    }

    /// Another model writes the same day: the reload brings as many records, with another value.
    @Test func anotherModelsEditReloadedComputesItAgain() async throws {
        let context = try TaskTestContext(sample: true)
        defer { context.clean() }
        await context.start()
        let day = context.today
        let page = GoalDayModel(store: context.store, day: day)
        let other = GoalDayModel(store: context.store, day: day)
        await page.load()
        await other.load()
        let water = try #require(page.goals.first { $0.key == "su" })
        #expect(await other.set(water, value: .number(3)))
        await page.load()
        let count = page.logs["su"]?.count
        #expect(page.status(for: water).progress.done == 3)

        #expect(await other.set(water, value: .number(5)))
        await page.load()
        try #require(page.logs["su"]?.count == count, "the same number of records")
        #expect(page.status(for: water).progress.done == 5)
    }
}

/// Set once from an observation's change handler.
private final class ChangeFlag: @unchecked Sendable {
    private let lock = NSLock()
    private var value = false
    var isSet: Bool { lock.withLock { value } }
    func set() { lock.withLock { value = true } }
}

/// Two weekly number goals with a target of two and no records.
private enum StripVault {
    static func write(at root: URL) throws {
        let goals = root.appendingPathComponent("goals")
        try FileManager.default.createDirectory(at: goals, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(
            at: root.appendingPathComponent("journal"), withIntermediateDirectories: true)
        for (name, key) in [("Alfa", "alfa"), ("Beta", "beta")] {
            let text = "---\ntype: goal\nname: \(name)\nkey: \(key)\nperiod: week\nkind: number\ntarget: 2\n---\n"
            try Data(text.utf8).write(to: goals.appendingPathComponent("\(name).md"))
        }
    }
}

#if os(macOS)
    /// The mounted strip orders its goals again when a goal's history changes, with nothing else
    /// it shows changing (its counter is given; the write waits, so nothing is published).
    @MainActor @Suite(.timeLimit(.minutes(1)))
    struct GoalStripHistoryOrderTests {
        private let watchdog = HostedTestWatchdog()

        @Test func theOrderFollowsTheHistory() async throws {
            let context = try TaskTestContext()
            defer { context.clean() }
            try StripVault.write(at: context.root)
            await context.start()
            let store = context.store
            let model = GoalDayModel(store: store, day: context.today)
            let alfa = try #require(model.goals.first { $0.key == "alfa" })
            let mount = HostedLayout.Mount(
                GoalStripView(model: model, counter: "x"), size: CGSize(width: 420, height: 400))
            defer { mount.close() }
            func order() -> [String] {
                var names: [String] = []
                for text in HostedAccessibilityTree.texts(under: mount) {
                    guard let name = ["Alfa", "Beta"].first(where: { text == $0 || text.hasPrefix($0 + ",") }),
                        names.last != name
                    else { continue }
                    names.append(name)
                }
                return names
            }
            guard
                await HostedAccessibilityTree.isAvailable(
                    mount, until: { order() == ["Alfa", "Beta"] && model.canEdit })
            else { return }

            let published = store.lastUpdated
            store.testingOccupyWriteSlot()
            let edit = Task { await model.set(alfa, value: .number(2)) }
            for _ in 0..<40 where order() != ["Beta", "Alfa"] { await mount.settle(rounds: 1) }
            #expect(order() == ["Beta", "Alfa"], "Alfa is complete for the week: it goes last")
            #expect(store.lastUpdated == published, "the write still waits: nothing was published")
            store.testingReleaseWriteSlot()
            #expect(await edit.value)
            await mount.settle()
            #expect(order() == ["Beta", "Alfa"])
        }
    }
#endif

#if os(macOS)
    import AppKit

    /// Opt-in timing (`MEASURE_GOAL_STRIP=1`) of the strip on the five-year vault, mounted: one
    /// draw over the same history (its counter changes), and the statuses that draw computed.
    /// Medians of five draws.
    @MainActor @Suite(.timeLimit(.minutes(3)))
    struct GoalStripDrawTimingTests {
        private let watchdog = HostedTestWatchdog(seconds: 170)

        @Test(.enabled(if: ProcessInfo.processInfo.environment["MEASURE_GOAL_STRIP"] == "1"))
        func fiveYearStripDraw() async throws {
            let context = try TaskTestContext()
            defer { context.clean() }
            let manifest = try SyntheticVault.generate(at: context.root, configuration: .fiveYears)
            await context.start()
            let model = GoalDayModel(store: context.store, day: manifest.endDate)
            await model.load()
            let tick = StripTick()
            let mount = HostedLayout.Mount(TickedStrip(model: model, tick: tick), size: CGSize(width: 720, height: 900))
            defer { mount.close() }
            let host = try #require(mount.window.contentView)
            await mount.settle()
            func milliseconds(_ start: UInt64) -> Double {
                Double(DispatchTime.now().uptimeNanoseconds &- start) / 1_000_000
            }
            var drawn: [Double] = []
            var computed: [Int] = []
            for _ in 0..<5 {
                await mount.settle()
                let before = model.statusComputations
                let start = DispatchTime.now().uptimeNanoseconds
                tick.value += 1
                let deadline = start + 5_000_000_000
                while tick.drawn != tick.value && DispatchTime.now().uptimeNanoseconds < deadline {
                    host.needsLayout = true
                    host.layoutSubtreeIfNeeded()
                    if tick.drawn != tick.value { await Task.yield() }
                }
                try #require(tick.drawn == tick.value)
                drawn.append(milliseconds(start))
                computed.append(model.statusComputations - before)
            }
            func median<T: Comparable>(_ values: [T]) -> T { values.sorted()[values.count / 2] }
            #if DEBUG
                let configuration = "Debug"
            #else
                let configuration = "Release"
            #endif
            print(
                String(
                    format: "MEASURE_GOAL_STRIP %@ goals=%d draw_ms=%.1f computed=%d", configuration,
                    model.goals.count, median(drawn), median(computed)))
        }
    }

    @MainActor @Observable private final class StripTick {
        var value = 0
        /// The tick the strip's last draw was made for.
        @ObservationIgnored var drawn = 0
    }

    /// The strip with a counter that changes with the tick: each tick draws it again.
    private struct TickedStrip: View {
        let model: GoalDayModel
        let tick: StripTick

        var body: some View {
            let value = tick.value
            GoalStripView(model: model, counter: "\(value)")
                .background { DrawMark(tick: tick, value: value) }
        }
    }

    /// Records the tick once the strip's draw for it ran (the mark is laid out after the strip).
    private struct DrawMark: View {
        let tick: StripTick
        let value: Int

        var body: some View {
            tick.drawn = value
            return Color.clear
        }
    }
#endif
