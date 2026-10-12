import Foundation
import GoalTracking
import Testing
import VaultFormat
import VaultIndex
import VaultStore

@testable import Journal

/// The goal screens take their statuses from the goal-status query. The query is compared with the
/// read model's old `goalStatuses` construction (every log, `VaultReadModel.goalStatuses(today:)`
/// in the test support) after the edits a publish patches, and on a day page older than the
/// goal-log list the app keeps for notifications.
@MainActor struct GoalScreensQueryTests {
    @Test func goalStatusesAfterIncrementalEditsMatchFullRebuild() async throws {
        let root = try testDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        try IncrementalReadModelVault.seed(at: root)
        let index = try VaultIndex()
        try index.rebuild(vaultRoot: root)
        let store = VaultStore(vaultRoot: root, index: index)
        let today = IncrementalReadModelVault.today
        let yesterday = try #require(CalendarDate("2026-10-04"))
        // Outside the 400-day goal-log list the read model keeps.
        let longAgo = try #require(today.addingDays(-500))
        let previous = try #require(longAgo.addingDays(-1))
        var model = try IncrementalReadModelVault.fullModel(index: index)

        func check(_ label: String) throws -> [String: GoalStatus] {
            let rebuilt = try VaultIndex()
            try rebuilt.rebuild(vaultRoot: root)
            var statuses: [String: GoalStatus] = [:]
            for day in [today, yesterday, today.addingDays(1)!, longAgo] {
                let rows = try index.goalStatuses(today: day)
                let comment = Comment(rawValue: "\(label) \(day)")
                #expect(rows.map(\.definition) == model.goals, comment)
                let byKey = TodayPresentation.goalStatuses(rows)
                #expect(byKey == model.goalStatuses(today: day), comment)
                let full = VaultReadModel(snapshot: try rebuilt.snapshot(), today: day)
                #expect(byKey == full.goalStatuses(today: day), comment)
                if day == today { statuses = byKey }
            }
            return statuses
        }
        func publish(_ changed: Set<String>, deleted: Set<String> = []) throws {
            model = try VaultPublishedContent.applying(
                previous: model, index: index, changedPaths: changed, deletedPaths: deleted, today: today
            ).content
        }

        var statuses = try check("seed")
        #expect(statuses["reading"]?.progress.done == 5 && statuses["reading"]?.streak == 0)

        _ = try await store.settingGoalValue(on: today, key: "reading", value: .number(20))
        try publish(["journal/\(today).md"])
        statuses = try check("value")
        #expect(statuses["reading"]?.progress.isComplete == true && statuses["reading"]?.streak == 1)

        _ = try await store.settingGoalValue(on: yesterday, key: "reading", value: .number(30))
        try publish(["journal/\(yesterday).md"])
        statuses = try check("past value")
        #expect(statuses["reading"]?.streak == 2)

        for day in [previous, longAgo] {
            _ = try await store.settingGoalValue(on: day, key: "reading", value: .number(25))
            try publish(["journal/\(day).md"])
        }
        statuses = try check("old values")
        #expect(model.goalLogs["reading"]?.contains { $0.day == longAgo } == false)
        #expect(statuses["reading"]?.streak == 2 && statuses["reading"]?.longestStreak == 2)

        let created = try await store.creatingGoal(name: "Walk", period: .day, kind: .boolean, target: 1, unit: nil)
        try publish([created])
        statuses = try check("new goal")
        #expect(statuses["walk"]?.isPendingToday == true)

        _ = try await store.settingGoalValue(on: today, key: "walk", value: .boolean(true))
        try publish(["journal/\(today).md"])
        statuses = try check("new goal value")
        #expect(statuses["walk"]?.progress.isComplete == true)

        let edited = root.appendingPathComponent("journal/\(yesterday).md")
        let text = try String(contentsOf: edited, encoding: .utf8)
        #expect(text.contains("reading: 30"))
        try Data(text.replacingOccurrences(of: "reading: 30", with: "reading: 3").utf8).write(to: edited)
        try FileManager.default.setAttributes(
            [.modificationDate: Date().addingTimeInterval(2)], ofItemAtPath: edited.path)
        model = try IncrementalReadModelVault.apply(model, index: index, result: try index.refresh(vaultRoot: root))
        statuses = try check("external edit")
        #expect(statuses["reading"]?.streak == 1)

        try FileManager.default.removeItem(at: root.appendingPathComponent("journal/\(previous).md"))
        model = try IncrementalReadModelVault.apply(model, index: index, result: try index.refresh(vaultRoot: root))
        statuses = try check("external delete")
        #expect(statuses["reading"]?.longestStreak == 1)
    }

    /// A day page more than 400 days back: its daily goals count from the logs of that day. The
    /// app's goal-log list (notifications, geofence) does not reach that far; the page's old
    /// statuses, built from that list, showed the goal as open.
    @Test func dayPageOlderThanTheGoalLogListCountsItsGoals() async throws {
        let context = try TaskTestContext()
        defer { context.clean() }
        await context.start()
        let store = context.store
        let today = try #require(store.content.derivedForDay)
        let old = try #require(today.addingDays(-800))
        try await store.createGoal(name: "Run", period: .day, kind: .boolean, target: 1, unit: nil)
        try await store.createGoal(name: "Read", period: .day, kind: .number, target: 10, unit: nil)
        try await store.setGoal(on: old, key: "run", value: .boolean(true))
        try await store.setGoal(on: old, key: "read", value: .number(4))
        #expect(store.content.goalLogs["run"]?.isEmpty == true)

        let rows = try await store.computeGoalStatuses(today: old)
        let statuses = TodayPresentation.goalStatuses(rows)
        #expect(statuses == store.content.goalStatuses(today: old))
        #expect(statuses["run"]?.progress.isComplete == true && statuses["read"]?.progress.done == 4)
        let page = TodayPresentation(
            day: DaySummary(empty: old), groups: TaskGroups(rows: [], on: old, isToday: false),
            goals: store.content.goals, goalStatuses: statuses, goalStatusesDay: old, today: today,
            locale: Locale(identifier: "en_US"), calendar: Calendar(identifier: .gregorian))
        #expect(page.counter(for: .goals) == "1/2" && page.remainingGoalCount == 1)

        let fromList = Dictionary(
            uniqueKeysWithValues: store.content.goals.map {
                ($0.key, GoalProgress.compute(definition: $0, logs: store.content.goalLogs[$0.key] ?? [], today: old))
            })
        #expect(fromList["run"]?.progress.isComplete == false, "the old page statuses missed the day")
    }

    /// Each screen against the source it read before the query, on an edge vault: a copied key of
    /// another kind, yearly amount and milestone goals, goals with no log, a 521-day chain with a
    /// forgiven miss, logs ahead of today. The list drew each goal's own status from the editing
    /// model once it loaded the whole history; the day page and "Close the day" counted a copied key
    /// as the first by name, from the goal-log list (399 days back, 6 ahead). Past and future days
    /// beyond that list are the one intended change: their daily goals now count.
    @Test func goalScreensMatchTheirOldSourcesOnAnEdgeVault() async throws {
        let context = try TaskTestContext()
        defer { context.clean() }
        let now = LocalDay.today()
        try EdgeGoalVault.write(at: context.root, now: now)
        await context.start()
        let store = context.store
        try #require(store.content.derivedForDay == now)
        #expect(store.content.goals.map(\.name) == ["Boş", "Kitap yılı", "Koşu", "Koşu kopya", "Maraton", "Su"])
        let daily = store.content.goals.filter { $0.period == .day }
        func complete(_ statuses: [String: GoalStatus]) -> [Bool] {
            daily.map { statuses[$0.key]?.progress.isComplete == true }
        }
        func fromGoalLogList(_ day: CalendarDate) -> [String: GoalStatus] {
            let logs = store.content.goalLogs
            return Dictionary(
                store.content.goals.map {
                    ($0.key, GoalProgress.compute(definition: $0, logs: logs[$0.key] ?? [], today: day))
                }, uniquingKeysWith: { first, _ in first })
        }
        let listStart = try #require(now.addingDays(-399))
        let listEnd = try #require(now.addingDays(6))
        for offset in [0, -1, -10, -11, -399, -400, -450, -520, -521, 3, 6, 7, 10] {
            let day = try #require(now.addingDays(offset))
            let comment = Comment(rawValue: "\(offset)")
            let rows = try await store.computeGoalStatuses(today: day)
            let editing = GoalDayModel(store: store, day: day)
            await editing.load()
            try #require(editing.hasLoaded)
            let byID = Dictionary(uniqueKeysWithValues: rows.map { ($0.definition.id, $0.status) })
            for goal in store.content.goals {
                #expect(byID[goal.id] == editing.status(for: goal), comment)
            }
            let page = TodayPresentation.goalStatuses(rows)
            #expect(page == store.content.goalStatuses(today: day), comment)
            if day >= listStart && day <= listEnd {
                #expect(complete(page) == complete(fromGoalLogList(day)), comment)
            }
        }
        let run = try #require(store.content.goals.first { $0.name == "Koşu" })
        let rows = try await store.computeGoalStatuses(today: now)
        let chain = try #require(rows.first { $0.definition.id == run.id }?.status)
        #expect(chain.streak == 520 && chain.longestStreak == 520, "the list shows a chain longer than the list")
        // The intended change: a day beyond the goal-log list counts its own log (Koşu, its copy
        // counted as Koşu, Su).
        for offset in [-450, 10] {
            let day = try #require(now.addingDays(offset))
            let page = TodayPresentation.goalStatuses(try await store.computeGoalStatuses(today: day))
            #expect(complete(page) == [true, true, false], Comment(rawValue: "\(offset)"))
            #expect(complete(fromGoalLogList(day)) == [false, false, false], Comment(rawValue: "\(offset)"))
        }

        // "Close the day": the copy of Koşu counts as Koşu, done; only Su is left.
        let flow = try await CloseDayModel.opened(store: store, today: now)
        let old = fromGoalLogList(now)
        #expect(flow.pendingGoals.map(\.name) == ["Su"])
        #expect(flow.pendingGoals == daily.filter { old[$0.key]?.progress.isComplete != true })
    }
}

/// Goal files and day files for the edge cases, dated around `now`.
private enum EdgeGoalVault {
    static func write(at root: URL, now: CalendarDate) throws {
        let goals: [(String, String)] = [
            ("Koşu", "key: kosu\nperiod: day\nkind: boolean\ntarget: 1"),
            // A copied file: same key, another kind. A boolean value is no amount for it.
            ("Koşu kopya", "key: kosu\nperiod: day\nkind: number\ntarget: 5"),
            ("Su", "key: su\nperiod: day\nkind: boolean\ntarget: 1"),
            ("Kitap yılı", "key: kitap\nperiod: year\nkind: number\ntarget: 3"),
            ("Maraton", "key: maraton\nperiod: year\nkind: milestone"),
            ("Boş", "key: bos\nperiod: week\nkind: boolean\ntarget: 3"),
        ]
        for (name, fields) in goals {
            try file(root, "goals/\(name).md", "---\ntype: goal\nname: \(name)\n\(fields)\n---\n")
        }
        for offset in -520...10 where offset <= 0 || offset == 3 || offset == 10 {
            guard let day = now.addingDays(offset) else { continue }
            var lines = ["  kosu: \(offset != -10)"]
            if offset == 0 || offset == -1 { lines.append("  kitap: 2") }
            if offset == -2 { lines.append("  maraton: true") }
            try file(
                root, "journal/\(day).md",
                "---\ntype: journal\ndate: \(day)\ngoals:\n" + lines.joined(separator: "\n") + "\n---\n")
        }
    }

    private static func file(_ root: URL, _ path: String, _ text: String) throws {
        let url = root.appendingPathComponent(path)
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data(text.utf8).write(to: url)
    }
}

#if os(macOS)
    import Observation
    import SwiftUI

    /// While the goal-status answer is on its way the goal list and the day page keep what they
    /// drew, and take the new answer when it comes. Read from the accessibility tree of the
    /// mounted view (`HostedAccessibilityTree`), with the store's goal-status query held at a gate.
    @MainActor @Suite(.timeLimit(.minutes(1)))
    struct GoalScreenLoadingTests {
        private let watchdog = HostedTestWatchdog()

        @Test func goalListKeepsItsStatusesWhileTheReloadIsOnItsWay() async throws {
            let context = try TaskTestContext(sample: true)
            defer { context.clean() }
            await context.start()
            let store = context.store
            let day = context.today
            let gate = GoalQueryGate(store: store)
            let water = try #require(store.content.goals.first { $0.key == "su" })
            func value() async throws -> String {
                let rows = try await store.computeGoalStatuses(today: day)
                let status = try #require(rows.first { $0.definition.id == water.id }?.status)
                return try #require(GoalRowPresentation.valueText(goal: water, status: status))
            }
            let before = try await value()
            let amount = (try #require(Double(before.prefix { $0 != "/" }))) == 7 ? 6.0 : 7.0
            let after = "\(amount.formatted())/\(water.target.formatted()) bardak"
            #expect(before != after)

            // The first answer is held: the page is up, no row is drawn without its status.
            gate.hold()
            let now = LocalDay.instant(for: day)
            let list = GoalsView(store: store).environment(\.clockNow, { now })
            let mount = HostedLayout.Mount(
                Self.environment(NavigationStack { list }, context: context), size: CGSize(width: 420, height: 900))
            defer { mount.close() }
            // A row reads as one element: name, meta, then the value.
            func row() -> String? { Self.texts(mount).first { $0.hasPrefix(water.name + ",") } }
            func shows(_ text: String) -> Bool { row()?.hasSuffix(", " + text) == true }
            let newGoal = String(localized: "Yeni hedef")
            guard await HostedAccessibilityTree.isAvailable(mount, until: { Self.texts(mount).contains(newGoal) })
            else { return }
            for _ in 0..<40 where gate.heldCount == 0 { await mount.settle(rounds: 1) }
            #expect(gate.heldCount == 1)
            await mount.settle()
            #expect(row() == nil, "no row is drawn before the first answer")
            #expect(!Self.texts(mount).contains(String(localized: "Henüz hedef yok")), "nor the empty list")
            gate.release()
            for _ in 0..<40 where !shows(before) { await mount.settle(rounds: 1) }
            #expect(shows(before))

            gate.hold()
            try await store.setGoal(on: day, key: "su", value: .number(amount))
            for _ in 0..<40 where gate.heldCount == 0 { await mount.settle(rounds: 1) }
            #expect(gate.heldCount > 0, "the publish asks for the statuses again")
            await mount.settle()
            #expect(shows(before), "the list keeps the status it drew")
            #expect(!shows(after))

            gate.release()
            for _ in 0..<40 where !shows(after) { await mount.settle(rounds: 1) }
            #expect(shows(after))
            #expect(!shows(before))
            #expect(try await value() == after)
        }

        @Test func dayPageKeepsItsGoalCounterWhileTheReloadIsOnItsWay() async throws {
            let context = try TaskTestContext(sample: true)
            defer { context.clean() }
            await context.start()
            let store = context.store
            let day = context.today
            let gate = GoalQueryGate(store: store)
            let mount = HostedLayout.Mount(
                Self.environment(NavigationStack { DayView(store: store, date: day) }, context: context),
                size: CGSize(width: 720, height: 1600))
            defer { mount.close() }
            let water = try #require(store.content.goals.first { $0.key == "su" })
            /// The page's goal counter from statuses by key.
            func counter(_ statuses: [String: GoalStatus]) -> String {
                let daily = store.content.goals.filter { $0.period == .day }
                return "\(daily.filter { statuses[$0.key]?.progress.isComplete == true }.count)/\(daily.count)"
            }
            let queried = TodayPresentation.goalStatuses(try await store.computeGoalStatuses(today: day))
            let before = counter(queried)
            let marked = queried["su"]?.progress.isComplete == true
            func shows(_ text: String) -> Bool { Self.texts(mount).contains { $0.hasSuffix(", " + text) } }
            // Until its first answer the strip counts from its own model: wait for the answer.
            guard await HostedAccessibilityTree.isAvailable(mount, until: { shows(before) && gate.passedCount > 0 })
            else { return }
            await mount.settle()

            gate.hold()
            try await store.setGoal(on: day, key: "su", value: .number(marked ? 0 : water.target))
            // The old construction over the published content; the query is held.
            let after = counter(store.content.goalStatuses(today: day))
            #expect(after != before)
            for _ in 0..<40 where gate.heldCount == 0 { await mount.settle(rounds: 1) }
            #expect(gate.heldCount > 0, "the publish asks for the statuses again")
            await mount.settle()
            #expect(shows(before), "the page keeps the counter it drew")
            #expect(!shows(after))

            gate.release()
            for _ in 0..<40 where !shows(after) { await mount.settle(rounds: 1) }
            #expect(shows(after))
            #expect(counter(TodayPresentation.goalStatuses(try await store.computeGoalStatuses(today: day))) == after)
        }

        /// Until a day's own statuses come, the goal strip counts from its own model: the page never
        /// shows `0/0` over its goal rows, nor the previous day's count after moving to another day.
        @Test func dayPageCountsItsGoalsFromTheStripUntilTheDaysStatusesCome() async throws {
            let context = try TaskTestContext(sample: true)
            defer { context.clean() }
            await context.start()
            let store = context.store
            let first = context.today
            func counter(_ day: CalendarDate) async throws -> String {
                let statuses = TodayPresentation.goalStatuses(try await store.computeGoalStatuses(today: day))
                let daily = store.content.goals.filter { $0.period == .day }
                return "\(daily.filter { statuses[$0.key]?.progress.isComplete == true }.count)/\(daily.count)"
            }
            let firstCounter = try await counter(first)
            // A day whose count differs, so the first day's answer cannot pass for it.
            var second: CalendarDate?
            var secondCounter = firstCounter
            for offset in 1...30 where second == nil {
                let day = try #require(first.addingDays(-offset))
                let value = try await counter(day)
                if value != firstCounter { (second, secondCounter) = (day, value) }
            }
            let next = try #require(second)
            #expect(firstCounter != "0/0" && secondCounter != "0/0")

            let gate = GoalQueryGate(store: store)
            gate.hold()
            let shown = ShownDay(first)
            let mount = HostedLayout.Mount(
                Self.environment(NavigationStack { ShownDayPage(store: store, shown: shown) }, context: context),
                size: CGSize(width: 720, height: 1600))
            defer { mount.close() }
            func shows(_ text: String) -> Bool { Self.texts(mount).contains { $0.hasSuffix(", " + text) } }
            // The strip draws its own count at once; the page's first answer is held meanwhile.
            guard
                await HostedAccessibilityTree.isAvailable(
                    mount, until: { shows(firstCounter) && gate.heldCount > 0 })
            else { return }
            await mount.settle()
            #expect(gate.heldCount > 0 && gate.passedCount == 0, "the first answer is still held")
            #expect(shows(firstCounter))
            #expect(!shows("0/0"))

            gate.release()
            for _ in 0..<40 where gate.heldCount > 0 { await mount.settle(rounds: 1) }
            await mount.settle()
            #expect(shows(firstCounter))

            // The page holds the first day's statuses; the next day's are held.
            gate.hold()
            shown.day = next
            for _ in 0..<40 where gate.heldCount == 0 { await mount.settle(rounds: 1) }
            #expect(gate.heldCount > 0, "the new day asks for its statuses")
            for _ in 0..<40 where !shows(secondCounter) { await mount.settle(rounds: 1) }
            #expect(shows(secondCounter))
            #expect(!shows(firstCounter), "the first day's count is not drawn for the next")
            #expect(!shows("0/0"))

            gate.release()
            for _ in 0..<40 where gate.heldCount > 0 { await mount.settle(rounds: 1) }
            await mount.settle()
            #expect(shows(secondCounter) && !shows(firstCounter))
        }

        /// An answer overtaken by a newer one (its request was replaced while it ran) is not drawn
        /// over the newer one, on the day page and in the list.
        @Test func goalScreensDropAnAnswerANewerOneOvertook() async throws {
            let context = try TaskTestContext(sample: true)
            defer { context.clean() }
            await context.start()
            let store = context.store
            let day = context.today
            let water = try #require(store.content.goals.first { $0.key == "su" })
            let original = store.content.goalLogs["su"]?.last { $0.day == day }?.value ?? .number(1)
            try await store.setGoal(on: day, key: "su", value: original)
            let marked = original == .number(water.target)
            let other = GoalValue.number(marked ? 0 : water.target)
            func statuses() async throws -> [String: GoalStatus] {
                TodayPresentation.goalStatuses(try await store.computeGoalStatuses(today: day))
            }
            func counter(_ statuses: [String: GoalStatus]) -> String {
                let daily = store.content.goals.filter { $0.period == .day }
                return "\(daily.filter { statuses[$0.key]?.progress.isComplete == true }.count)/\(daily.count)"
            }
            func value(_ statuses: [String: GoalStatus]) throws -> String {
                let status = try #require(statuses["su"])
                return try #require(GoalRowPresentation.valueText(goal: water, status: status))
            }
            let before = try await statuses()
            try await store.setGoal(on: day, key: "su", value: other)
            let changed = try await statuses()
            try await store.setGoal(on: day, key: "su", value: original)
            let (beforeCounter, changedCounter) = (counter(before), counter(changed))
            let (beforeValue, changedValue) = (try value(before), try value(changed))
            #expect(beforeCounter != changedCounter && beforeValue != changedValue)

            let gate = GoalQueryGate(store: store)
            let now = LocalDay.instant(for: day)
            let mount = HostedLayout.Mount(
                Self.environment(
                    HStack {
                        NavigationStack { DayView(store: store, date: day) }
                        NavigationStack { GoalsView(store: store).environment(\.clockNow, { now }) }
                    }, context: context),
                size: CGSize(width: 1200, height: 1600))
            defer { mount.close() }
            func shows(_ text: String) -> Bool { Self.texts(mount).contains { $0.hasSuffix(", " + text) } }
            // Both screens have their first answers (the page's counter, the list's row).
            guard
                await HostedAccessibilityTree.isAvailable(
                    mount, until: { shows(beforeCounter) && shows(beforeValue) && gate.passedCount >= 2 })
            else { return }
            await mount.settle()

            // The first edit's answers are held; the second edit replaces their requests.
            gate.hold()
            try await store.setGoal(on: day, key: "su", value: other)
            for _ in 0..<40 where gate.heldCount < 2 { await mount.settle(rounds: 1) }
            try await store.setGoal(on: day, key: "su", value: original)
            for _ in 0..<40 where gate.heldCount < 4 { await mount.settle(rounds: 1) }
            try #require(gate.heldCount == 4)
            // The newer answers first, then the overtaken ones.
            gate.releaseNewest()
            gate.releaseNewest()
            await mount.settle()
            gate.release()
            await mount.settle()
            #expect(shows(beforeCounter) && !shows(changedCounter), "the page keeps the newer answer")
            #expect(shows(beforeValue) && !shows(changedValue), "the list keeps the newer answer")
        }

        /// A copied goal file with the same key draws its own status in the list, as the editing
        /// model drew it before the query: the copy (a number goal) is not shown with the first
        /// definition's amount.
        @Test func goalListDrawsACopiedKeyWithItsOwnStatus() async throws {
            let context = try TaskTestContext()
            defer { context.clean() }
            let now = LocalDay.today()
            try EdgeGoalVault.write(at: context.root, now: now)
            await context.start()
            let store = context.store
            let run = try #require(store.content.goals.first { $0.name == "Koşu" })
            let copy = try #require(store.content.goals.first { $0.name == "Koşu kopya" })
            let editing = GoalDayModel(store: store, day: now)
            await editing.load()
            let own = try #require(GoalRowPresentation.valueText(goal: copy, status: editing.status(for: copy)))
            let first = try #require(GoalRowPresentation.valueText(goal: copy, status: editing.status(for: run)))
            #expect(own != first)

            let clock = LocalDay.instant(for: now)
            let mount = HostedLayout.Mount(
                Self.environment(
                    NavigationStack { GoalsView(store: store).environment(\.clockNow, { clock }) }, context: context),
                size: CGSize(width: 420, height: 900))
            defer { mount.close() }
            func row() -> String? { Self.texts(mount).first { $0.hasPrefix(copy.name + ",") } }
            guard await HostedAccessibilityTree.isAvailable(mount, until: { row() != nil }) else { return }
            await mount.settle()
            #expect(row()?.hasSuffix(", " + own) == true)
            #expect(row()?.hasSuffix(", " + first) == false)
        }

        /// At midnight the list asks for the new day's statuses and keeps its rows until they come.
        @Test func goalListAsksAgainAtMidnightAndKeepsItsRowsMeanwhile() async throws {
            let context = try TaskTestContext(sample: true)
            defer { context.clean() }
            await context.start()
            let store = context.store
            let day = context.today
            let next = try #require(day.addingDays(1))
            let water = try #require(store.content.goals.first { $0.key == "su" })
            try await store.setGoal(on: day, key: "su", value: .number(water.target))
            try await store.setGoal(on: next, key: "su", value: .number(1))
            func value(_ day: CalendarDate) async throws -> String {
                let rows = try await store.computeGoalStatuses(today: day)
                let status = try #require(rows.first { $0.definition.id == water.id }?.status)
                return try #require(GoalRowPresentation.valueText(goal: water, status: status))
            }
            let before = try await value(day)
            let after = try await value(next)
            #expect(before != after)

            let gate = GoalQueryGate(store: store)
            let clock = ShownDay(day)
            let mount = HostedLayout.Mount(
                Self.environment(NavigationStack { ClockedGoalList(store: store, clock: clock) }, context: context),
                size: CGSize(width: 420, height: 900))
            defer { mount.close() }
            func row() -> String? { Self.texts(mount).first { $0.hasPrefix(water.name + ",") } }
            func shows(_ text: String) -> Bool { row()?.hasSuffix(", " + text) == true }
            guard await HostedAccessibilityTree.isAvailable(mount, until: { shows(before) }) else { return }

            gate.hold()
            clock.day = next
            for _ in 0..<40 where gate.heldCount == 0 { await mount.settle(rounds: 1) }
            #expect(gate.heldCount > 0, "the new day asks for its statuses")
            await mount.settle()
            #expect(shows(before), "the rows stay until the new day's answer")

            gate.release()
            for _ in 0..<40 where !shows(after) { await mount.settle(rounds: 1) }
            #expect(shows(after))
        }

        private static func environment(_ view: some View, context: TaskTestContext) -> some View {
            let defaults = context.defaults.defaults
            return
                view
                .environment(NotificationService(center: FakeNotificationCenter(), defaults: defaults))
                .environment(CalendarService(source: GoalQuietCalendarSource()))
                .environment(LocationService(source: FakeLocationSource(), defaults: defaults))
                .environment(IntentNavigation())
        }

        private static func texts(_ mount: HostedLayout.Mount) -> [String] {
            HostedAccessibilityTree.texts(under: mount)
        }
    }

    /// A day the test moves: the page shown, or the clock's day.
    @MainActor @Observable private final class ShownDay {
        var day: CalendarDate
        init(_ day: CalendarDate) { self.day = day }
    }

    /// A pushed day page whose date the test changes in place, as the day pager does.
    private struct ShownDayPage: View {
        let store: IndexStore
        let shown: ShownDay
        var body: some View { DayView(store: store, date: shown.day) }
    }

    /// The goal list under a clock the test moves past midnight.
    private struct ClockedGoalList: View {
        let store: IndexStore
        let clock: ShownDay
        var body: some View {
            let now = LocalDay.instant(for: clock.day)
            GoalsView(store: store).environment(\.clockNow, { now })
        }
    }

    @MainActor private final class GoalQuietCalendarSource: CalendarEventSource {
        var authorization = CalendarAuthorization.denied
        var onChange: (@MainActor @Sendable () -> Void)?
        func requestFullAccess() async throws -> Bool { false }
        func events(from start: Date, to end: Date) async throws -> [CalendarEvent] { [] }
    }
#endif

/// Holds the goal-status query's answers at its test seam until released.
@MainActor final class GoalQueryGate {
    private var isHolding = false
    private var held: [CheckedContinuation<Void, Never>] = []

    init(store: IndexStore) {
        store.testingGoalStatusQueryDidFinish = { [weak self] in await self?.pass() }
    }

    /// Answers waiting at the gate.
    var heldCount: Int { held.count }
    /// Answers that went through without being held.
    private(set) var passedCount = 0

    func hold() { isHolding = true }

    /// Lets every held answer through; later ones pass straight on.
    func release() {
        isHolding = false
        let waiting = held
        held = []
        for continuation in waiting { continuation.resume() }
    }

    /// Lets only the latest held answer through; the older ones stay held.
    func releaseNewest() {
        held.popLast()?.resume()
    }

    private func pass() async {
        guard isHolding else {
            passedCount += 1
            return
        }
        await withCheckedContinuation { held.append($0) }
    }
}
