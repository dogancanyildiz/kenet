#if os(macOS)
    import AppKit
    import Foundation
    import SwiftUI
    import Testing
    import VaultFormat

    @testable import Journal

    /// The day screens query the index on demand. While an answer is on its way the screen keeps
    /// what it drew (a new event must not blank the page for a moment) and takes the answer when it
    /// comes. Read from the accessibility tree SwiftUI builds for the mounted page, with the store's
    /// day queries held at the gate.
    @MainActor @Suite(.timeLimit(.minutes(1)))
    struct DayQueryLoadingTests {
        private let watchdog = HostedTestWatchdog()

        @Test func dayPageKeepsItsDayWhileTheReloadIsOnItsWay() async throws {
            let context = try TaskTestContext(sample: true)
            defer { context.clean() }
            await context.start()
            let store = context.store
            let day = try #require(CalendarDate("2026-09-20"))
            let gate = DayQueryGate(store: store)
            let mount = HostedLayout.Mount(
                Self.environment(NavigationStack { DayView(store: store, date: day) }, context: context),
                size: CGSize(width: 720, height: 1600))
            defer { mount.close() }
            let before = try await store.computeDay(on: day).events.map(\.text.plainText)
            let added = "Yükleme anı"
            let known = Set(before + [added])
            func events() -> [String] { Self.texts(mount).filter(known.contains) }
            #expect(!before.isEmpty)
            guard await HostedAccessibilityTree.isAvailable(mount, until: { events() == before }) else { return }

            gate.hold()
            #expect(await store.addEvent(on: day, text: added, time: nil))
            for _ in 0..<40 where gate.heldCount == 0 { await mount.settle(rounds: 1) }
            #expect(gate.heldCount > 0, "the publish asks for the day again")
            await mount.settle()
            #expect(events() == before, "the page keeps the day it drew")

            gate.release()
            for _ in 0..<40 where events() == before { await mount.settle(rounds: 1) }
            #expect(events() == before + [added])
        }

        @Test func dayColumnKeepsItsRowsAndSelectionWhileTheReloadIsOnItsWay() async throws {
            let context = try TaskTestContext(sample: true)
            defer { context.clean() }
            await context.start()
            let store = context.store
            let day = try #require(CalendarDate("2026-09-20"))
            let selected = "journal/\(day).md"
            let probe = SelectionProbe(selected)
            let gate = DayQueryGate(store: store)
            let column = MacDaysColumn(
                store: store, selection: Binding(get: { probe.selection }, set: { probe.set($0) }), openSummaries: {})
            let mount = HostedLayout.Mount(
                Self.environment(column, context: context), size: CGSize(width: 360, height: 2400))
            defer { mount.close() }
            let rows = try await store.computeDaySummaries().map(Self.rowLabel)
            guard await HostedAccessibilityTree.isAvailable(mount, until: { Self.rows(mount, among: rows) == rows })
            else { return }
            // The column opens with no rows while the first answer is on its way; the selection
            // made before (a task's day, the calendar) is not dropped meanwhile.
            #expect(probe.selection == selected && probe.changes.allSatisfy { $0 == selected })

            gate.hold()
            #expect(await store.addEvent(on: day, text: "Yükleme anı", time: nil))
            for _ in 0..<40 where gate.heldCount == 0 { await mount.settle(rounds: 1) }
            #expect(gate.heldCount > 0, "the publish asks for the days again")
            await mount.settle()
            #expect(Self.rows(mount, among: rows) == rows, "the column keeps its rows")

            gate.release()
            let updated = try await store.computeDaySummaries().map(Self.rowLabel)
            #expect(updated != rows)
            for _ in 0..<40 where Self.rows(mount, among: updated) != updated { await mount.settle(rounds: 1) }
            #expect(Self.rows(mount, among: updated) == updated)
            #expect(probe.selection == selected && probe.changes.allSatisfy { $0 == selected })
        }

        /// The month arrows step from the month asked for, not from the one still on screen: two
        /// steps before the first month's answer arrives land two months on. Until the first answer
        /// the days are not drawn, so the month never shows without its marks.
        @Test func calendarStepsFromTheAskedMonthAndDrawsDaysWithTheirMarks() async throws {
            let context = try TaskTestContext(sample: true)
            defer { context.clean() }
            await context.start()
            let store = context.store
            let gate = DayQueryGate(store: store)
            gate.hold()
            let now = LocalDay.instant(for: try #require(CalendarDate("2026-09-20")))
            let calendar = DaysCalendarView(store: store) { _ in }.environment(\.clockNow, { now })
            let mount = HostedLayout.Mount(
                Self.environment(calendar, context: context), size: CGSize(width: 360, height: 420))
            defer { mount.close() }
            let september = Self.monthTitle("2026-09-01")
            guard await HostedAccessibilityTree.isAvailable(mount, until: { Self.texts(mount).contains(september) })
            else { return }
            for _ in 0..<40 where gate.heldCount == 0 { await mount.settle(rounds: 1) }
            #expect(gate.heldCount == 1)
            await mount.settle()
            let twentieth = Self.dayLabel("2026-09-20")
            #expect(!Self.texts(mount).contains(twentieth), "no day is drawn before the first answer")
            gate.release()
            for _ in 0..<40 where !Self.texts(mount).contains(twentieth) { await mount.settle(rounds: 1) }
            #expect(Self.texts(mount).contains(twentieth))

            gate.hold()
            let next = try #require(
                HostedAccessibilityTree.element(under: mount, labelled: String(localized: "Sonraki ay")))
            HostedAccessibilityTree.press(next)
            await mount.settle()
            HostedAccessibilityTree.press(next)
            await mount.settle()
            #expect(gate.heldCount > 0)
            #expect(Self.texts(mount).contains(twentieth), "the month on screen stays until the asked one answers")

            gate.release()
            let november = Self.dayLabel("2026-11-20")
            for _ in 0..<40 where !Self.texts(mount).contains(november) { await mount.settle(rounds: 1) }
            #expect(Self.texts(mount).contains(november))
            #expect(Self.texts(mount).contains(Self.monthTitle("2026-11-01")))
            #expect(!Self.texts(mount).contains(Self.dayLabel("2026-10-20")))
        }

        private static func environment(_ view: some View, context: TaskTestContext) -> some View {
            let defaults = context.defaults.defaults
            return
                view
                .environment(NotificationService(center: FakeNotificationCenter(), defaults: defaults))
                .environment(CalendarService(source: QuietCalendarSource()))
                .environment(LocationService(source: FakeLocationSource(), defaults: defaults))
                .environment(IntentNavigation())
        }

        /// The listed rows of `labels`, in the order the column shows them.
        private static func rows(_ mount: HostedLayout.Mount, among labels: [String]) -> [String] {
            let wanted = Set(labels)
            return HostedAccessibilityTree.labels(under: mount).filter(wanted.contains)
        }

        private static func texts(_ mount: HostedLayout.Mount) -> [String] {
            HostedAccessibilityTree.texts(under: mount)
        }

        private static func rowLabel(_ day: DayOverview) -> String {
            VoiceOverCopy.dayRowLabel(date: day.date, eventCount: day.eventCount, preview: day.preview)
        }

        private static func monthTitle(_ first: String) -> String {
            LocalDay.instant(for: CalendarDate(first)!).formatted(.dateTime.month(.wide).year())
        }

        private static func dayLabel(_ date: String) -> String {
            LocalDay.instant(for: CalendarDate(date)!).formatted(.dateTime.day().month().year())
        }
    }

    @MainActor private final class SelectionProbe {
        private(set) var selection: String?
        private(set) var changes: [String?] = []

        init(_ selection: String?) { self.selection = selection }

        func set(_ value: String?) {
            changes.append(value)
            selection = value
        }
    }

    @MainActor private final class QuietCalendarSource: CalendarEventSource {
        var authorization = CalendarAuthorization.denied
        var onChange: (@MainActor @Sendable () -> Void)?
        func requestFullAccess() async throws -> Bool { false }
        func events(from start: Date, to end: Date) async throws -> [CalendarEvent] { [] }
    }

    /// SwiftUI's accessibility nodes answer the accessibility messages without adopting the Swift
    /// protocol, so they are read through selectors.
    @MainActor enum HostedAccessibilityTree {
        private static let label = NSSelectorFromString("accessibilityLabel")
        private static let value = NSSelectorFromString("accessibilityValue")
        private static let children = NSSelectorFromString("accessibilityChildren")
        private static let pressSelector = NSSelectorFromString("accessibilityPerformPress")

        /// SwiftUI builds the tree only once an assistive client has asked the process something.
        /// A machine that still gives no tree has nothing to measure: the test returns with a note.
        static func isAvailable(
            _ mount: HostedLayout.Mount, until ready: () -> Bool, test: String = #function
        ) async -> Bool {
            _ = AXUIElementSetAttributeValue(
                AXUIElementCreateApplication(getpid()), "AXManualAccessibility" as CFString, kCFBooleanTrue)
            for _ in 0..<60 where !ready() { await mount.settle(rounds: 1) }
            if ready() { return true }
            if texts(under: mount).isEmpty {
                if HostedControls.requiresTree {
                    Issue.record("No accessibility tree, and KENET_REQUIRE_AX asks for one: \(test)")
                } else {
                    FileHandle.standardError.write(
                        Data("ATLANDI (ortam erişilebilirlik ağacı vermiyor): \(test)\n".utf8))
                }
                return false
            }
            Issue.record("The mounted view never showed its first answer")
            return false
        }

        /// Every label and text value under the hosted root, in tree order.
        static func texts(under mount: HostedLayout.Mount) -> [String] {
            var found: [String] = []
            walk(mount.window.contentView as Any) { node in
                for selector in [label, value] {
                    if let text = string(node, selector), !text.isEmpty { found.append(text) }
                }
            }
            return found
        }

        /// Every label under the hosted root, in tree order.
        static func labels(under mount: HostedLayout.Mount) -> [String] {
            var found: [String] = []
            walk(mount.window.contentView as Any) { node in
                if let text = string(node, label), !text.isEmpty { found.append(text) }
            }
            return found
        }

        static func element(under mount: HostedLayout.Mount, labelled text: String) -> NSObject? {
            var match: NSObject?
            walk(mount.window.contentView as Any) { node in
                if match == nil, string(node, label) == text { match = node }
            }
            return match
        }

        static func press(_ node: NSObject) {
            _ = node.perform(pressSelector)
        }

        private static func string(_ node: NSObject, _ selector: Selector) -> String? {
            guard node.responds(to: selector) else { return nil }
            return node.perform(selector)?.takeUnretainedValue() as? String
        }

        /// The accessibility children, and for a view its subviews too: a Mac list's rows are
        /// reached through the table's views. Each node is visited once.
        private static func walk(_ root: Any, _ visit: (NSObject) -> Void) {
            var seen = Set<ObjectIdentifier>()
            func step(_ item: Any) {
                guard let node = item as? NSObject, seen.insert(ObjectIdentifier(node)).inserted else { return }
                visit(node)
                if node.responds(to: children), let nodes = node.perform(children)?.takeUnretainedValue() as? [Any] {
                    nodes.forEach(step)
                }
                (node as? NSView)?.subviews.forEach(step)
            }
            step(root)
        }
    }
#endif
