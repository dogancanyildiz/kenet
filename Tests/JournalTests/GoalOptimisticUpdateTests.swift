import Foundation
import GoalTracking
import Testing
import VaultFormat

@testable import Journal

/// A goal marked on a screen is drawn from the screen's editing model from the moment it is marked
/// until a goal-status answer asked after the write comes; then the answer wins again. A write that
/// saved nothing is taken back.
@MainActor struct GoalOptimisticUpdateTests {
    /// The answer is a status the model would never compute (no logs at all), so the test tells
    /// which source a goal is drawn from.
    @Test func anAnswerAskedAfterTheWriteWinsAgain() async throws {
        let context = try TaskTestContext(sample: true)
        defer { context.clean() }
        await context.start()
        let store = context.store
        let model = GoalDayModel(store: store, day: context.today)
        await model.load()
        let water = try #require(model.goals.first { $0.key == "su" })
        let book = try #require(model.goals.first { $0.key == "kitap" })
        let empty = GoalProgress.compute(definition: water, logs: [], today: context.today)
        let current = model.value(for: water)
        let amount: Double = current == .number(7) ? 6 : 7
        #expect(model.shownStatus(for: water, answer: empty) == empty, "no edit: the answer is drawn")

        let asked = model.currentRevision()
        #expect(await model.set(water, value: .number(amount)))
        let edited = model.status(for: water)
        #expect(edited != empty && edited.progress.done == amount)
        #expect(model.shownStatus(for: water, answer: empty) == edited, "the edit is drawn, not the answer")
        #expect(model.shownStatus(for: book, answer: empty) == empty, "an untouched goal waits for the answer")
        #expect(model.shownStatuses(["su": empty, "kitap": empty]) == ["su": edited, "kitap": empty])

        // An answer asked before the write was published does not have the edit.
        model.answerShown(askedAt: asked)
        #expect(model.shownStatus(for: water, answer: empty) == edited)
        // One asked at the edit's publish has it: the answer wins, whatever it says.
        model.answerShown(askedAt: model.currentRevision())
        #expect(model.shownStatus(for: water, answer: empty) == empty)
        #expect(model.shownStatuses(["su": empty]) == ["su": empty])
    }

    /// An answer asked at the edit's publish can be on screen before the edit's own call returns
    /// (the publish runs before the write's tail): the edit is then answered as it finishes.
    @Test func anAnswerShownBeforeTheEditReturnsAnswersIt() async throws {
        let context = try TaskTestContext(sample: true)
        defer { context.clean() }
        await context.start()
        let store = context.store
        let model = GoalDayModel(store: store, day: context.today)
        await model.load()
        let water = try #require(model.goals.first { $0.key == "su" })
        let empty = GoalProgress.compute(definition: water, logs: [], today: context.today)
        // Stands for that answer: asked at a revision the edit's publish does not pass.
        model.answerShown(askedAt: Int.max)
        #expect(await model.set(water, value: .number(model.value(for: water) == .number(5) ? 4 : 5)))
        #expect(model.shownStatus(for: water, answer: empty) == empty)
    }

    /// A second edit that saved nothing, made before the first edit's answer came: the first edit
    /// still waits for its answer, so a stale answer (asked before the first write) is not drawn.
    @Test func aFailedSecondWriteKeepsTheFirstEditDrawn() async throws {
        let context = try TaskTestContext(sample: true)
        defer { context.clean() }
        await context.start()
        let store = context.store
        let day = try #require(CalendarDate("2026-10-20"))
        let model = GoalDayModel(store: store, day: day)
        await model.load()
        let water = try #require(model.goals.first { $0.key == "su" })
        let stale = GoalProgress.compute(definition: water, logs: [], today: day)
        let asked = model.currentRevision()
        #expect(await model.set(water, value: .number(3)))
        let first = model.status(for: water)
        // The answer asked before the write comes now; the first edit is not in it.
        model.answerShown(askedAt: asked)
        await model.load()
        let journal = context.root.appendingPathComponent("journal")
        try FileManager.default.setAttributes([.posixPermissions: 0o555], ofItemAtPath: journal.path)
        defer { try? FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: journal.path) }

        #expect(await !model.set(water, value: .number(5)))
        #expect(model.status(for: water) == first)
        #expect(model.shownStatus(for: water, answer: stale) == first, "the first edit is still drawn")
        model.answerShown(askedAt: model.currentRevision())
        #expect(model.shownStatus(for: water, answer: stale) == stale, "until an answer that has it")
    }

    /// The day page's slot gives the strip the model of the page's day and vault: the same model
    /// while both stay, a new one for another day or for another vault on the same day (the Mac day
    /// column keeps its page when the vault changes).
    @Test func dayPageSlotRebuildsTheModelForAnotherVault() async throws {
        let context = try TaskTestContext(sample: true)
        defer { context.clean() }
        await context.start()
        let store = context.store
        let day = context.today
        let slot = GoalDayModelSlot()
        let first = slot.model(store: store, day: day)
        #expect(slot.model(store: store, day: day) === first)
        let next = try #require(day.addingDays(1))
        let other = slot.model(store: store, day: next)
        #expect(other !== first && other.day == next)
        let back = slot.model(store: store, day: day)
        #expect(back !== first, "a day left and come back to gets a new model")

        let second = context.directory.appendingPathComponent("Second")
        try FileManager.default.createDirectory(at: second, withIntermediateDirectories: true)
        await store.select(second)
        try #require(store.vaultURL?.path == second.path)
        let switched = slot.model(store: store, day: day)
        #expect(switched !== back, "the same day in another vault gets a new model")
        #expect(switched.belongs(to: store.vaultURL) && !back.belongs(to: store.vaultURL))
        #expect(slot.model(store: store, day: day) === switched)
    }

    /// Nothing saved: the drawn value goes back to what it was and the answer is drawn again.
    @Test func aWriteThatSavedNothingIsTakenBack() async throws {
        let context = try TaskTestContext(sample: true)
        defer { context.clean() }
        await context.start()
        let store = context.store
        let day = try #require(CalendarDate("2026-10-20"))
        let model = GoalDayModel(store: store, day: day)
        await model.load()
        let water = try #require(model.goals.first { $0.key == "su" })
        let before = model.status(for: water)
        let empty = GoalProgress.compute(definition: water, logs: [], today: day)
        let journal = context.root.appendingPathComponent("journal")
        try FileManager.default.setAttributes([.posixPermissions: 0o555], ofItemAtPath: journal.path)
        defer { try? FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: journal.path) }

        #expect(await !model.set(water, value: .number(3)))
        #expect(model.errorText != nil)
        #expect(model.value(for: water) == nil)
        #expect(model.status(for: water) == before)
        #expect(model.shownStatus(for: water, answer: empty) == empty, "the answer is drawn again")
        #expect(!FileManager.default.fileExists(atPath: journal.appendingPathComponent("\(day).md").path))
    }
}

#if os(macOS)
    import AppKit
    import SwiftUI

    /// The list's milestone row and the day page's goal count, mounted, with the goal-status
    /// answers held at the gate (`GoalQueryGate`): a mark is drawn at once, before any answer has it.
    @MainActor @Suite(.timeLimit(.minutes(1)))
    struct GoalOptimisticScreenTests {
        private let watchdog = HostedTestWatchdog()

        @Test func goalListDrawsAMarkAtOnceAndTheSecondTapTakesItBack() async throws {
            let list = try await MilestoneList()
            defer { list.close() }
            guard await list.isUp() else { return }
            #expect(list.shows(list.unmarked))

            list.gate.hold()
            try await list.tap()
            for _ in 0..<40 where list.gate.heldCount == 0 { await list.mount.settle(rounds: 1) }
            #expect(list.gate.heldCount > 0, "the write asks for the statuses again; the answer is held")
            await list.mount.settle()
            #expect(list.shows(list.marked), "the mark is drawn before any answer has it")
            #expect(list.fileHasMark())

            // The second tap acts on the mark the row shows: it takes it back.
            try await list.tap()
            for _ in 0..<40 where list.fileHasMark() { await list.mount.settle(rounds: 1) }
            await list.mount.settle()
            #expect(!list.fileHasMark())
            #expect(list.shows(list.unmarked), "the row follows the second tap, answers still held")

            list.gate.release()
            for _ in 0..<40 where list.gate.heldCount > 0 { await list.mount.settle(rounds: 1) }
            await list.mount.settle()
            #expect(list.shows(list.unmarked))
        }

        @Test func goalListKeepsTheMarkWhenTheAnswerComes() async throws {
            let list = try await MilestoneList()
            defer { list.close() }
            guard await list.isUp() else { return }

            list.gate.hold()
            try await list.tap()
            for _ in 0..<40 where list.gate.heldCount == 0 { await list.mount.settle(rounds: 1) }
            await list.mount.settle()
            #expect(list.shows(list.marked))
            list.gate.release()
            for _ in 0..<40 where list.gate.heldCount > 0 { await list.mount.settle(rounds: 1) }
            await list.mount.settle()
            #expect(list.shows(list.marked), "the answer has the same mark")
            #expect(list.gate.passedCount > 0 || list.gate.heldCount == 0)
            let rows = try await list.context.store.computeGoalStatuses(today: list.context.today)
            #expect(rows.first { $0.definition.id == list.goal.id }?.status.completionDate == list.context.today)
        }

        @Test func goalListTakesBackAMarkThatWasNotSaved() async throws {
            let list = try await MilestoneList()
            defer { list.close() }
            guard await list.isUp() else { return }
            let journal = list.context.root.appendingPathComponent("journal")
            try FileManager.default.setAttributes([.posixPermissions: 0o555], ofItemAtPath: journal.path)
            defer { try? FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: journal.path) }

            try await list.tap()
            let failure = String(localized: "Değişiklik kaydedilemedi. Kasayı kontrol edip yeniden dene.")
            for _ in 0..<40 where !list.texts().contains(failure) { await list.mount.settle(rounds: 1) }
            await list.mount.settle()
            #expect(list.texts().contains(failure))
            #expect(!list.fileHasMark())
            #expect(list.shows(list.unmarked), "nothing was saved: the mark is taken back")
        }

        /// Tapping the strip's plus on the day page counts the goal at once, while the page's answer
        /// is held; the answer then has the same count.
        @Test func dayPageCountsAMarkAtOnce() async throws {
            let context = try TaskTestContext(sample: true)
            defer { context.clean() }
            await context.start()
            let store = context.store
            let day = context.today
            let water = try #require(store.content.goals.first { $0.key == "su" })
            try await store.setGoal(on: day, key: "su", value: .number(water.target - 1))
            func counter() async throws -> String {
                let statuses = TodayPresentation.goalStatuses(try await store.computeGoalStatuses(today: day))
                let daily = store.content.goals.filter { $0.period == .day }
                return "\(daily.filter { statuses[$0.key]?.progress.isComplete == true }.count)/\(daily.count)"
            }
            let before = try await counter()
            let gate = GoalQueryGate(store: store)
            let mount = HostedLayout.Mount(
                GoalScreenEnvironment.wrap(NavigationStack { DayView(store: store, date: day) }, context: context),
                size: CGSize(width: 720, height: 1600))
            defer { mount.close() }
            func shows(_ text: String) -> Bool {
                HostedAccessibilityTree.texts(under: mount).contains { $0.hasSuffix(", " + text) }
            }
            guard await HostedAccessibilityTree.isAvailable(mount, until: { shows(before) && gate.passedCount > 0 })
            else { return }
            let plus = try #require(
                await GoalScreenEnvironment.enabledElement(in: mount) {
                    GoalScreenEnvironment.node(after: water.name, labelled: String(localized: "Artır"), in: mount)
                })

            gate.hold()
            HostedAccessibilityTree.press(plus)
            for _ in 0..<40 where gate.heldCount == 0 { await mount.settle(rounds: 1) }
            #expect(gate.heldCount > 0, "the write asks for the statuses again; the answer is held")
            await mount.settle()
            let marked = "\(Int(before.prefix { $0 != "/" })! + 1)/\(before.split(separator: "/")[1])"
            #expect(shows(marked), "the count has the mark before any answer")
            #expect(!shows(before))

            gate.release()
            for _ in 0..<40 where gate.heldCount > 0 { await mount.settle(rounds: 1) }
            await mount.settle()
            #expect(shows(marked))
            #expect(try await counter() == marked)
        }
    }

    /// Opt-in timing (`MEASURE_GOAL_MARK=1`) on the five-year vault's day page: from the tap on a
    /// goal's plus to the count showing the mark (drawn from the editing model), to the write's
    /// publish, and to the goal-status answer the count waited for before. Medians of five taps.
    @MainActor @Suite(.timeLimit(.minutes(3)))
    struct GoalMarkTimingTests {
        private let watchdog = HostedTestWatchdog(seconds: 170)

        @Test(.enabled(if: ProcessInfo.processInfo.environment["MEASURE_GOAL_MARK"] == "1"))
        func fiveYearDayPageMark() async throws {
            let context = try TaskTestContext()
            defer { context.clean() }
            let manifest = try SyntheticVault.generate(at: context.root, configuration: .fiveYears)
            await context.start()
            let store = context.store
            let day = manifest.endDate
            let goal = try #require(store.content.goals.first { $0.key == "meditasyon" })
            try await store.setGoal(on: day, key: goal.key, value: nil)
            let answer = AnswerStamp()
            store.testingGoalStatusQueryDidFinish = { answer.at = DispatchTime.now().uptimeNanoseconds }
            func counter() async throws -> String {
                let statuses = TodayPresentation.goalStatuses(try await store.computeGoalStatuses(today: day))
                let daily = store.content.goals.filter { $0.period == .day }
                return "\(daily.filter { statuses[$0.key]?.progress.isComplete == true }.count)/\(daily.count)"
            }
            let open = try await counter()
            let mount = HostedLayout.Mount(
                GoalScreenEnvironment.wrap(NavigationStack { DayView(store: store, date: day) }, context: context),
                size: CGSize(width: 720, height: 1600))
            defer { mount.close() }
            func shows(_ text: String) -> Bool {
                HostedAccessibilityTree.texts(under: mount).contains { $0.hasSuffix(", " + text) }
            }
            guard await HostedAccessibilityTree.isAvailable(mount, until: { shows(open) }) else { return }
            let done = "\(Int(open.prefix { $0 != "/" })! + 1)/\(open.split(separator: "/")[1])"
            func milliseconds(_ start: UInt64, _ end: UInt64) -> Double { Double(end &- start) / 1_000_000 }
            var drawn: [Double] = []
            var published: [Double] = []
            var answered: [Double] = []
            for _ in 0..<5 {
                let plus = try #require(
                    await GoalScreenEnvironment.enabledElement(in: mount) {
                        GoalScreenEnvironment.node(after: goal.name, labelled: String(localized: "Artır"), in: mount)
                    })
                await mount.settle()
                let revision = store.lastUpdated
                answer.at = 0
                let start = DispatchTime.now().uptimeNanoseconds
                HostedAccessibilityTree.press(plus)
                var drawnAt: UInt64 = 0
                var publishedAt: UInt64 = 0
                let deadline = start + 10_000_000_000
                while (drawnAt == 0 || publishedAt == 0 || answer.at == 0)
                    && DispatchTime.now().uptimeNanoseconds < deadline
                {
                    mount.window.contentView?.layoutSubtreeIfNeeded()
                    let now = DispatchTime.now().uptimeNanoseconds
                    if publishedAt == 0, store.lastUpdated != revision { publishedAt = now }
                    if drawnAt == 0, shows(done) { drawnAt = DispatchTime.now().uptimeNanoseconds }
                    await Task.yield()
                    try? await Task.sleep(for: .milliseconds(1))
                }
                try #require(drawnAt > 0 && publishedAt > 0 && answer.at > 0)
                drawn.append(milliseconds(start, drawnAt))
                published.append(milliseconds(start, publishedAt))
                answered.append(milliseconds(start, answer.at))
                await mount.settle()
                try await store.setGoal(on: day, key: goal.key, value: nil)
                for _ in 0..<60 where !shows(open) { await mount.settle(rounds: 1) }
            }
            func median(_ values: [Double]) -> Double { values.sorted()[values.count / 2] }
            // One look at the page: the polling's own granularity.
            var looks: [Double] = []
            for _ in 0..<5 {
                let start = DispatchTime.now().uptimeNanoseconds
                _ = shows(done)
                looks.append(milliseconds(start, DispatchTime.now().uptimeNanoseconds))
            }
            #if DEBUG
                let configuration = "Debug"
            #else
                let configuration = "Release"
            #endif
            print(
                String(
                    format:
                        "MEASURE_GOAL_MARK %@ drawn_ms=%.1f published_ms=%.1f answered_ms=%.1f answer_after_publish_ms=%.1f look_ms=%.1f",
                    configuration, median(drawn), median(published), median(answered),
                    median(zip(answered, published).map { $0 - $1 }), median(looks)))
        }
    }

    /// When the last goal-status query finished.
    @MainActor private final class AnswerStamp {
        var at: UInt64 = 0
    }

    /// The goal list over a vault with one yearly milestone, mounted on `context.today`.
    @MainActor private final class MilestoneList {
        let context: TaskTestContext
        let goal: GoalDefinition
        let gate: GoalQueryGate
        let mount: HostedLayout.Mount
        let marked: String
        let unmarked: String

        init() async throws {
            context = try TaskTestContext()
            let goals = context.root.appendingPathComponent("goals")
            try FileManager.default.createDirectory(at: goals, withIntermediateDirectories: true)
            try FileManager.default.createDirectory(
                at: context.root.appendingPathComponent("journal"), withIntermediateDirectories: true)
            try Data("---\ntype: goal\nname: Maraton\nkey: maraton\nperiod: year\nkind: milestone\n---\n".utf8)
                .write(to: goals.appendingPathComponent("Maraton.md"))
            await context.start()
            let store = context.store
            let day = context.today
            goal = try #require(store.content.goals.first { $0.key == "maraton" })
            let done = GoalProgress.compute(
                definition: goal, logs: [GoalLog(day: day, value: .boolean(true))], today: day)
            let open = GoalProgress.compute(definition: goal, logs: [], today: day)
            marked = try #require(GoalRowPresentation.meta(goal: goal, status: done))
            unmarked = try #require(GoalRowPresentation.meta(goal: goal, status: open))
            gate = GoalQueryGate(store: store)
            let now = LocalDay.instant(for: day)
            mount = HostedLayout.Mount(
                GoalScreenEnvironment.wrap(
                    NavigationStack { GoalsView(store: store).environment(\.clockNow, { now }) }, context: context),
                size: CGSize(width: 420, height: 900))
        }

        func close() {
            mount.close()
            context.clean()
        }

        func texts() -> [String] { HostedAccessibilityTree.texts(under: mount) }
        func row() -> String? { texts().first { $0.hasPrefix(goal.name + ",") } }
        func shows(_ meta: String) -> Bool { row()?.hasSuffix(meta) == true }

        func isUp() async -> Bool {
            await HostedAccessibilityTree.isAvailable(mount, until: { self.row() != nil })
        }

        /// Presses the row once the editing model takes taps (it has loaded, no write is running).
        func tap() async throws {
            let name = goal.name
            let node = try #require(
                await GoalScreenEnvironment.enabledElement(in: mount) {
                    GoalScreenEnvironment.node(in: self.mount) { $0.hasPrefix(name + ",") }
                })
            HostedAccessibilityTree.press(node)
        }

        func fileHasMark() -> Bool {
            let url = context.root.appendingPathComponent("journal/\(context.today).md")
            guard let data = try? Data(contentsOf: url) else { return false }
            return String(decoding: data, as: UTF8.self).contains("maraton: true")
        }
    }

    @MainActor enum GoalScreenEnvironment {
        private static let label = NSSelectorFromString("accessibilityLabel")
        private static let value = NSSelectorFromString("accessibilityValue")
        private static let children = NSSelectorFromString("accessibilityChildren")
        private static let enabled = NSSelectorFromString("isAccessibilityEnabled")

        static func wrap(_ view: some View, context: TaskTestContext) -> some View {
            let defaults = context.defaults.defaults
            return
                view
                .environment(NotificationService(center: FakeNotificationCenter(), defaults: defaults))
                .environment(CalendarService(source: OptimisticQuietCalendarSource()))
                .environment(LocationService(source: FakeLocationSource(), defaults: defaults))
                .environment(IntentNavigation())
        }

        /// Waits until `find` gives an element that takes presses.
        static func enabledElement(
            in mount: HostedLayout.Mount, _ find: () -> NSObject?
        ) async -> NSObject? {
            for _ in 0..<60 {
                if let node = find(), isEnabled(node) { return node }
                await mount.settle(rounds: 1)
            }
            return nil
        }

        /// The first node whose label matches, in tree order.
        static func node(in mount: HostedLayout.Mount, where matches: (String) -> Bool) -> NSObject? {
            nodes(in: mount).first { labelText($0).map(matches) == true }
        }

        /// The first node labelled `text` after the first one that reads `anchor` (a label, or a
        /// static text's value).
        static func node(after anchor: String, labelled text: String, in mount: HostedLayout.Mount) -> NSObject? {
            let all = nodes(in: mount)
            guard let start = all.firstIndex(where: { labelText($0) == anchor || valueText($0) == anchor })
            else { return nil }
            return all[start...].first { labelText($0) == text }
        }

        private static func isEnabled(_ node: NSObject) -> Bool {
            guard node.responds(to: enabled), let method = node.method(for: enabled) else { return true }
            typealias Getter = @convention(c) (NSObject, Selector) -> Bool
            return unsafeBitCast(method, to: Getter.self)(node, enabled)
        }

        private static func labelText(_ node: NSObject) -> String? {
            guard node.responds(to: label) else { return nil }
            return node.perform(label)?.takeUnretainedValue() as? String
        }

        private static func valueText(_ node: NSObject) -> String? {
            guard node.responds(to: value) else { return nil }
            return node.perform(value)?.takeUnretainedValue() as? String
        }

        private static func nodes(in mount: HostedLayout.Mount) -> [NSObject] {
            var seen = Set<ObjectIdentifier>()
            var found: [NSObject] = []
            func step(_ item: Any) {
                guard let node = item as? NSObject, seen.insert(ObjectIdentifier(node)).inserted else { return }
                found.append(node)
                if node.responds(to: children), let nodes = node.perform(children)?.takeUnretainedValue() as? [Any] {
                    nodes.forEach(step)
                }
                (node as? NSView)?.subviews.forEach(step)
            }
            step(mount.window.contentView as Any)
            return found
        }
    }

    @MainActor private final class OptimisticQuietCalendarSource: CalendarEventSource {
        var authorization = CalendarAuthorization.denied
        var onChange: (@MainActor @Sendable () -> Void)?
        func requestFullAccess() async throws -> Bool { false }
        func events(from start: Date, to end: Date) async throws -> [CalendarEvent] { [] }
    }
#endif
