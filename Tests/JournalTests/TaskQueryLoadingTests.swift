#if os(macOS)
    import AppKit
    import Foundation
    import SwiftUI
    import Testing
    import VaultFormat

    @testable import Journal

    /// The Tasks list queries the index on demand. While an answer is on its way the list keeps the
    /// rows it drew (completing a task must not blank it for a moment) and the Mac detail keeps its
    /// selection; the answer is taken when it comes. Read from the accessibility tree SwiftUI builds
    /// for the mounted list, with the store's task queries held at the gate.
    @MainActor @Suite(.timeLimit(.minutes(1)))
    struct TaskQueryLoadingTests {
        private let watchdog = HostedTestWatchdog()

        @Test func listKeepsItsRowsWhileACompletionReloads() async throws {
            let context = try TaskTestContext(sample: true)
            defer { context.clean() }
            await context.start()
            let store = context.store
            let day = try #require(CalendarDate("2026-09-20"))
            let model = TasksModel(store: store, today: { day })
            let gate = TaskQueryGate(store: store)
            let mount = HostedLayout.Mount(
                Self.environment(NavigationStack { TasksView(store: store, tasks: model) }, context: context),
                size: CGSize(width: 720, height: 2400))
            defer { mount.close() }
            let expected = try await Self.agendaTexts(store, day: day)
            let known = Set(expected)
            func listed() -> [String] { Self.listed(mount, among: known) }
            guard await HostedAccessibilityTree.isAvailable(mount, until: { listed() == expected }) else { return }

            gate.hold()
            let row = try #require(model.agenda.flatMap(\.rows).last { $0.recurrence == nil })
            #expect(await model.toggle(row))
            for _ in 0..<40 where gate.heldCount == 0 { await mount.settle(rounds: 1) }
            #expect(gate.heldCount > 0, "the publish asks for the list again")
            await mount.settle()
            #expect(listed() == expected, "the list keeps its rows")

            gate.release()
            let after = expected.filter { $0 != row.text.plainText }
            for _ in 0..<40 where listed() != after { await mount.settle(rounds: 1) }
            #expect(listed() == after)
        }

        @Test func macSelectionStaysWhileTheListReloadsAndLeavesWithItsRow() async throws {
            let context = try TaskTestContext(sample: true)
            defer { context.clean() }
            await context.start()
            let store = context.store
            let day = try #require(CalendarDate("2026-09-20"))
            let model = TasksModel(store: store, today: { day })
            await model.loadList()
            let rows = model.agenda.flatMap(\.rows).filter { $0.recurrence == nil }
            let selected = try #require(rows.first)
            let completed = try #require(rows.last)
            #expect(selected.id != completed.id)
            let probe = TaskSelectionProbe(selected.id)
            let gate = TaskQueryGate(store: store)
            let list = TasksView(
                store: store, selection: Binding(get: { probe.selection }, set: { probe.set($0) }), tasks: model)
            let mount = HostedLayout.Mount(
                Self.environment(NavigationStack { list }, context: context), size: CGSize(width: 720, height: 2400))
            defer { mount.close() }
            let expected = try await Self.agendaTexts(store, day: day)
            let known = Set(expected)
            guard
                await HostedAccessibilityTree.isAvailable(
                    mount, until: { Self.listed(mount, among: known) == expected })
            else { return }
            #expect(probe.selection == selected.id && probe.changes.allSatisfy { $0 == selected.id })

            gate.hold()
            #expect(await model.toggle(completed))
            for _ in 0..<40 where gate.heldCount == 0 { await mount.settle(rounds: 1) }
            #expect(gate.heldCount > 0)
            await mount.settle()
            #expect(Self.listed(mount, among: known) == expected, "the list keeps its rows")
            #expect(probe.selection == selected.id, "the selection stays while the answer is on its way")

            gate.release()
            let after = expected.filter { $0 != completed.text.plainText }
            for _ in 0..<40 where Self.listed(mount, among: known) != after { await mount.settle(rounds: 1) }
            #expect(Self.listed(mount, among: known) == after)
            #expect(probe.selection == selected.id && probe.changes.allSatisfy { $0 == selected.id })

            // The selected row itself leaves the list: the detail clears with the answer.
            gate.hold()
            #expect(await model.toggle(selected))
            for _ in 0..<40 where gate.heldCount == 0 { await mount.settle(rounds: 1) }
            await mount.settle()
            #expect(probe.selection == selected.id, "nothing changes before the answer")
            gate.release()
            for _ in 0..<40 where probe.selection != nil { await mount.settle(rounds: 1) }
            #expect(probe.selection == nil)
        }

        /// The agenda rows' texts as the list draws them, from the store's query.
        private static func agendaTexts(_ store: IndexStore, day: CalendarDate) async throws -> [String] {
            let model = TasksModel(store: store, today: { day })
            await model.loadList()
            let texts = model.agenda.flatMap(\.rows).map(\.text.plainText)
            #expect(texts.count > 3 && Set(texts).count == texts.count)
            return texts
        }

        /// The texts of `known` rows on screen, in tree order.
        private static func listed(_ mount: HostedLayout.Mount, among known: Set<String>) -> [String] {
            var seen = Set<String>()
            return HostedAccessibilityTree.texts(under: mount).filter { known.contains($0) && seen.insert($0).inserted }
        }

        private static func environment(_ view: some View, context: TaskTestContext) -> some View {
            let defaults = context.defaults.defaults
            return
                view
                .environment(NotificationService(center: FakeNotificationCenter(), defaults: defaults))
                .environment(CalendarService(source: SilentCalendarSource()))
                .environment(LocationService(source: FakeLocationSource(), defaults: defaults))
                .environment(IntentNavigation())
        }
    }

    @MainActor private final class TaskSelectionProbe {
        private(set) var selection: String?
        private(set) var changes: [String?] = []

        init(_ selection: String?) { self.selection = selection }

        func set(_ value: String?) {
            changes.append(value)
            selection = value
        }
    }

    @MainActor private final class SilentCalendarSource: CalendarEventSource {
        var authorization = CalendarAuthorization.denied
        var onChange: (@MainActor @Sendable () -> Void)?
        func requestFullAccess() async throws -> Bool { false }
        func events(from start: Date, to end: Date) async throws -> [CalendarEvent] { [] }
    }
#endif
